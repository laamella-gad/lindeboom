## Table-driven lexer runtime shared by generated lexers and
## `lindeboom parse`.
##
## The tables describe a DFA over UTF-8 bytes. Bytes are first mapped to
## equivalence classes; `next[state * classCount + class]` is the next state,
## or -1 when there is none. State 0 is the start state.
##
## With an `indentation` block, the tokens then go through a filter that
## drops newlines inside brackets and on blank lines, and adds indent and
## dedent tokens where the indentation of a line changes.

import std/unicode
import ./diagnostics

export diagnostics

type
  TokenAction* = enum
    taEmit    ## produce a token
    taHidden  ## produce a token on the hidden channel
    taSkip    ## drop the matched text

  TabMode* = enum
    tmExpand = "expand"  ## a tab advances to the next multiple of `tabWidth`
    tmStrict = "strict"  ## as expand, but the result must not depend on `tabWidth`
    tmError = "error"    ## tabs in indentation are an error

  IndentConfig* = object
    enabled*: bool
    newline*, indent*, dedent*: int32  ## token kinds
    opens*, closes*: seq[int32]        ## bracket token kinds
    tabs*: TabMode
    tabWidth*: int

  LexerTables* = object
    classes*: array[256, uint8]  ## byte -> equivalence class
    classCount*: int
    next*: seq[int32]
    acceptKind*: seq[int32]      ## per state: token kind, -1 if not accepting
    acceptAction*: seq[TokenAction]
    indentation*: IndentConfig

  LexerToken*[K] = object
    kind*: K
    start*, stop*: int  ## byte offsets into the source, `stop` exclusive
    pos*: SourcePos
    hidden*: bool       ## on the hidden channel; the parser ignores it

func text*[K](t: LexerToken[K], src: string): string =
  src[t.start ..< t.stop]

func charLen(src: string, i: int): int =
  ## Length of the UTF-8 character at byte offset `i`; 1 if it is invalid.
  let n = min(src.runeLenAt(i), src.len - i)
  if (n == 1 and ord(src[i]) >= 0x80) or src[i ..< i + n].validateUtf8() != -1: 1
  else: n

func describeChar(src: string, i: int): string =
  ## The character at byte offset `i`, quoted for an error message.
  let n = charLen(src, i)
  let ch = src[i ..< i + n]
  const hexChars = "0123456789ABCDEF"
  if (n == 1 and ord(src[i]) >= 0x80) or ch.validateUtf8() != -1:
    let b = ord(src[i])
    "invalid UTF-8 byte 0x" & hexChars[b shr 4] & hexChars[b and 0xF]
  else:
    let shown =
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
    "unexpected character '" & shown & "'"

proc advancePos(pos: var SourcePos, src: string, a, b: int) =
  ## Moves `pos` over `src[a ..< b]`.
  for i in a ..< b:
    if src[i] == '\n':
      inc pos.line
      pos.col = 1
    elif (ord(src[i]) and 0xC0) != 0x80:
      inc pos.col

type Indent = object
  width: int   ## with tabs expanded to `tabWidth`
  narrow: int  ## with tabs counted as one column

func indentOf(c: IndentConfig, src: string, start: int): (Indent, bool) =
  ## The indentation of the line containing byte offset `start`, measured up
  ## to `start`, and whether it contains a tab.
  var i = start
  while i > 0 and src[i - 1] != '\n': dec i
  var ind: Indent
  var hasTab = false
  for j in i ..< start:
    if src[j] == '\t':
      ind.width = (ind.width div c.tabWidth + 1) * c.tabWidth
      inc ind.narrow
      hasTab = true
    elif (ord(src[j]) and 0xC0) != 0x80:
      inc ind.width
      inc ind.narrow
  (ind, hasTab)

const inconsistentTabs = "inconsistent use of tabs and spaces in indentation"

func marker[K](kind: int32, at: LexerToken[K]): LexerToken[K] =
  ## An empty token of `kind` just before `at`.
  LexerToken[K](kind: K(kind), start: at.start, stop: at.start, pos: at.pos)

proc filterIndentation*[K](c: IndentConfig, src: string, tokens: seq[LexerToken[K]],
    d: var Diagnostics): seq[LexerToken[K]] =
  ## `tokens` with newlines dropped inside brackets and on lines without
  ## other tokens, an indent token before the first token of a line indented
  ## further than the one before, and dedent tokens for each level it closes.
  ## Ends with a newline and the remaining dedents before end of file. After
  ## an error, goes on as if the line were indented correctly.
  var stack = @[Indent()]
  var depth = 0          # open brackets
  var atLineStart = true # no token yet since the last newline
  var i = 0
  while i < tokens.len:
    let tok = tokens[i]
    let k = int32(ord(tok.kind))
    if tok.hidden:
      result.add tok
    elif k == c.newline:
      if depth == 0 and not atLineStart:
        result.add tok
        atLineStart = true
    elif k == 0:
      if not atLineStart: result.add marker(c.newline, tok)
      for _ in 1 ..< stack.len: result.add marker(c.dedent, tok)
      result.add tok
    else:
      if atLineStart:
        let (ind, hasTab) = c.indentOf(src, tok.start)
        var error = ""
        if hasTab and c.tabs == tmError:
          error = "tab in indentation; this grammar indents with spaces only"
        elif ind.width > stack[^1].width:
          # with strict tabs, the line must be indented further either way
          if c.tabs == tmStrict and ind.narrow <= stack[^1].narrow: error = inconsistentTabs
          stack.add ind
          result.add marker(c.indent, tok)
        else:
          while ind.width < stack[^1].width:
            discard stack.pop()
            result.add marker(c.dedent, tok)
          if ind.width != stack[^1].width:
            error = "unindent does not match any outer indentation level"
          elif c.tabs == tmStrict and ind.narrow != stack[^1].narrow:
            error = inconsistentTabs
        if error.len > 0: d.error(tok.pos, error)
        atLineStart = false
      if k in c.opens: inc depth
      elif k in c.closes and depth > 0: dec depth
      result.add tok
    inc i

proc tokenize*[K](t: LexerTables, src: string, d: var Diagnostics):
    seq[LexerToken[K]] =
  ## Splits `src` into tokens by longest match, ending with an end-of-file
  ## token of kind `K(0)`, and applies the indentation filter if the grammar
  ## has one. A character that cannot start a token is an error and is
  ## skipped; a run of them is one error.
  var i = 0
  var pos = SourcePos(line: 1, col: 1)
  var failed = false # the last character could not start a token
  while i < src.len:
    var state = 0'i32
    var j = i
    var kind = -1'i32
    var action = taEmit
    var stop = -1
    while j < src.len and state >= 0:
      state = t.next[int(state) * t.classCount + int(t.classes[ord(src[j])])]
      inc j
      if state >= 0 and t.acceptKind[state] >= 0:
        kind = t.acceptKind[state]
        action = t.acceptAction[state]
        stop = j
    if stop < 0:
      if not failed: d.error(pos, describeChar(src, i))
      failed = true
      stop = i + charLen(src, i)
      pos.advancePos(src, i, stop)
      i = stop
    else:
      failed = false
      if action != taSkip:
        result.add LexerToken[K](kind: K(kind), start: i, stop: stop, pos: pos,
          hidden: action == taHidden)
      pos.advancePos(src, i, stop)
      i = stop
  result.add LexerToken[K](kind: K(0), start: src.len, stop: src.len, pos: pos)
  if t.indentation.enabled:
    result = filterIndentation(t.indentation, src, result, d)
