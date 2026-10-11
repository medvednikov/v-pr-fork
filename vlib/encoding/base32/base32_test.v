import encoding.base32

// TODO: add more tests

fn test_encode_and_decode() {
	input := 'hello v'

	encoded := base32.encode_string_to_string(input)
	assert encoded == 'NBSWY3DPEB3A===='

	decoded := base32.decode_string_to_string(encoded) or { panic('error decoding: ${err}') }
	assert decoded == input

	encoder_no_padding := base32.new_std_encoding_with_padding(base32.no_padding)
	encoded2 := encoder_no_padding.encode_string_to_string(input)
	assert encoded2 == 'NBSWY3DPEB3A'

	decoded2 := encoder_no_padding.decode_string_to_string(encoded2) or {
		panic('error decoding: ${err}')
	}
	assert decoded2 == input
}

fn test_decoder_rejects_out_of_alphabet_bytes() {
	for alphabet in [base32.std_alphabet, base32.hex_alphabet] {
		for padding in [base32.std_padding, base32.no_padding] {
			enc := base32.new_encoding_with_padding(alphabet, padding)
			for invalid in [u8(`?`), `!`, 0, 0x80, 0xff] {
				mut input := enc.encode_string_to_string('abcde').bytes()
				input[3] = invalid
				if result := enc.decode(input) {
					assert false, 'accepted invalid byte ${invalid}: ${result}'
				} else {
					assert err.msg() == 'illegal base32 data at input byte 3'
				}
			}
		}
	}
}
