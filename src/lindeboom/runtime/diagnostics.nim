## Error and warning messages with source positions.

import std/algorithm

type
  Severity* = enum
    sevError = "error"
    sevWarning = "warning"

  SourcePos* = object
    line*, col*: int ## 1-based; `col` counts code points

  Diagnostic* = object
    filename*: string
    severity*: Severity
    pos*: SourcePos
    msg*: string

  Diagnostics* = object
    filename*: string
    items*: seq[Diagnostic]

func `<`*(a, b: SourcePos): bool =
  a.line < b.line or (a.line == b.line and a.col < b.col)

proc error*(d: var Diagnostics, pos: SourcePos, msg: string) =
  d.items.add Diagnostic(filename: d.filename, severity: sevError, pos: pos, msg: msg)

proc warning*(d: var Diagnostics, pos: SourcePos, msg: string) =
  d.items.add Diagnostic(filename: d.filename, severity: sevWarning, pos: pos, msg: msg)

func hasErrors*(d: Diagnostics): bool =
  for x in d.items:
    if x.severity == sevError: return true

func errorCount*(d: Diagnostics): int =
  for x in d.items:
    if x.severity == sevError: inc result

func `$`*(x: Diagnostic): string =
  ## `file:line:col: severity: message`
  x.filename & ":" & $x.pos.line & ":" & $x.pos.col & ": " & $x.severity &
    ": " & x.msg

func format*(d: Diagnostics, x: Diagnostic): string =
  ## `file:line:col: severity: message`, with the file name of `d`.
  var y = x
  y.filename = d.filename
  $y

func sorted*(d: Diagnostics): seq[Diagnostic] =
  ## Diagnostics in source order; stable for equal positions.
  d.items.sorted(proc (a, b: Diagnostic): int =
    if a.pos < b.pos: -1
    elif b.pos < a.pos: 1
    else: 0)

iterator items*(d: Diagnostics): Diagnostic =
  ## The diagnostics in source order.
  for x in d.sorted: yield x
