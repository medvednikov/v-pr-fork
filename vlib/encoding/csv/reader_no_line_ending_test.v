import encoding.csv

fn test_reader_single_record_without_line_ending() {
	cases := [
		['a,b,c', 'a', 'b', 'c'],
		['a,b', 'a', 'b'],
		['"a","b"', 'a', 'b'],
		[',', '', ''],
		['a,', 'a', ''],
		[',b', '', 'b'],
	]
	for data in cases {
		mut reader := csv.new_reader(data[0])
		assert reader.read()! == data[1..]
		reader.read() or {
			assert err.msg() == 'encoding.csv: end of file'
			continue
		}
		assert false, 'read an extra record from ${data[0]}'
	}
}

fn test_single_record_is_independent_of_line_ending() {
	for ending in ['', '\n', '\r', '\r\n'] {
		for data in ['x', 'a,b,c', '"a","b",c', 'a,b,'] {
			mut reader := csv.new_reader(data + ending)
			mut unterminated := csv.new_reader(data)
			assert reader.read()! == unterminated.read()!
			reader.read() or {
				assert err.msg() == 'encoding.csv: end of file'
				continue
			}
			assert false, 'read an extra record for ${data} with ${ending.bytes()}'
		}
	}
}

fn test_reader_single_field_without_line_ending() {
	mut reader := csv.new_reader('value')
	assert reader.read()! == ['value']
	mut custom := csv.new_reader('a;b', delimiter: `;`)
	assert custom.read()! == ['a', 'b']
}

fn test_reader_empty_and_comment_only_documents() {
	for data in ['', '#comment'] {
		mut reader := csv.new_reader(data)
		reader.read() or {
			assert err.msg() == 'encoding.csv: end of file'
			continue
		}
		assert false, 'read a record from ${data}'
	}
}
