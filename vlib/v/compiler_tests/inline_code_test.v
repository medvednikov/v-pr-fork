import os

fn test_inline_code_separate_and_equals_arguments() {
	for eval_args in [['-e', 'println(1)'], ['-e=println(1)']] {
		mut args := [@VEXE, '-new-compiler', '-no-retry-compilation', '-nocache']
		args << eval_args
		result := os.exec(args)
		assert result.exit_code == 0, result.output
		assert result.output.trim_space() == '1'
	}
}

fn test_inline_code_forwards_arguments_and_exit_status() {
	result := os.exec([@VEXE, '-new-compiler', '-no-retry-compilation', '-nocache', '-e',
		'import os; println(os.args[1..]); exit(7)', '--custom', 'with spaces'])
	assert result.exit_code == 7, result.output
	assert result.output.trim_space() == "['--custom', 'with spaces']"
}

fn test_inline_code_reports_missing_source() {
	result := os.exec([@VEXE, '-new-compiler', '-no-retry-compilation', '-e'])
	assert result.exit_code != 0
	assert result.output.contains('option `-e` requires a value')
}

fn test_http_shortcut_accepts_the_option() {
	// Syntax checking validates the shortcut without leaving a server running.
	result := os.exec([@VEXE, '-new-compiler', '-no-retry-compilation', '-nocache', '-check-syntax',
		'-http'])
	assert result.exit_code == 0, result.output
	assert !result.output.contains('unknown option')
}
