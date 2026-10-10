module driver

import os
import time
import v.modulecache

fn test_compiled_sources_are_the_operands_that_a_compiler_knows_as_sources() {
	assert v3_compiled_sources(['-O2', '-o', 'out', 'src.c', '/cache/module.o', '-I', '/inc/extra.c',
		'-lm', '-x', 'objective-c', 'main.m', '-x', 'none', '-MF', 'deps.d', '-include', '/inc/force.h',
		'/lib/libfoo.a']) == ['src.c', 'main.m']
	assert v3_compiled_sources(['-o', 'out', '/cache/main.o', '/cache/os.o', '-lm']) == []
}

fn test_dependency_file_names_what_a_compiler_read() {
	text := 'out: src.c /usr/include/stdio.h \\\n /usr/include/with\\ space.h \\\n  /usr/include/hash\\#mark.h /usr/include/dollar$$.h\n\n/usr/include/stdio.h:\n'
	assert v3_parse_dependency_file(text) == ['src.c', '/usr/include/stdio.h',
		'/usr/include/with space.h', '/usr/include/hash#mark.h', '/usr/include/dollar$.h']
	assert v3_parse_dependency_file('') == []
	assert v3_parse_dependency_file('out.o: \\\r\n a.c b.h\r\n') == ['a.c', 'b.h']
}

fn test_include_search_is_read_from_what_a_compiler_prints() {
	gcc := 'ignoring nonexistent directory "/usr/local/include/x86_64-linux-gnu"
ignoring duplicate directory "/usr/include"
#include "..." search starts here:
 /quoted
#include <...> search starts here:
 /first
 /usr/lib/gcc/x86_64-linux-gnu/13/include
 /usr/local/include
 /usr/include
End of search list.
# 0 "/dev/null"
'
	search := v3_parse_include_search(gcc) or {
		assert false, 'the search list of GCC is not read'
		return
	}
	assert search.dirs == ['/quoted', '/first', '/usr/lib/gcc/x86_64-linux-gnu/13/include',
		'/usr/local/include', '/usr/include']
	assert search.absent == ['/usr/local/include/x86_64-linux-gnu']
	assert search.frameworks == []
	clang := '#include "..." search starts here:
#include <...> search starts here:
 /usr/local/include
 /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include
 /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks (framework directory)
End of search list.
'
	frameworks := v3_parse_include_search(clang) or {
		assert false, 'the search list of Clang is not read'
		return
	}
	assert frameworks.dirs == ['/usr/local/include',
		'/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include',
		'/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks']
	assert frameworks.frameworks == [
		'/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks',
	]
	// An answer without its end is none, and neither is one in another language.
	assert v3_parse_include_search('#include <...> search starts here:\n /usr/include\n') == none
	assert v3_parse_include_search('#include <...> Suche beginnt hier:\n /usr/include\nEnde der Suchliste.\n') == none
	assert v3_include_search_args(['-O2', '-o', 'out', 'src.c', '-I/a', '-I', '/b', '-isystem',
		'/c', '-lm', '-std=gnu11', '-m64', '-nostdinc', '-Wl,-s', '-D', 'X=1', '-MF', '-Iignored',
		'-iframework', '/f']) == ['-I/a', '-I', '/b', '-isystem', '/c', '-std=gnu11', '-m64',
		'-nostdinc', '-iframework', '/f']
}

fn test_quoted_include_names_are_those_that_the_directory_of_a_file_is_searched_for() {
	source := '#include <stdio.h>
#include "local.h"
  #  include "sub/other.h" // trailing
#include_next "next.h"
#import "objc.h"
// #include "in_a_comment.h"
const char *text = "#include \"in_a_string.h\"";
#if __has_include("optional.h") && __has_include_next( "later.h" ) && __has_include(<angle.h>)
#endif
#include MACRO_NAME
#include "local.h"
'
	assert v3_quoted_include_names(source) == ['local.h', 'sub/other.h', 'next.h', 'objc.h',
		'optional.h', 'later.h']
}

fn test_include_names_of_a_framework_are_those_of_its_headers() {
	assert v3_include_name_below('sys/types.h', false) or { '' } == 'sys/types.h'
	assert v3_include_name_below('Cocoa.framework/Headers/Cocoa.h', true) or { '' } == 'Cocoa/Cocoa.h'
	assert v3_include_name_below('A.framework/Versions/C/Headers/sub/b.h', true) or { '' } == 'A/sub/b.h'
	assert v3_include_name_below('A.framework/PrivateHeaders/p.h', true) or { '' } == 'A/p.h'
	assert v3_include_name_below('A.framework/Resources/x.h', true) == none
	assert v3_include_name_below('plain/x.h', true) == none
	assert v3_include_path_below('Cocoa/Cocoa.h', true) or { '' } == 'Cocoa.framework/Headers/Cocoa.h'
	assert v3_include_path_below('A/sub/b.h', false) or { '' } == 'A/sub/b.h'
	assert v3_include_path_below('stdio.h', true) == none
}

fn test_header_inputs_are_the_files_read_and_the_places_where_another_would_be_read() {
	root := os.join_path(os.vtmp_dir(), 'v3_driver_header_inputs_${os.getpid()}')
	os.rmdir_all(root) or {}
	defer {
		os.rmdir_all(root) or {}
	}
	first := os.join_path(root, 'first')
	second := os.join_path(root, 'second')
	third := os.join_path(root, 'third')
	frameworks := os.join_path(root, 'Frameworks')
	absent := os.join_path(root, 'absent')
	for dir in [first, os.join_path(second, 'sys'), third,
		os.join_path(frameworks, 'Kit.framework', 'Headers')] {
		os.mkdir_all(dir)!
	}
	header := os.join_path(second, 'sys', 'wait.h')
	inner := os.join_path(third, 'inner.h')
	kit := os.join_path(frameworks, 'Kit.framework', 'Headers', 'Kit.h')
	os.write_file(header, '#if __has_include(<optional.h>)\n#endif\n#include "inner.h"\n#include "types.h"\nint wait(void);\n')!
	os.write_file(os.join_path(second, 'sys', 'types.h'), 'typedef int pid;\n')!
	os.write_file(inner, 'int inner;\n')!
	os.write_file(kit, 'int kit;\n')!
	if modulecache.file_metadata_signature(header) == '' {
		// This file system cannot tell a later edit apart: nothing is kept for it.
		return
	}
	search := V3IncludeSearch{
		dirs:       [first, second, frameworks, third]
		frameworks: [frameworks]
		absent:     [absent]
	}
	later := time.utc().unix() + 10
	inputs := v3_header_inputs([header, inner, kit], '#include <sys/wait.h>\n', search, later)
	assert inputs.unknown == '' && !inputs.mentions_time
	// What a file includes in quotation marks and what is in its own directory is
	// read whether the compiler told it or not.
	assert inputs.files == [kit, header, os.join_path(second, 'sys', 'types.h'), inner].sorted()
	assert inputs.identities == inputs.files.map(modulecache.file_metadata_signature(it))
	for candidate in [
		// `sys/wait.h` would be found in the first directory if `sys` appeared there.
		os.join_path(first, 'sys'),
		// `inner.h` is looked for next to the file that includes it before anywhere.
		os.join_path(second, 'sys', 'inner.h'),
		// It was found in the third directory, after the first two and a framework.
		os.join_path(first, 'inner.h'),
		os.join_path(second, 'inner.h'),
		// `<Kit/Kit.h>` is a header of a framework, or a file of a directory.
		os.join_path(first, 'Kit'),
		os.join_path(second, 'Kit'),
		// `optional.h` could appear anywhere.
		os.join_path(first, 'optional.h'),
		os.join_path(third, 'optional.h'),
		absent,
	] {
		assert candidate in inputs.missing, candidate
	}
	// A directory that is searched after the one of a header cannot hide it.
	assert os.join_path(third, 'sys') !in inputs.missing
	assert os.join_path(frameworks, 'inner.h') !in inputs.missing

	// The compiler and its own answer can spell a directory in two ways.
	spelled := V3IncludeSearch{
		dirs: [first, os.join_path(root, 'first', '..', 'second')]
	}
	respelled := v3_header_inputs([header], '', spelled, later)
	assert os.join_path(first, 'sys') in respelled.missing

	// A header of a time macro makes what is compiled a thing of the moment.
	os.write_file(inner, 'static const char *built = __DATE__ " " __TIME__;\n')!
	assert v3_header_inputs([header, inner], '', search, later).mentions_time
	assert v3_header_inputs([header], 'const char *t = __TIMESTAMP__;\n', search, later).mentions_time
	os.write_file(inner, 'int inner;\n')!

	// A file that was written when the compiler had started may not be the one
	// that it read.
	assert v3_header_inputs([header, inner], '', search, time.utc().unix() - 10).unknown.len > 0

	// A header that is where an earlier directory would have it, and that was not
	// there when the compiler started, came while the compiler ran: what the
	// compiler read is not what it would read now. One that was there all along is
	// one that the compiler passed over, as `#include_next` makes it.
	os.write_file(os.join_path(first, 'inner.h'), 'int shadow;\n')!
	passed_over := v3_header_inputs([header, inner], '', search, later)
	assert passed_over.unknown == ''
	assert os.join_path(first, 'inner.h') !in passed_over.missing
	appeared := v3_header_inputs([header, inner], '', V3IncludeSearch{
		dirs: [first, second, third]
	}, time.utc().unix() - 10)
	assert appeared.unknown.contains('appeared while the compiler ran')
		|| appeared.unknown.contains('cannot be told apart'), appeared.unknown
	// A directory that the compiler was told of and that is there now.
	os.mkdir_all(absent)!
	assert v3_header_inputs([header], '', search, later).unknown.contains('appeared')
}

fn test_headers_that_a_compiler_read_are_inputs_of_its_executable() {
	$if windows {
		return
	}
	compiler := os.find_abs_path_of_executable('cc') or { return }
	root := os.join_path(os.vtmp_dir(), 'v3_driver_compile_inputs_${os.getpid()}')
	os.rmdir_all(root) or {}
	defer {
		os.rmdir_all(root) or {}
	}
	build_dir := os.join_path(root, 'build')
	first := os.join_path(root, 'first')
	second := os.join_path(root, 'second')
	absent := os.join_path(root, 'absent')
	for dir in [build_dir, first, os.join_path(second, 'sub')] {
		os.mkdir_all(dir)!
	}
	header := os.join_path(second, 'sub', 'answer.h')
	os.write_file(header, '#if __has_include(<optional_answer.h>)\n#endif\nstatic inline int answer(void) { return 41; }\n')!
	unit := '#include <sub/answer.h>\nint main(void) { return answer() - 41; }\n'
	os.write_file(os.join_path(build_dir, 'src.c'), unit)!
	manager := modulecache.new_manager(os.join_path(root, 'cache'), 'salt', true, '', '')
	args := ['-I${first}', '-I', second, '-I${absent}', '-o', 'out', 'src.c', '-MD', '-MF',
		v3_program_dependency_file]
	compiled := os.exec([compiler, '-I${first}', '-I', second, '-I${absent}', '-o',
		os.join_path(build_dir, 'out'), os.join_path(build_dir, 'src.c'), '-MD', '-MF',
		os.join_path(build_dir, v3_program_dependency_file)])
	assert compiled.exit_code == 0, compiled.output
	if modulecache.file_metadata_signature(header) == '' {
		// This file system cannot tell a later edit apart: nothing is kept for it.
		return
	}
	// The compiler is asked once where it searches, in a language that is read here.
	search := v3_include_search(&manager, compiler, args, build_dir) or {
		assert false, 'the compiler does not tell where it searches'
		return
	}
	assert first in search.dirs && second in search.dirs && absent in search.absent
	assert search.dirs.index(first) < search.dirs.index(second)
	assert os.ls(manager.dir)!.filter(it.starts_with('include_search_')).len == 1
	again := v3_include_search(&manager, compiler, args, build_dir) or {
		assert false, 'the answer of the compiler is not kept'
		return
	}
	assert again.dirs == search.dirs && again.absent == search.absent
	later := time.utc().unix() + 10
	mut inputs := V3ProgramLinkInputs{
		taken: true
	}
	inputs.add_compiled_headers(args, build_dir, unit, search, later)
	assert inputs.unknown == ''
	assert header in inputs.files
	assert inputs.identities[inputs.files.index(header)] == modulecache.file_metadata_signature(header)
	// The source of the unit is in the directory of the build: it is no input.
	assert inputs.files.all(!it.starts_with(build_dir + '/'))
	// The header would be found in the first directory if it appeared there, and so
	// would the one that it asks about; the directory that is not there may appear.
	for candidate in [os.join_path(first, 'sub'), os.join_path(first, 'optional_answer.h'),
		os.join_path(second, 'optional_answer.h'), absent] {
		assert candidate in inputs.missing, candidate
	}
	// A header that was written when the compiler had started may not be the one
	// that it read.
	mut early := V3ProgramLinkInputs{
		taken: true
	}
	early.add_compiled_headers(args, build_dir, unit, search, time.utc().unix() - 10)
	assert early.unknown.len > 0
	// More than one source: the compiler writes down the headers of the last one.
	mut several := V3ProgramLinkInputs{
		taken: true
	}
	several.add_compiled_headers(['-o', 'out', 'src.c', 'other.c'], build_dir, unit, search,
		later)
	assert several.unknown.contains('more than one source')
	// A command that only links read no header.
	mut linked := V3ProgramLinkInputs{
		taken: true
	}
	linked.add_compiled_headers(['-o', 'out', '/cache/main.o'], build_dir, '', search,
		later)
	assert linked.unknown == '' && linked.files == []
}

fn test_an_executable_is_not_kept_of_a_compilation_that_cannot_be_repeated() {
	mut timed := V3ProgramLinkInputs{
		taken: true
	}
	timed.add_header_inputs(&V3HeaderInputs{
		files:         ['/usr/include/built.h']
		identities:    ['identity']
		mentions_time: true
	})
	assert timed.unknown.contains('time of its compilation') && timed.files == []
	mut unknown := V3ProgramLinkInputs{
		taken: true
	}
	unknown.add_header_inputs(&V3HeaderInputs{
		unknown: 'a header appeared'
	})
	assert unknown.unknown == 'a header appeared'
	mut known := V3ProgramLinkInputs{
		taken:      true
		files:      ['/lib/libm.a']
		identities: ['m']
	}
	known.add_header_inputs(&V3HeaderInputs{
		files:      ['/usr/include/stdio.h', '/lib/libm.a']
		identities: ['identity of stdio', 'other']
		missing:    ['/first/stdio.h']
	})
	assert known.unknown == ''
	assert known.files == ['/lib/libm.a', '/usr/include/stdio.h']
	assert known.identities == ['m', 'identity of stdio']
	assert known.missing == ['/first/stdio.h']
}
