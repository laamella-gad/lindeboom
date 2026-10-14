## Shared helpers for front-end tests.

import std/strutils
import lindeboom/grammar

proc messages*(src: string): seq[string] =
  ## Diagnostics of `src` as `line:col: severity: message`, in source order.
  let (_, d) = loadGrammar(src, "test.ldb")
  for x in d.sorted:
    var m = d.format(x)
    m.removePrefix("test.ldb:")
    result.add m

proc hasMessage*(src, expected: string): bool =
  ## True if some diagnostic of `src` contains `expected`.
  for m in messages(src):
    if expected in m: return true

proc ok*(src: string): bool =
  ## True if `src` has no diagnostics at all.
  messages(src).len == 0
