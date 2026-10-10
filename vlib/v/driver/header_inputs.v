module driver

import os
import v.modulecache

// What a C compiler reads besides the unit that it compiles decides what it makes
// of the unit: the preprocessed headers that TinyCC is given (tcc_prelude.v) and
// the executable that is kept of a program (program_compile_inputs.v) both stand
// for a compilation, and are good for as long as that would read the same. This
// file works out what a compilation depends on from the files that it read.

// V3IncludeSearch is where a C compiler looks for an included file: `dirs` in the
// order of the search, `frameworks` those of them that hold frameworks, where
// `<A/B.h>` is `A.framework/Headers/B.h`, and `absent` the directories that it was
// told to search and that are not there.
struct V3IncludeSearch {
mut:
	dirs       []string
	frameworks []string
	absent     []string
}

// V3HeaderInputs is what a compilation depends on besides its unit and its
// command: the `files` that the compiler read, each with the metadata in
// `identities` that it had when it was read, and the `missing` paths where a file
// that is not there would be read instead of, or in addition to, one of them.
// `mentions_time` says that the unit or a header spells `__DATE__`, `__TIME__` or
// `__TIMESTAMP__`, so that the compilation may give another result at another
// time. `unknown` says why the inputs cannot all be told, or is '' when they can.
struct V3HeaderInputs {
mut:
	files         []string
	identities    []string
	missing       []string
	mentions_time bool
	unknown       string
}

// v3_c_mentions_compile_time reports whether `text` spells a macro whose value is
// that of the moment of the compilation.
fn v3_c_mentions_compile_time(text string) bool {
	return text.contains('__DATE__') || text.contains('__TIME__') || text.contains('__TIMESTAMP__')
}

// v3_quoted_include_names returns the names that `source` includes, or asks
// `__has_include` about, in quotation marks: the compiler looks for those in the
// directory of the file that names them before it looks anywhere else.
fn v3_quoted_include_names(source string) []string {
	mut names := []string{}
	mut pos := 0
	for pos < source.len {
		mut line_end := source.index_after_('\n', pos)
		if line_end < 0 {
			line_end = source.len
		}
		line := source[pos..line_end].trim_left(' \t')
		pos = line_end + 1
		if line.len < 2 || line[0] != `#` {
			continue
		}
		directive := line[1..].trim_left(' \t')
		mut rest := ''
		for word in ['include_next', 'include', 'import'] {
			if directive.starts_with(word) {
				rest = directive[word.len..].trim_left(' \t')
				break
			}
		}
		if rest.len > 2 && rest[0] == `"` {
			close := rest.index_after_('"', 1)
			if close > 1 && rest[1..close] !in names {
				names << rest[1..close]
			}
		}
	}
	mut found := 0
	for {
		found = source.index_after_('__has_include', found)
		if found < 0 {
			break
		}
		found += '__has_include'.len
		mut open := found
		if source[open..].starts_with('_next') {
			open += '_next'.len
		}
		for open < source.len && source[open] in [` `, `\t`, `(`] {
			open++
		}
		if open < source.len && source[open] == `"` {
			mut close := open + 1
			for close < source.len && source[close] != `"` && source[close] != `\n` {
				close++
			}
			if close < source.len && source[close] == `"` && close > open + 1
				&& source[open + 1..close] !in names {
				names << source[open + 1..close]
			}
		}
	}
	return names
}

// v3_path_is_older_than reports whether `relative` below `root`, which is there,
// was there before the time `before`, in seconds: each part of the way to it was
// made, changed and put in place earlier. A file that someone moves into a
// directory keeps the time of its contents and gets a new time of change.
fn v3_path_is_older_than(root string, relative string, before i64) bool {
	mut current := root
	for part in relative.split('/') {
		if part.len == 0 {
			continue
		}
		current = os.join_path_single(current, part)
		attributes := os.stat(current) or { return false }
		if attributes.mtime >= before || attributes.ctime >= before {
			return false
		}
	}
	return true
}

// v3_file_identity_from_before returns the metadata of `path` when that is the
// metadata of the file that a compiler read which started at the time `before`,
// in seconds: the metadata is taken after the compiler has read the file, so a
// file that was written or put in place at `before` or later may not be the one
// that was read.
fn v3_file_identity_from_before(path string, before i64) ?string {
	identity := modulecache.file_metadata_signature(path)
	if identity.len == 0 || path.contains_any('\t\n') {
		return none
	}
	attributes := os.stat(path) or { return none }
	if attributes.mtime >= before || attributes.ctime >= before {
		return none
	}
	return identity
}

// v3_include_name_below returns the name by which a file is included that is at
// `relative` below a directory of the search: the path itself, or for a directory
// of frameworks `A/B.h` for `A.framework/Headers/B.h`. It returns none for a file
// of a framework that no name of that form leads to.
fn v3_include_name_below(relative string, framework bool) ?string {
	if !framework {
		return relative
	}
	parts := relative.split('/')
	if parts.len < 3 || !parts[0].ends_with('.framework') {
		return none
	}
	mut headers := 1
	if parts.len > 4 && parts[1] == 'Versions' {
		headers = 3
	}
	if parts[headers] !in ['Headers', 'PrivateHeaders'] || headers + 1 >= parts.len {
		return none
	}
	mut name := [parts[0].all_before_last('.framework')]
	name << parts[headers + 1..]
	return name.join('/')
}

// v3_include_path_below is the opposite of v3_include_name_below: the path below a
// directory of the search where a file of the name `name` would be found.
fn v3_include_path_below(name string, framework bool) ?string {
	if !framework {
		return name
	}
	slash := name.index_u8(`/`)
	if slash <= 0 || slash + 1 >= name.len {
		return none
	}
	return '${name[..slash]}.framework/Headers/${name[slash + 1..]}'
}

// v3_header_inputs returns what a compilation of `unit` depends on, given the
// files that the compiler `read` for it, where it looks for an included file, and
// a time `before`, in seconds, from before it started.
//
// A file of the name of one that was read would be read instead of it if it were
// in a directory that is searched earlier: for each such directory, the path
// where it is not is an input. So is the directory of a file for each name that
// the file includes in quotation marks, which is searched first of all, and each
// directory of the search for a name that the unit or a file asks `__has_include`
// about. A file that is in such a place now, and was not there before the
// compiler started, may or may not be what the compiler read: the inputs are not
// known then. One that was there all along is one that the compiler passed over,
// as `#include_next` does.
fn v3_header_inputs(read []string, unit string, search V3IncludeSearch, before i64) V3HeaderInputs {
	mut inputs := V3HeaderInputs{
		mentions_time: v3_c_mentions_compile_time(unit)
	}
	// The compiler and its own answer can spell one directory in two ways.
	real_dirs := search.dirs.map(os.real_path(it))
	framework_dirs := search.dirs.map(it in search.frameworks)
	mut real_dir_of := map[string]string{}
	mut files := map[string]bool{}
	for path in read {
		files[path] = true
	}
	mut missing := map[string]bool{}
	mut asked := v3_has_include_names(unit)
	for path in read {
		text := os.read_file(path) or { '' }
		if !inputs.mentions_time && v3_c_mentions_compile_time(text) {
			inputs.mentions_time = true
		}
		if text.contains('__has_include') {
			for name in v3_has_include_names(text) {
				if name !in asked {
					asked << name
				}
			}
		}
		own_dir := os.dir(path)
		for name in v3_quoted_include_names(text) {
			if os.is_abs_path(name) {
				continue
			}
			absent := v3_first_missing_path(own_dir, name)
			candidate := os.norm_path(os.join_path(own_dir, name))
			if absent.len > 0 {
				missing[absent] = true
			} else if os.is_file(candidate) {
				// It is read, or an inactive part of the file names it.
				files[candidate] = true
			}
		}
		real_dir := real_dir_of[own_dir] or {
			resolved := os.real_path(own_dir)
			real_dir_of[own_dir] = resolved
			resolved
		}
		real := os.join_path_single(real_dir, os.file_name(path))
		for position, dir in real_dirs {
			if !real.starts_with(dir + '/') {
				continue
			}
			name := v3_include_name_below(real[dir.len + 1..], framework_dirs[position]) or {
				continue
			}
			for earlier in 0 .. position {
				if real_dirs[earlier] == dir {
					continue
				}
				relative := v3_include_path_below(name, framework_dirs[earlier]) or { continue }
				absent := v3_first_missing_path(search.dirs[earlier], relative)
				if absent.len > 0 {
					missing[absent] = true
				} else if !v3_path_is_older_than(search.dirs[earlier], relative, before) {
					inputs.unknown = '`${os.join_path(search.dirs[earlier], relative)}` appeared while the compiler ran'
				}
			}
		}
	}
	for name in asked {
		for position, dir in search.dirs {
			relative := v3_include_path_below(name, framework_dirs[position]) or { continue }
			absent := v3_first_missing_path(dir, relative)
			if absent.len > 0 {
				missing[absent] = true
			} else {
				files[os.join_path(dir, relative)] = true
			}
		}
	}
	for dir in search.absent {
		if !os.exists(dir) {
			missing[dir] = true
		} else {
			inputs.unknown = '`${dir}` appeared while the compiler ran'
		}
	}
	inputs.files = files.keys()
	inputs.files.sort()
	inputs.missing = missing.keys()
	inputs.missing.sort()
	for path in inputs.files {
		identity := v3_file_identity_from_before(path, before) or {
			if inputs.unknown.len == 0 {
				inputs.unknown = '`${path}` cannot be told apart from a changed file'
			}
			''
		}
		inputs.identities << identity
	}
	for path in inputs.missing {
		if path.contains_any('\n') && inputs.unknown.len == 0 {
			inputs.unknown = '`${path}` cannot be recorded'
		}
	}
	return inputs
}
