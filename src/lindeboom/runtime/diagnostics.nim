## Error and warning messages with source positions.

import std/[algorithm, unicode]

type
  Severity* = enum
    sevError = "error"
    sevWarning = "warning"

  SourcePos* = object
    line*, col*: int ## 1-based; `col` counts code points

  SyntaxErrorInfo* = object
    ## What a syntax error is about, for a formatter that words the message
    ## itself. Token kinds are ordinals of the generated `TokenKind`.
    pos*: SourcePos
    msg*: string         ## the default message
    hasToken*: bool      ## false for an error from the lexer, which has no token
    found*: int          ## kind of the token found
    text*: string        ## its text; for a lexer error, the character that
                         ## starts no token, if that is the error
    expected*: seq[int]  ## kinds that could have come there, EOF last
    rules*: seq[string]  ## the rules being parsed, outermost first

  SyntaxErrorFormatter* = proc (e: SyntaxErrorInfo): string
    ## Turns a syntax error into its message.

  Diagnostic* = object
    filename*: string
    severity*: Severity
    pos*: SourcePos
    msg*: string
    syntax*: ref SyntaxErrorInfo  ## for a syntax error, nil otherwise

  Diagnostics* = object
    filename*: string
    items*: seq[Diagnostic]

func `<`*(a, b: SourcePos): bool =
  a.line < b.line or (a.line == b.line and a.col < b.col)

proc error*(d: var Diagnostics, pos: SourcePos, msg: string) =
  d.items.add Diagnostic(filename: d.filename, severity: sevError, pos: pos, msg: msg)

proc warning*(d: var Diagnostics, pos: SourcePos, msg: string) =
  d.items.add Diagnostic(filename: d.filename, severity: sevWarning, pos: pos, msg: msg)

proc syntaxError*(d: var Diagnostics, e: SyntaxErrorInfo) =
  ## Adds a syntax error with the default message of `e`.
  let info = new SyntaxErrorInfo
  info[] = e
  d.items.add Diagnostic(filename: d.filename, severity: sevError, pos: e.pos,
    msg: e.msg, syntax: info)

proc formatSyntaxErrors*(d: var Diagnostics, formatter: SyntaxErrorFormatter) =
  ## Rewords the syntax errors in `d` with `formatter`; nil keeps the
  ## default messages.
  if formatter != nil:
    for x in d.items.mitems:
      if x.syntax != nil: x.msg = formatter(x.syntax[])

func escapeChar*(ch: string): string =
  ## A valid UTF-8 character as it is written inside single quotes:
  ## backslash escapes for control characters, quotes and backslashes.
  const hexChars = "0123456789ABCDEF"
  case ch
  of "\n": "\\n"
  of "\r": "\\r"
  of "\t": "\\t"
  of "'": "\\'"
  of "\\": "\\\\"
  else:
    if ord(ch[0]) < 32 or ch[0] == '\x7F':
      "\\x" & hexChars[ord(ch[0]) shr 4] & hexChars[ord(ch[0]) and 0xF]
    else: ch

func quoteText*(text: string, maxLen = 20): string =
  ## `text` in single quotes for a message, escaped, and shortened with
  ## `...` after `maxLen` characters. Invalid UTF-8 bytes are shown as `\xHH`.
  const hexChars = "0123456789ABCDEF"
  result = "'"
  var i = 0
  var n = 0
  while i < text.len and n < maxLen:
    let len = min(text.runeLenAt(i), text.len - i)
    let ch = text[i ..< i + len]
    if (len == 1 and ord(text[i]) >= 0x80) or ch.validateUtf8() != -1:
      result.add "\\x" & hexChars[ord(text[i]) shr 4] & hexChars[ord(text[i]) and 0xF]
      inc i
    else:
      result.add escapeChar(ch)
      i += len
    inc n
  if i < text.len: result.add "..."
  result.add "'"

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
