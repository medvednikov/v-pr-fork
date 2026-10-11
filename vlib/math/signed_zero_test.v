module math

fn test_abs_float_signed_zero() {
	for value in [f64(0), copysign(0, -1)] {
		assert f64_bits(abs(value)) == 0
	}
	for value in [f32(0), f32_from_bits(0x80000000)] {
		assert f32_bits(abs(value)) == 0
	}
	assert abs(-4) == 4
	assert abs(i64(-4)) == 4
	assert abs(u64(4)) == 4
	assert abs(f32(-4)) == 4
	assert abs(f64(-4)) == 4
	assert abs(inf(-1)) == inf(1)
	assert is_nan(abs(nan()))
}

fn test_expm1_signed_zero() {
	for value in [f64(0), copysign(0, -1)] {
		assert f64_bits(expm1(value)) == f64_bits(value)
	}
	assert expm1(inf(-1)) == -1
	assert expm1(inf(1)) == inf(1)
	assert is_nan(expm1(nan()))
}
