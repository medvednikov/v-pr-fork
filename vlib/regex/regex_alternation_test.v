import regex

fn test_alternation_chain_matches_every_branch() {
	for pattern in ['a|b|c', 'c|b|a', '(a)|(b)|(c)'] {
		for input in ['a', 'b', 'c'] {
			mut re := regex.regex_opt(pattern)!
			start, end := re.find(input)
			assert start == 0, '${pattern} on ${input}'
			assert end == input.len
		}
	}
}

fn test_quantified_alternation_preserves_previous_matches() {
	for input in ['a', 'b', 'ab', 'baaba'] {
		mut re := regex.regex_opt('(a|b)+')!
		start, end := re.find(input)
		assert start == 0
		assert end == input.len
	}
	mut re := regex.regex_opt('d(a|b)+z')!
	start, end := re.find('xxdabbazyy')
	assert start == 2
	assert end == 8
	assert re.get_group_by_id('xxdabbazyy', 0) == 'a'
	not_found, _ := re.find('dcz')
	assert not_found == -1
}

fn test_alternation_keeps_documented_token_semantics() {
	mut re := regex.regex_opt('(cat|dog)')!
	for input in ['catog', 'cadog'] {
		start, end := re.find(input)
		assert start == 0
		assert end == input.len
	}
	for input in ['cat', 'dog'] {
		start, _ := re.find(input)
		assert start == -1
	}
	mut grouped := regex.regex_opt('((cat)|(dog))+')!
	start, end := grouped.find('dogcat')
	assert start == 0
	assert end == 6
}
