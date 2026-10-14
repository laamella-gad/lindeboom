## Table-driven lexer runtime shared by generated lexers and
## `lindeboom parse`.
##
## The tables describe a DFA over UTF-8 bytes. Bytes are first mapped to
## equivalence classes; `next[state * classCount + class]` is the next state,
## or -1 when there is none. State 0 is the start state.

import std/unicode
import ./diagnostics

export diagnostics

type
  TokenAction* = enum
    taEmit    ## produce a token
    taHidden  ## produce a token on the hidden channel
    taSkip    ## drop the matched text

  LexerTables* = object
    classes*: array[256, uint8]  ## byte -> equivalence class
    classCount*: int
    next*: seq[int32]
    acceptKind*: seq[int32]      ## per state: token kind, -1 if not accepting
    acceptAction*: seq[TokenAction]

  LexerToken*[K] = object
    kind*: K
    start*, stop*: int  ## byte offsets into the source, `stop` exclusive
    pos*: SourcePos
    hidden*: bool       ## on the hidden channel; the parser ignores it

func text*[K](t: LexerToken[K], src: string): string =
  src[t.start ..< t.stop]

func describeChar(src: string, i: int): string =
  ## The character at byte offset `i`, quoted for an error message.
  let n = min(src.runeLenAt(i), src.len - i)
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

proc tokenize*[K](t: LexerTables, src: string, d: var Diagnostics):
    seq[LexerToken[K]] =
  ## Splits `src` into tokens by longest match, ending with an end-of-file
  ## token of kind `K(0)`. Stops at the first error, without the end-of-file
  ## token.
  var i = 0
  var pos = SourcePos(line: 1, col: 1)
  var failed = false
  while i < src.len and not failed:
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
      d.error(pos, describeChar(src, i))
      failed = true
    else:
      if action != taSkip:
        result.add LexerToken[K](kind: K(kind), start: i, stop: stop, pos: pos,
          hidden: action == taHidden)
      pos.advancePos(src, i, stop)
      i = stop
  if not failed:
    result.add LexerToken[K](kind: K(0), start: src.len, stop: src.len, pos: pos)
