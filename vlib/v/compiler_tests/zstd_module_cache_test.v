import os

fn test_shipped_zstd_and_veb_use_module_cache() {
	$if windows {
		return
	} // This regression uses the Unix system C compiler cache path.
	root := os.join_path(os.vtmp_dir(), 'zstd_module_cache_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	sources := {
		'zstd': "import compress.zstd
fn main() {
 data := 'cached native source'.bytes()
 encoded := zstd.compress(data)!
 assert zstd.decompress(encoded)! == data
 println('zstd ok')
}"
		'veb':  'import veb
struct App { veb.Middleware[Context] }
struct Context { veb.Context }
pub fn (mut app App) index(mut ctx Context) veb.Result { return ctx.text("hello") }
fn main() {
 mut app := &App{}
 veb.run[App, Context](mut app, 18099)
}'
	}
	for name, source_text in sources {
		src := os.join_path(root, '${name}.v')
		binary := os.join_path(root, name + $if windows { '.exe' } $else { '' })
		cache := os.join_path(root, '${name}_cache')
		os.write_file(src, source_text)!
		args := ['env', 'V3CACHE=${cache}', 'V3_CACHE_TRACE=1', @VEXE, '-new-compiler', '-cc',
			'cc', '-no-retry-compilation', '-show-timings', '-o', binary, src]
		cold := os.exec(args)
		assert cold.exit_code == 0, cold.output
		assert !cold.output.contains('external C inputs cannot be assigned'), cold.output
		warm := os.exec(args)
		assert warm.exit_code == 0, warm.output
		assert warm.output.contains('monomorphize (cached)'), warm.output
		assert !warm.output.contains('external C inputs cannot be assigned'), warm.output
		if name == 'zstd' {
			run := os.exec([binary])
			assert run.exit_code == 0, run.output
			assert run.output.trim_space() == 'zstd ok', run.output
		}
	}
}
