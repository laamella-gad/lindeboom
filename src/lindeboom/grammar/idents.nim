## Turning grammar names into unique Nim identifiers.

import std/[sets, strutils]

func sanitize*(s: string): string =
  ## A valid Nim identifier: no `__`, no trailing `_`.
  for c in s:
    if c != '_' or (result.len > 0 and result[^1] != '_'): result.add c
  result.removeSuffix('_')

func nimNormalize*(s: string): string =
  ## Nim compares identifiers on the first character exactly, the rest
  ## ignoring case and underscores.
  result = $s[0]
  for c in s[1 .. ^1]:
    if c != '_': result.add toLowerAscii(c)

proc uniqueIdent*(base: string, used: var HashSet[string]): string =
  ## `base` sanitized, with a number appended if Nim would consider it equal
  ## to an identifier in `used`. Adds the result to `used`.
  let s = sanitize(base)
  result = s
  var n = 2
  while nimNormalize(result) in used:
    result = s & $n
    inc n
  used.incl nimNormalize(result)

func capitalized*(s: string): string =
  ## `ifStmt` -> `IfStmt`.
  result = s
  if result.len > 0: result[0] = toUpperAscii(result[0])
