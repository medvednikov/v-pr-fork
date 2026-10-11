## Description

`encoding.base32` encodes and decodes Base32 data. Decoders reject bytes outside their alphabet.

Custom alphabets must contain exactly 32 distinct bytes, excluding CR, LF, and the padding byte.
Encoding constructors panic when these requirements are violated.
