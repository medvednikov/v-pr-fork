module privlib

pub struct Item {
	weight int
pub mut:
	count int
}

struct Hidden {
	a int
pub mut:
	b int
}

pub struct S {
	secret int
mut:
	counter int
pub mut:
	shown  int
	items  []Item
	hidden []Hidden
}

const private_const = 42

fn private_fn() int {
	return private_const
}

fn (s S) private_method() int {
	return s.secret + s.counter
}

pub fn new() S {
	return S{
		items:  [Item{}]
		hidden: [Hidden{}]
	}
}
