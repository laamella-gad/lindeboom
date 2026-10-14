## Sets of code points, and their encoding as UTF-8 byte ranges.

import std/algorithm

type
  CodeRange* = tuple[lo, hi: int32]
  CharSet* = seq[CodeRange]  ## sorted, non-overlapping, non-adjacent

  ByteRange* = tuple[lo, hi: uint8]

const
  maxCode* = 0x10FFFF'i32
  surrogates: CodeRange = (0xD800'i32, 0xDFFF'i32)

func normalize*(s: openArray[CodeRange]): CharSet =
  ## Sorts and merges overlapping or adjacent ranges.
  let sorted = s.sorted(proc (a, b: CodeRange): int = cmp(a.lo, b.lo))
  for r in sorted:
    if result.len > 0 and r.lo <= result[^1].hi + 1:
      result[^1].hi = max(result[^1].hi, r.hi)
    else:
      result.add r

func withoutSurrogates*(s: CharSet): CharSet =
  ## Surrogates have no valid UTF-8 encoding.
  for r in s:
    if r.hi < surrogates.lo or r.lo > surrogates.hi:
      result.add r
    else:
      if r.lo < surrogates.lo: result.add (r.lo, surrogates.lo - 1)
      if r.hi > surrogates.hi: result.add (surrogates.hi + 1, r.hi)

func complement*(s: CharSet): CharSet =
  ## All valid code points not in `s`. Surrogates are never included.
  var lo = 0'i32
  for r in s:
    if r.lo > lo: result.add (lo, r.lo - 1)
    lo = r.hi + 1
  if lo <= maxCode: result.add (lo, maxCode)
  result = result.withoutSurrogates()

func anyChar*(): CharSet =
  @[(0'i32, maxCode)].withoutSurrogates()

func encode(c: int32): seq[uint8] =
  if c < 0x80:
    @[uint8(c)]
  elif c < 0x800:
    @[uint8(0xC0 or (c shr 6)), uint8(0x80 or (c and 0x3F))]
  elif c < 0x10000:
    @[uint8(0xE0 or (c shr 12)), uint8(0x80 or ((c shr 6) and 0x3F)),
      uint8(0x80 or (c and 0x3F))]
  else:
    @[uint8(0xF0 or (c shr 18)), uint8(0x80 or ((c shr 12) and 0x3F)),
      uint8(0x80 or ((c shr 6) and 0x3F)), uint8(0x80 or (c and 0x3F))]

func splitRange(lo, hi: int32, result: var seq[seq[ByteRange]]) =
  # Split where the encoded length changes, then where a continuation byte
  # range doesn't cover all of 0x80..0xBF; what remains is a plain sequence
  # of byte ranges.
  for b in [0x7F'i32, 0x7FF, 0xFFFF]:
    if lo <= b and hi > b:
      splitRange(lo, b, result)
      splitRange(b + 1, hi, result)
      return
  for i in 1..3:
    let m = (1'i32 shl (6 * i)) - 1
    if (lo and not m) != (hi and not m):
      if (lo and m) != 0:
        splitRange(lo, lo or m, result)
        splitRange((lo or m) + 1, hi, result)
        return
      if (hi and m) != m:
        splitRange(lo, (hi and not m) - 1, result)
        splitRange(hi and not m, hi, result)
        return
  let a = encode(lo)
  let b = encode(hi)
  var s: seq[ByteRange]
  for k in 0 ..< a.len: s.add (a[k], b[k])
  result.add s

func utf8Sequences*(s: CharSet): seq[seq[ByteRange]] =
  ## Byte range sequences that together match exactly the UTF-8 encodings
  ## of the code points in `s`.
  for r in s.withoutSurrogates():
    splitRange(r.lo, r.hi, result)
