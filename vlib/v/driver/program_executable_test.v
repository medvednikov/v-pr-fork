module driver

import os
import time
import v.modulecache

fn link_inputs_fixture(name string) string {
	root := os.join_path(os.vtmp_dir(), 'v3_driver_${name}_${os.getpid()}')
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	return root
}

fn test_program_link_inputs_are_the_files_and_library_candidates_of_a_link() {
	root := link_inputs_fixture('program_link_inputs')
	defer {
		os.rmdir_all(root) or {}
	}
	first := os.join_path(root, 'first')
	second := os.join_path(root, 'second')
	linker := os.join_path(root, 'linker')
	system := os.join_path(root, 'system')
	for dir in [first, second, linker, system] {
		os.mkdir_all(dir)!
	}
	object := os.join_path(root, 'module.o')
	archive := os.join_path(second, 'libfoo.a')
	runtime := os.join_path(linker, 'libruntime.a')
	system_library := os.join_path(system, 'libbar.so')
	for file in [object, archive, runtime, os.join_path(linker, 'notes.txt')] {
		os.write_file(file, '!<arch>\nx')!
	}
	os.write_file(system_library, '\x7fELF\x00')!
	gone := os.join_path(root, 'gone.o')
	absent_dir := os.join_path(root, 'absent')
	inputs := v3_program_link_inputs(['-std=gnu11', '-o', 'out', 'src.c', object, gone, '-L${first}',
		'-L', second, '-lfoo', '-l', 'bar', '-I${root}', '-Wl,-rpath,${root}', '-L${absent_dir}'],
		linker, [system], '')
	assert inputs.taken && inputs.unknown == ''
	assert inputs.files == [runtime, object, archive, system_library].sorted()
	assert inputs.identities == inputs.files.map(modulecache.file_metadata_signature(it))
	// The link reads `libfoo.a` of the second directory because no library of that
	// name is in the first, or before it in the second; `libbar.so` of the system
	// because none is in a directory of `-L`.
	for candidate in [gone, os.join_path(first, 'libfoo.dylib'), os.join_path(first, 'libfoo.a'),
		os.join_path(second, 'libfoo.dylib'), os.join_path(first, 'libbar.a'),
		os.join_path(second, 'libbar.so'), os.join_path(system, 'libfoo.a'), absent_dir] {
		assert candidate in inputs.missing, candidate
	}
	assert archive !in inputs.missing
	// What is relative to the build directory is made anew by every build.
	assert inputs.files.all(os.is_abs_path(it)) && inputs.missing.all(os.is_abs_path(it))
}

fn test_program_link_inputs_include_the_files_of_linker_options() {
	root := link_inputs_fixture('program_link_options')
	defer {
		os.rmdir_all(root) or {}
	}
	names := ['direct.a', 'whole.a', 'forced.a', 'xlinker.a', 'loaded.a', 'symbols.txt', 'version.map',
		'exact.a']
	for name in names {
		os.write_file(os.join_path(root, name), '!<arch>\n${name}')!
	}
	path := fn [root] (name string) string {
		return os.join_path(root, name)
	}
	inputs := v3_program_link_inputs(['-o', 'out', 'src.c', '-Wl,${path('direct.a')}',
		'-Wl,--whole-archive,${path('whole.a')},--no-whole-archive',
		'-Wl,-force_load,${path('forced.a')}', '-Xlinker', path('xlinker.a'), '-force_load',
		path('loaded.a'), '-exported_symbols_list', path('symbols.txt'),
		'-Wl,--version-script=${path('version.map')}', '-L${root}', '-l:exact.a', '-Wl,-rpath,${root}',
		'-Wl,-dead_strip'], '', []string{}, '')
	assert inputs.unknown == ''
	assert inputs.files == names.map(path(it)).sorted()
	assert inputs.missing == []
}

fn test_program_link_inputs_are_unknown_for_what_cannot_be_followed() {
	root := link_inputs_fixture('program_link_unknown')
	defer {
		os.rmdir_all(root) or {}
	}
	thin := os.join_path(root, 'libthin.a')
	os.write_file(thin, '!<thin>\n//                                              10        `\nmember.o/\n')!
	assert v3_program_link_inputs(['-o', 'out', 'src.c', thin], '', []string{}, '').unknown.contains('thin archive')
	assert v3_program_link_inputs(['-o', 'out', 'src.c', '-L${root}', '-lthin'], '', []string{}, '').unknown.contains('thin archive')
	assert v3_program_link_inputs(['-o', 'out', 'src.c', '-Wl,${thin}'], '', []string{}, '').unknown.contains('thin archive')
	response := os.join_path(root, 'link.rsp')
	os.write_file(response, thin)!
	assert v3_program_link_inputs(['-o', 'out', 'src.c', '@${response}'], '', []string{}, '').unknown.len > 0
	assert v3_program_link_inputs(['-o', 'out', 'src.c', '-filelist', response], '', []string{}, '').unknown.len > 0
	assert v3_program_link_inputs(['-o', 'out', 'src.c', '-Wl,-filelist,${response}'], '',
		[]string{}, '').unknown.len > 0
	// A script that does more than name its inputs.
	script := os.join_path(root, 'libscript.so')
	os.write_file(script, 'SEARCH_DIR(/somewhere)\nGROUP ( libother.so.1 )\n')!
	assert v3_program_link_inputs(['-o', 'out', 'src.c', script], '', []string{}, '').unknown.contains('linker script')
}

fn test_program_link_inputs_follow_a_linker_script() {
	root := link_inputs_fixture('program_link_script')
	defer {
		os.rmdir_all(root) or {}
	}
	real_library := os.join_path(root, 'libreal.so.6')
	extra := os.join_path(root, 'libextra.a')
	needed := os.join_path(root, 'libneeded.so.1')
	os.write_file(real_library, '\x7fELF\x00')!
	os.write_file(extra, '!<arch>\nextra')!
	os.write_file(needed, '\x7fELF\x00')!
	script := os.join_path(root, 'libscripted.so')
	os.write_file(script, '/* GNU ld script */\nOUTPUT_FORMAT(elf64-x86-64)\nGROUP ( ${real_library} -lextra AS_NEEDED ( libneeded.so.1 ) )\n')!
	inputs := v3_program_link_inputs(['-o', 'out', 'src.c', '-L${root}', '-lscripted'], '',
		[]string{}, '')
	assert inputs.unknown == ''
	assert inputs.files == [script, real_library, extra, needed].sorted()
	// A thin archive behind a script is found too.
	os.write_file(extra, '!<thin>\n')!
	assert v3_program_link_inputs(['-o', 'out', 'src.c', '-L${root}', '-lscripted'], '', []string{}, '').unknown.contains('thin archive')
}

fn test_program_link_inputs_read_what_goes_to_the_linker_as_one_command() {
	root := link_inputs_fixture('program_link_forwarded')
	defer {
		os.rmdir_all(root) or {}
	}
	libs := os.join_path(root, 'libs')
	os.mkdir_all(libs)!
	archive := os.join_path(libs, 'libanswer.a')
	os.write_file(archive, '!<arch>\nanswer')!
	// An option and its value can each be handed over on its own.
	for args in [
		['-Wl,-L,${libs},-lanswer'],
		['-Wl,-L', '-Wl,${libs}', '-Wl,-l,answer'],
		['-Xlinker', '-L', '-Xlinker', libs, '-Xlinker', '-lanswer'],
		['-Wl,--library-path=${libs},--library=answer'],
		['-Wl,--library-path,${libs},--library,answer'],
		['-Wl,-L${libs}', '-Wl,-weak-lanswer'],
	] {
		mut command := ['-o', 'out', 'src.c']
		command << args
		inputs := v3_program_link_inputs(command, '', []string{}, '')
		assert inputs.unknown == '', args.str()
		assert inputs.files == [archive], args.str()
		assert os.join_path(libs, 'libanswer.dylib') in inputs.missing, args.str()
	}
	// The value of an option that names no input is none, though it is a file.
	named := v3_program_link_inputs(['-o', 'out', 'src.c', '-Wl,-soname,${archive}',
		'-Wl,-rpath,${libs}', '-Wl,-install_name,${archive}', '-Wl,-z,now', '-Wl,-znow',
		'-Wl,--build-id=sha1', '-Wl,-stack_size,0x4000000', '-Wl,-platform_version,macos,11.0,14.0',
		'-Wl,--as-needed', '-Wl,-dead_strip', '-Wl,-undefined,dynamic_lookup', '-Wl,--exclude-libs,ALL',
		'-Wl,-export_dynamic', '-Wl,-O1', '-Wl,-melf_x86_64'], '', []string{}, '')
	assert named.unknown == ''
	assert named.files == []
	// An option that is not known may read anything, and so may one that moves
	// the place where libraries are looked for.
	for args in [
		['-Wl,--no-such-option'],
		['-Wl,--sysroot=${root}'],
		['-Wl,-syslibroot,${root}'],
		['-Xlinker', '--made-up=1'],
		['-Wl,-exotic,${archive}'],
		['-Wl,@${archive}'],
	] {
		mut command := ['-o', 'out', 'src.c']
		command << args
		unknown := v3_program_link_inputs(command, '', []string{}, '')
		assert unknown.reason().len > 0, args.str()
		// What an option of the linker reads is known when the linker tells it; the
		// arguments of a file are those of the compiler as well.
		assert (unknown.unknown_option.len > 0) == !args[0].contains('@'), args.str()
	}
	// The options of the compiler itself are many, and none of them is the linker's.
	assert v3_program_link_inputs(['-O2', '-fwrapv', '--no-such-option', '-o', 'out', 'src.c'],
		'', []string{}, '').unknown == ''
	// A relative path is one of the directory of the build, unless it leaves it.
	assert v3_program_link_inputs(['-o', 'out', 'src.c', 'module.o', '-Lcache', '-Wl,cache/a.o'],
		'', []string{}, '').unknown == ''
	assert v3_program_link_inputs(['-o', 'out', 'src.c', '-L../libs', '-lanswer'], '', []string{}, '').unknown.len > 0
	assert v3_program_link_inputs(['-o', 'out', 'src.c', '../libs/libanswer.a'], '', []string{}, '').unknown.len > 0
	assert v3_program_link_inputs(['-o', 'out', 'src.c', '-Wl,../libs/libanswer.a'], '',
		[]string{}, '').unknown.len > 0
}

fn test_program_link_inputs_give_an_option_the_value_that_follows_it_in_the_command() {
	root := link_inputs_fixture('program_link_values')
	defer {
		os.rmdir_all(root) or {}
	}
	libs := os.join_path(root, 'libs')
	os.mkdir_all(libs)!
	archive := os.join_path(libs, 'libanswer.a')
	os.write_file(archive, '!<arch>\nanswer')!
	symbols := os.join_path(root, 'symbols.map')
	os.write_file(symbols, '{ global: answer; };\n')!
	// The value of an option of the linker can be an argument of the compiler
	// driver, which hands it over in its place; an option whose value is attached
	// to it takes none.
	for args in [
		['-Wl,-rpath', '/opt/lib', '-Wl,-L,${libs},-lanswer'],
		['-Wl,-rpath', libs, '-Wl,-L,${libs},-lanswer'],
		['-Wl,--sort-common', '-Wl,-L${libs}', '-lanswer'],
		['-Wl,--icf=all', '-Wl,--sort-common=descending', '-L', libs, '-lanswer'],
		['-Wl,-soname', 'libout.so', '-L${libs}', '-Wl,-lanswer'],
		['-Wl,-R${libs}', '-Wl,-R', '-Wl,${libs}', '-L${libs}', '-lanswer'],
	] {
		mut command := ['-o', 'out', 'src.c']
		command << args
		inputs := v3_program_link_inputs(command, '', []string{}, '')
		assert inputs.unknown == '', args.str()
		assert inputs.files == [archive], args.str()
	}
	split := v3_program_link_inputs(['-o', 'out', 'src.c', '-Wl,--version-script', symbols,
		'-L${libs}', '-lanswer'], '', []string{}, '')
	assert split.unknown == ''
	assert split.files == [archive, symbols].sorted()
	// A macro that the compiler is given a value for names no file, and neither
	// does a value that is no absolute path.
	defined := v3_program_link_inputs(['-o', 'out', 'src.c', '-DASSETS=../assets', '-DROOT=${archive}',
		'-std=gnu11', '--sysroot=${root}', '-fprofile-use=${symbols}', '-march=native'], '',
		[]string{}, '')
	assert defined.unknown == ''
	assert defined.files == [symbols]
}

fn test_program_link_inputs_find_what_a_relative_path_names_outside_the_build() {
	root := link_inputs_fixture('program_link_relative')
	defer {
		os.rmdir_all(root) or {}
	}
	// The command runs in a directory that the build made beside the output.
	build_dir := os.join_path(root, 'out.v3cc')
	libs := os.join_path(root, 'libs')
	os.mkdir_all(build_dir)!
	os.mkdir_all(libs)!
	archive := os.join_path(libs, 'libanswer.a')
	profile := os.join_path(root, 'default.profdata')
	os.write_file(archive, '!<arch>\nanswer')!
	os.write_file(profile, 'profile')!
	inputs := v3_program_link_inputs(['-o', 'out', 'src.c', 'cache/module.o', '-L../libs', '-lanswer',
		'-fprofile-use=../default.profdata', '-fdebug-prefix-map=../src=.', '-iframework',
		'../Frameworks', '-Wl,-rpath,../libs', '-I../include'], '', []string{}, build_dir)
	assert inputs.unknown == ''
	assert inputs.files == [profile, archive].sorted()
	// A file that is not there now may be there for the next build.
	assert os.join_path(libs, 'libanswer.dylib') in inputs.missing
	direct := v3_program_link_inputs(['-o', 'out', 'src.c', '../libs/libanswer.a',
		'-Wl,../libs/libanswer.a'],
		'', []string{}, build_dir)
	assert direct.unknown == ''
	assert direct.files == [archive]
	// Where the directory of the build is not known, such a path names nothing
	// that can be followed.
	assert v3_program_link_inputs(['-o', 'out', 'src.c', '-fprofile-use=../default.profdata'],
		'', []string{}, '').unknown.len > 0
}

fn test_an_argument_of_the_driver_is_told_from_one_that_it_hands_to_the_linker() {
	assert v3_compiler_option_values('-iframework') == 1
	assert v3_compiler_option_values('-sectcreate') == 3
	assert v3_compiler_option_values('-L') == 1
	assert v3_compiler_option_values('-O2') == 0
	kind, value := v3_attached_linker_option('-L/dir')
	assert kind == .library_dir && value == '/dir'
	for arg, expected in {
		'-lanswer':      V3AttachedOption.library
		'-weak-lanswer': V3AttachedOption.library
		'-F/frameworks': V3AttachedOption.framework_dir
		'-R/run':        V3AttachedOption.runtime_path
		'-T/script.ld':  V3AttachedOption.script
		'-Ttext':        V3AttachedOption.no_option
		'-znow':         V3AttachedOption.value
		'--library=x':   V3AttachedOption.no_option
		'-exported':     V3AttachedOption.no_option
		'/abs/libfoo.a': V3AttachedOption.no_option
	} {
		found, _ := v3_attached_linker_option(arg)
		assert found == expected, arg
	}
}

fn test_program_link_inputs_follow_a_linker_script_of_any_name() {
	root := link_inputs_fixture('program_link_script_name')
	defer {
		os.rmdir_all(root) or {}
	}
	archive := os.join_path(root, 'libanswer.a')
	os.write_file(archive, '!<arch>\nanswer')!
	script := os.join_path(root, 'answer.ld')
	os.write_file(script, 'INPUT ( ${archive} )\n')!
	for args in [
		[script],
		['-Wl,${script}'],
		['-Xlinker', script],
		['-T', script],
		['-T${script}'],
		['-Wl,-T,${script}'],
		['-Wl,-T${script}'],
		['-Wl,--script=${script}'],
	] {
		mut command := ['-o', 'out', 'src.c']
		command << args
		inputs := v3_program_link_inputs(command, '', []string{}, '')
		assert inputs.unknown == '', args.str()
		assert inputs.files == [archive, script].sorted(), args.str()
	}
	// A script that lays the program out does more than name inputs.
	layout := os.join_path(root, 'layout.x')
	os.write_file(layout, 'SECTIONS { . = 0x10000; }\n')!
	assert v3_program_link_inputs(['-o', 'out', 'src.c', layout], '', []string{}, '').unknown.contains('linker script')
	assert v3_program_link_inputs(['-o', 'out', 'src.c', '-Wl,-T,${layout}'], '', []string{}, '').unknown.contains('linker script')
	// A list of symbols is read as it is, and a source is compiled.
	symbols := os.join_path(root, 'symbols.txt')
	source := os.join_path(root, 'extra.c')
	os.write_file(symbols, '_answer\n')!
	os.write_file(source, 'int extra(void) { return 1; }\n')!
	plain := v3_program_link_inputs(['-o', 'out', 'src.c', source, '-Wl,--version-script=${symbols}',
		'-exported_symbols_list', symbols, '-Wl,-exported_symbols_list,${symbols}'], '',
		[]string{}, '')
	assert plain.unknown == ''
	assert plain.files == [source, symbols].sorted()
	// A text stub of a library names what the library exports, not other files.
	stub := os.join_path(root, 'libstub.tbd')
	os.write_file(stub, '--- !tapi-tbd\ntbd-version: 4\n')!
	stubbed := v3_program_link_inputs(['-o', 'out', 'src.c', stub], '', []string{}, '')
	assert stubbed.unknown == '' && stubbed.files == [stub]
}

fn test_environment_of_a_link_is_part_of_what_identifies_its_executable() {
	saved := os.getenv_opt('LIBRARY_PATH')
	defer {
		if value := saved {
			os.setenv('LIBRARY_PATH', value, true)
		} else {
			os.unsetenv('LIBRARY_PATH')
		}
	}
	signature := fn () string {
		return v3_program_executable_link_signature(['-lanswer'], false, []string{})
	}
	os.setenv('LIBRARY_PATH', '/first', true)
	first := signature()
	assert first == signature()
	os.setenv('LIBRARY_PATH', '/second', true)
	assert signature() != first
	os.setenv('LIBRARY_PATH', '/first${os.path_delimiter}/second', true)
	ordered := signature()
	os.setenv('LIBRARY_PATH', '/second${os.path_delimiter}/first', true)
	assert signature() != ordered
	os.unsetenv('LIBRARY_PATH')
	assert signature() != first
	// What a compiler or a linker searches or writes into its output by.
	for name in ['LIBRARY_PATH', 'CPATH', 'C_INCLUDE_PATH', 'LD_RUN_PATH', 'SDKROOT',
		'MACOSX_DEPLOYMENT_TARGET'] {
		assert name in v3_link_environment_names
	}
}

fn test_link_search_args_are_those_that_move_the_libraries_of_a_compiler() {
	assert v3_link_search_args(['-O2', '-o', 'out', 'src.c', '--sysroot=/sdk', '-isysroot', '/sdk2',
		'-m32', '-B/tools', '-lfoo', '-static', '-target', 'x86_64-linux-gnu', '-Wl,-s', '-I/inc']) == [
		'--sysroot=/sdk',
		'-isysroot',
		'/sdk2',
		'-m32',
		'-B/tools',
		'-static',
		'-target',
		'x86_64-linux-gnu',
	]
}

fn test_linker_report_is_read_in_both_of_its_forms() {
	root := link_inputs_fixture('linker_report_forms')
	defer {
		os.rmdir_all(root) or {}
	}
	info := os.join_path(root, 'dependency_info')
	mut bytes := []u8{}
	for kind, name in {
		u8(0x00): '@(#)PROGRAM:ld PROJECT:ld-1267'
		u8(0x10): '/sdk/usr/lib/libSystem.tbd'
		u8(0x11): '/first/libanswer.a'
		u8(0x40): 'out'
	} {
		bytes << kind
		bytes << name.bytes()
		bytes << 0
	}
	bytes << u8(0x10)
	bytes << '/libs/libanswer.a'.bytes()
	bytes << 0
	bytes << u8(0x10)
	bytes << '/sdk/usr/lib/libSystem.tbd'.bytes()
	bytes << 0
	os.write_bytes(info, bytes)!
	found, not_found := v3_read_linker_report(.dependency_info, info) or {
		assert false, 'the report of Apple ld is not read'
		return
	}
	assert found == ['/sdk/usr/lib/libSystem.tbd', '/libs/libanswer.a']
	assert not_found == ['/first/libanswer.a']
	// A report that is cut off, or that is not there, is none.
	os.write_bytes(info, bytes[..bytes.len - 3])!
	assert v3_read_linker_report(.dependency_info, info) == none
	assert v3_read_linker_report(.dependency_info, info + '.absent') == none
	assert v3_read_linker_report(.no_report, info) == none
	rule := os.join_path(root, 'dependency_file')
	os.write_file(rule, 'out: /usr/lib/crt1.o /tmp/cc1.o \\\n /libs/libanswer.a /usr/lib/libc.so\n\n/usr/lib/crt1.o:\n\n/tmp/cc1.o:\n')!
	read, none_missing := v3_read_linker_report(.dependency_file, rule) or {
		assert false, 'the report of GNU ld is not read'
		return
	}
	assert read == ['/usr/lib/crt1.o', '/tmp/cc1.o', '/libs/libanswer.a', '/usr/lib/libc.so']
	assert none_missing == []
	assert v3_linker_report_args(.dependency_info, '/build') == [
		'-Wl,-dependency_info,/build/${v3_linker_report_file}',
	]
	assert v3_linker_report_args(.dependency_file, '/build') == [
		'-Wl,--dependency-file=/build/${v3_linker_report_file}',
	]
	assert v3_linker_report_args(.no_report, '/build') == []
	// The arguments that ask for the report name no input themselves.
	for report in [V3LinkerReport.dependency_info, .dependency_file] {
		mut command := ['-o', 'out', 'src.c']
		command << v3_linker_report_args(report, '/build')
		asked := v3_program_link_inputs(command, '', []string{}, '/build')
		assert asked.reason() == ''
		assert asked.files == []
	}
}

fn test_linker_report_adds_what_the_linker_found_by_itself() {
	root := link_inputs_fixture('linker_report_inputs')
	defer {
		os.rmdir_all(root) or {}
	}
	build_dir := os.join_path(root, 'build')
	os.mkdir_all(build_dir)!
	named := os.join_path(root, 'libnamed.a')
	implicit := os.join_path(root, 'libimplicit.tbd')
	made := os.join_path(build_dir, 'src.o')
	gone := os.join_path(root, 'temporary.o')
	absent := os.join_path(root, 'first', 'libnamed.a')
	for file in [named, implicit, made] {
		os.write_file(file, '!<arch>\nx')!
	}
	if modulecache.file_metadata_signature(named) == '' {
		// This file system cannot tell a later edit apart: nothing is kept for it.
		return
	}
	write_report := fn [build_dir] (found []string, not_found []string) {
		mut bytes := []u8{}
		for name in found {
			bytes << u8(0x10)
			bytes << name.bytes()
			bytes << 0
		}
		for name in not_found {
			bytes << u8(0x11)
			bytes << name.bytes()
			bytes << 0
		}
		os.write_bytes(os.join_path(build_dir, v3_linker_report_file), bytes) or { panic(err) }
	}
	write_report([named, implicit, made, gone, 'relative.o'], [absent])
	later := time.utc().unix() + 10
	new_inputs := fn [named] () V3ProgramLinkInputs {
		return V3ProgramLinkInputs{
			taken:          true
			files:          [named]
			identities:     ['identity from before the link']
			unknown_option: 'the linker option `-no_order_inits` is not one whose inputs are known'
		}
	}
	mut inputs := new_inputs()
	inputs.add_linker_report(.dependency_info, build_dir, later)
	assert inputs.unknown == ''
	// The linker told where it found nothing: the option that is not known here
	// read nothing that the report does not hold.
	assert inputs.unknown_option == ''
	assert inputs.reason() == ''
	// A file that the command names keeps what it was before the link; one that
	// the linker found by itself is the file that it is now; what the command made
	// or removed is no input.
	assert inputs.files == [named, implicit]
	assert inputs.identities == ['identity from before the link',
		modulecache.file_metadata_signature(implicit)]
	assert inputs.missing == [absent]
	// A rule of `make` tells no path where nothing was: what the option reads
	// besides is not known.
	os.write_file(os.join_path(build_dir, v3_linker_report_file), 'out: ${named} ${implicit}\n')!
	mut ruled := new_inputs()
	ruled.add_linker_report(.dependency_file, build_dir, later)
	assert ruled.unknown == ''
	assert ruled.files == [named, implicit]
	assert ruled.unknown_option.len > 0
	// A file that the linker found and that is as new as the link may not be the
	// one that it read.
	write_report([named, implicit], []string{})
	mut early := new_inputs()
	early.add_linker_report(.dependency_info, build_dir, time.utc().unix() - 10)
	assert early.unknown.contains('libimplicit.tbd')
	// A linker that was asked and wrote nothing leaves no executable behind.
	os.rm(os.join_path(build_dir, v3_linker_report_file))!
	mut silent := new_inputs()
	silent.add_linker_report(.dependency_info, build_dir, later)
	assert silent.unknown.contains('did not tell')
	mut unasked := new_inputs()
	unasked.add_linker_report(.no_report, build_dir, later)
	assert unasked.unknown == '' && unasked.unknown_option.len > 0
}

fn test_linker_is_asked_once_which_report_it_gives() {
	$if windows {
		return
	}
	compiler := os.find_abs_path_of_executable('cc') or { return }
	root := link_inputs_fixture('linker_report_probe')
	defer {
		os.rmdir_all(root) or {}
	}
	build_dir := os.join_path(root, 'build')
	os.mkdir_all(build_dir)!
	manager := modulecache.new_manager(os.join_path(root, 'cache'), 'salt', true, '', '')
	report := v3_linker_report(&manager, compiler, []string{}, os.user_os(), build_dir)
	$if macos {
		assert report == .dependency_info
	}
	records := os.ls(manager.dir)!.filter(it.starts_with('linker_report_'))
	// Nothing of the question is left in the directory of the build.
	assert os.ls(build_dir)! == []
	if report != .no_report {
		assert records.len == 1
		assert os.read_file(os.join_path(manager.dir, records[0]))! == 'yes\n'
		// The answer is read back: a compiler that is not there is not run.
		os.rmdir_all(build_dir)!
		os.mkdir_all(build_dir)!
		assert v3_linker_report(&manager, compiler, []string{}, os.user_os(), build_dir) == report
	}
	// A linker that does not know the option says so, and is not asked again; a
	// compiler that fails for another reason is.
	refusing := os.join_path(root, 'refusing-cc')
	os.write_file(refusing, '#!/bin/sh\necho "ld: unknown options: -dependency_info --dependency-file" >&2\nexit 1\n')!
	os.chmod(refusing, 0o755)!
	assert v3_linker_report(&manager, refusing, []string{}, os.user_os(), build_dir) == .no_report
	failing := os.join_path(root, 'failing-cc')
	os.write_file(failing, '#!/bin/sh\necho "cc: no space left on device" >&2\nexit 1\n')!
	os.chmod(failing, 0o755)!
	assert v3_linker_report(&manager, failing, []string{}, os.user_os(), build_dir) == .no_report
	kept := os.ls(manager.dir)!.filter(it.starts_with('linker_report_')).map(os.read_file(os.join_path(manager.dir,
		it)) or { '' })
	assert kept.filter(it == 'no\n').len == 1
	assert kept.len == records.len + 1
}

fn test_library_search_dirs_are_read_from_what_a_compiler_prints() {
	gcc := 'install: /usr/lib/gcc/x86_64-linux-gnu/13/\nprograms: =/usr/bin\nlibraries: =/usr/lib/gcc/x86_64-linux-gnu/13/:/usr/lib/x86_64-linux-gnu/:/lib/\n'
	assert v3_parse_library_search_dirs(gcc) == ['/usr/lib/gcc/x86_64-linux-gnu/13/',
		'/usr/lib/x86_64-linux-gnu/', '/lib/']
	tcc := 'install: /tcc/lib\ninclude:\n  /tcc/lib/include\n  /usr/include\nlibraries:\n  thirdparty/tcc/lib\n  /usr/local/lib\n  /usr/lib\nlibtcc1:\n  /tcc/lib/libtcc1.a\n'
	assert v3_parse_library_search_dirs(tcc) == ['thirdparty/tcc/lib', '/usr/local/lib', '/usr/lib']
	assert v3_parse_library_search_dirs('') == []
}

fn test_files_keep_identities_only_while_they_are_the_files_that_were_read() {
	root := os.join_path(os.vtmp_dir(), 'v3_driver_file_identities_${os.getpid()}')
	os.rmdir_all(root) or {}
	os.mkdir_all(root)!
	defer {
		os.rmdir_all(root) or {}
	}
	source := os.join_path(root, 'main.v')
	os.write_file(source, 'fn main() {}\n')!
	identities := [modulecache.file_metadata_signature(source)]
	if identities[0] == '' {
		// This file system cannot tell a later edit apart: nothing is kept for it.
		assert !v3_files_keep_identities([source], identities)
		return
	}
	assert v3_files_keep_identities([source], identities)
	assert !v3_files_keep_identities([source, source], identities)
	assert !v3_files_keep_identities([source], [''])
	os.write_file(source, 'fn main() { println(1) }\n')!
	assert !v3_files_keep_identities([source], identities)
}

fn test_program_executable_link_signature_tells_builds_apart() {
	base := v3_program_executable_link_signature(['-lm'], false, ['strict=false'])
	assert base == v3_program_executable_link_signature(['-lm'], false, ['strict=false'])
	assert base != v3_program_executable_link_signature(['-lm', '-lz'], false, ['strict=false'])
	assert base != v3_program_executable_link_signature(['-lm'], true, ['strict=false'])
	assert base != v3_program_executable_link_signature(['-lm'], false, ['strict=true'])
}
