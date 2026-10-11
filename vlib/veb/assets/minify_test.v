import veb.assets

fn test_minify_css_preserves_selector_whitespace() {
	assert assets.minify_css('div\n span {\n color: red;\n }\n') == 'div span { color: red; }'
	assert assets.minify_css('a{}\n\n b{}\n') == 'a{} b{}'
	assert assets.minify_css('\n\t \n') == ''
}

fn test_minify_js_has_no_trailing_whitespace() {
	assert assets.minify_js('  const x = 1;\n\nconst y = 2;\n') == 'const x = 1; const y = 2;'
	assert assets.minify_js('const x = 1;') == 'const x = 1;'
	assert assets.minify_js('\n\t \n') == ''
}
