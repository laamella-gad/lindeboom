## Lexer for `.ldb` grammar files (not to be confused with the generated lexers).
##
## `options {`, `tokens {` and `indentation {` are single tokens, so these
## words can still name rules.

import ../runtime/diagnostics

type
  TokenKind* = enum
    tkEof = "end of file"
    tkId = "identifier"
    tkInt = "integer"
    tkString = "string literal"
    tkCharSet = "character set"
    tkOptionsBlock = "'options {'"
    tkTokensBlock = "'tokens {'"
    tkIndentationBlock = "'indentation {'"
    tkRBrace = "'}'"
    tkColon = "':'"
    tkSemi = "';'"
    tkPipe = "'|'"
    tkLParen = "'('"
    tkRParen = "')'"
    tkQuestion = "'?'"
    tkStar = "'*'"
    tkPlus = "'+'"
    tkAssign = "'='"
    tkPlusAssign = "'+='"
    tkTilde = "'~'"
    tkDot = "'.'"
    tkRange = "'..'"
    tkHash = "'#'"
    tkArrow = "'->'"
    tkComma = "','"
    tkLt = "'<'"
    tkGt = "'>'"

  Token* = object
    kind*: TokenKind
    text*: string  ## identifier/integer text; raw contents of strings and
                   ## character sets (without delimiters)
    pos*: SourcePos

  Lexer = object
    src: string
    i, line, col: int

func pos(lx: Lexer): SourcePos = SourcePos(line: lx.line, col: lx.col)

func peek(lx: Lexer, ahead = 0): char =
  if lx.i + ahead < lx.src.len: lx.src[lx.i + ahead] else: '\0'

proc advance(lx: var Lexer) =
  if lx.i < lx.src.len:
    let c = lx.src[lx.i]
    inc lx.i
    if c == '\n':
      inc lx.line
      lx.col = 1
    elif (c.ord and 0xC0) != 0x80:
      # count code points, not UTF-8 continuation bytes
      inc lx.col

proc skipTrivia(lx: var Lexer, d: var Diagnostics) =
  ## Whitespace and comments.
  var more = true
  while more:
    case lx.peek
    of ' ', '\t', '\r', '\n':
      lx.advance()
    of '/':
      if lx.peek(1) == '/':
        while lx.peek notin {'\n', '\0'}: lx.advance()
      elif lx.peek(1) == '*':
        let start = lx.pos
        lx.advance(); lx.advance()
        while lx.i < lx.src.len and not (lx.peek == '*' and lx.peek(1) == '/'):
          lx.advance()
        if lx.i >= lx.src.len:
          d.error(start, "unterminated comment")
        else:
          lx.advance(); lx.advance()
      else:
        more = false
    else:
      more = false

proc scanQuoted(lx: var Lexer, d: var Diagnostics, close: char,
    what: string): string =
  ## Scans up to `close`, keeping escapes raw. Stops at end of line.
  let start = lx.pos
  lx.advance()
  let first = lx.i
  while lx.peek notin {close, '\n', '\0'}:
    if lx.peek == '\\' and lx.peek(1) notin {'\n', '\0'}: lx.advance()
    lx.advance()
  result = lx.src[first ..< lx.i]
  if lx.peek == close:
    lx.advance()
  else:
    d.error(start, "unterminated " & what)

proc blockKeyword(word: string): TokenKind =
  case word
  of "options": tkOptionsBlock
  of "tokens": tkTokensBlock
  of "indentation": tkIndentationBlock
  else: tkId

proc scanBlockBrace(lx: var Lexer): bool =
  ## After a block keyword: consume whitespace and `{` if present.
  var j = lx.i
  while j < lx.src.len and lx.src[j] in {' ', '\t', '\r', '\n'}: inc j
  if j < lx.src.len and lx.src[j] == '{':
    while lx.i <= j: lx.advance()
    result = true

proc next(lx: var Lexer, d: var Diagnostics): Token =
  lx.skipTrivia(d)
  result.pos = lx.pos
  let c = lx.peek
  case c
  of '\0':
    result.kind = tkEof
  of 'a'..'z', 'A'..'Z':
    let first = lx.i
    while lx.peek in {'a'..'z', 'A'..'Z', '0'..'9', '_'}: lx.advance()
    result.text = lx.src[first ..< lx.i]
    result.kind = tkId
    let blk = blockKeyword(result.text)
    if blk != tkId and lx.scanBlockBrace():
      result.kind = blk
  of '0'..'9':
    let first = lx.i
    while lx.peek in {'0'..'9'}: lx.advance()
    result.kind = tkInt
    result.text = lx.src[first ..< lx.i]
  of '\'':
    result.kind = tkString
    result.text = lx.scanQuoted(d, '\'', "string literal")
  of '[':
    result.kind = tkCharSet
    result.text = lx.scanQuoted(d, ']', "character set")
  else:
    let two = c & lx.peek(1)
    var kind = tkEof
    var len = 2
    case two
    of "+=": kind = tkPlusAssign
    of "..": kind = tkRange
    of "->": kind = tkArrow
    else:
      len = 1
      case c
      of '}': kind = tkRBrace
      of ':': kind = tkColon
      of ';': kind = tkSemi
      of '|': kind = tkPipe
      of '(': kind = tkLParen
      of ')': kind = tkRParen
      of '?': kind = tkQuestion
      of '*': kind = tkStar
      of '+': kind = tkPlus
      of '=': kind = tkAssign
      of '~': kind = tkTilde
      of '.': kind = tkDot
      of '#': kind = tkHash
      of ',': kind = tkComma
      of '<': kind = tkLt
      of '>': kind = tkGt
      else: len = 0
    if len == 0:
      d.error(result.pos, "unexpected character '" & c & "'")
      # skip the whole UTF-8 sequence
      lx.advance()
      while (lx.peek.ord and 0xC0) == 0x80: lx.advance()
      result = lx.next(d)
    else:
      for _ in 1..len: lx.advance()
      result.kind = kind

proc tokenize*(src: string, d: var Diagnostics): seq[Token] =
  ## All tokens of `src`, ending with `tkEof`.
  var lx = Lexer(src: src, line: 1, col: 1)
  while true:
    let t = lx.next(d)
    result.add t
    if t.kind == tkEof: break
