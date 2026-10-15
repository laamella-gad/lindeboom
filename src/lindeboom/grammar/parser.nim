## Recursive-descent parser for `.ldb` grammar files.
##
## Syntax errors are collected rather than fatal: after an error the parser
## skips to the end of the current rule or block and continues.

import std/[strutils, unicode]
import ../runtime/diagnostics, ./ast, ./scanner

type
  Parser = object
    toks: seq[Token]
    i: int
    d: Diagnostics

  SyntaxError = object of CatchableError

func cur(p: Parser): Token = p.toks[p.i]

func peekTok(p: Parser, ahead: int): Token =
  p.toks[min(p.i + ahead, p.toks.high)]

proc advance(p: var Parser) =
  if p.i < p.toks.high: inc p.i

func at(p: Parser, kind: TokenKind): bool = p.cur.kind == kind

func atWord(p: Parser, word: string): bool =
  p.cur.kind == tkId and p.cur.text == word

proc accept(p: var Parser, kind: TokenKind): bool =
  if p.at(kind):
    p.advance()
    result = true

func describe(t: Token): string =
  case t.kind
  of tkId, tkInt: "'" & t.text & "'"
  of tkString: "'" & t.text & "'"
  of tkCharSet: "[" & t.text & "]"
  else: $t.kind

proc fail(p: var Parser, msg: string) {.noreturn.} =
  p.d.error(p.cur.pos, msg)
  raise newException(SyntaxError, msg)

proc expect(p: var Parser, kind: TokenKind): Token =
  if not p.at(kind):
    p.fail("expected " & $kind & " but found " & describe(p.cur))
  result = p.cur
  p.advance()

proc skipPast(p: var Parser, kind: TokenKind) =
  while not p.at(kind) and not p.at(tkEof): p.advance()
  discard p.accept(kind)

func atRuleStart(p: Parser): bool =
  (p.at(tkId) and p.peekTok(1).kind == tkColon) or
    (p.atWord("fragment") and p.peekTok(1).kind == tkId and
      p.peekTok(2).kind == tkColon)

proc skipRule(p: var Parser) =
  ## Error recovery: skip to just after `;`, or to the start of the next rule.
  while not p.at(tkSemi) and not p.at(tkEof) and not p.atRuleStart():
    p.advance()
  discard p.accept(tkSemi)

# ---- escapes ----

proc decodeEscape(p: var Parser, s: string, i: var int, pos: SourcePos,
    inSet: bool): Rune =
  ## `s[i]` is a backslash; reads the escape and leaves `i` after it.
  inc i
  let c = if i < s.len: s[i] else: '\0'
  inc i
  case c
  of 'n': result = Rune('\n')
  of 'r': result = Rune('\r')
  of 't': result = Rune('\t')
  of 'b': result = Rune('\b')
  of 'f': result = Rune('\f')
  of '\\', '\'', '"': result = Rune(c)
  of ']', '[', '-':
    if not inSet:
      p.d.error(pos, "invalid escape sequence '\\" & c & "'")
    result = Rune(c)
  of 'u':
    var hex = ""
    if i < s.len and s[i] == '{':
      inc i
      while i < s.len and s[i] != '}':
        hex.add s[i]
        inc i
      inc i
    else:
      while i < s.len and hex.len < 4 and s[i] in HexDigits:
        hex.add s[i]
        inc i
    if hex.len == 0 or hex.len > 6 or not hex.allCharsInSet(HexDigits) or
        parseHexInt(hex) > 0x10FFFF:
      p.d.error(pos, "invalid unicode escape '\\u" & hex & "'")
    else:
      result = Rune(parseHexInt(hex))
  else:
    p.d.error(pos, "invalid escape sequence '\\" & c & "'")
    result = Rune(c)

proc readRune(p: var Parser, s: string, i: var int, pos: SourcePos,
    inSet: bool): Rune =
  if s[i] == '\\':
    result = p.decodeEscape(s, i, pos, inSet)
  else:
    fastRuneAt(s, i, result)

proc decodeLiteral(p: var Parser, t: Token): string =
  var i = 0
  while i < t.text.len:
    result.add p.readRune(t.text, i, t.pos, false)
  if result.len == 0:
    p.d.error(t.pos, "empty literal")

proc decodeSet(p: var Parser, t: Token): seq[RuneRange] =
  let s = t.text
  var i = 0
  while i < s.len:
    let lo = p.readRune(s, i, t.pos, true)
    if i + 1 < s.len and s[i] == '-':
      inc i
      let hi = p.readRune(s, i, t.pos, true)
      if int32(hi) < int32(lo):
        p.d.error(t.pos, "reversed range in character set [" & s & "]")
      result.add (lo, hi)
    else:
      result.add (lo, lo)
  if result.len == 0:
    p.d.error(t.pos, "empty character set")

proc singleRune(p: var Parser, t: Token): Rune =
  let s = p.decodeLiteral(t)
  if s.runeLen != 1:
    p.d.error(t.pos, "range bound '" & t.text & "' must be a single character")
  if s.len > 0: result = s.runeAt(0)

# ---- prequel: options, tokens, indentation ----

proc parseOptions(p: var Parser, g: var Grammar) =
  p.advance()
  while not p.at(tkRBrace) and not p.at(tkEof):
    let name = p.expect(tkId)
    discard p.expect(tkAssign)
    if p.cur.kind notin {tkId, tkInt, tkString}:
      p.fail("expected an option value but found " & describe(p.cur))
    g.options.add GrammarOption(pos: name.pos, name: name.text,
      value: p.cur.text)
    p.advance()
    discard p.expect(tkSemi)
  discard p.expect(tkRBrace)

proc parseTokens(p: var Parser, g: var Grammar) =
  p.advance()
  var more = not p.at(tkRBrace)
  while more:
    let name = p.expect(tkId)
    g.tokens.add TokenDecl(pos: name.pos, name: name.text)
    more = p.accept(tkComma) and not p.at(tkRBrace)
  discard p.expect(tkRBrace)

proc parseSetting(p: var Parser, key: Token, s: var IndentSetting) =
  let v = p.expect(tkId)
  if s.value.len > 0:
    p.d.error(key.pos, "duplicate indentation setting '" & key.text & "'")
  s = IndentSetting(pos: v.pos, value: v.text)

proc parseIndentation(p: var Parser, g: var Grammar) =
  if g.hasIndentation:
    p.d.error(p.cur.pos, "duplicate 'indentation' block")
  g.hasIndentation = true
  g.indentation.pos = p.cur.pos
  p.advance()
  while not p.at(tkRBrace) and not p.at(tkEof):
    let key = p.expect(tkId)
    discard p.expect(tkAssign)
    case key.text
    of "newline": p.parseSetting(key, g.indentation.newline)
    of "indent": p.parseSetting(key, g.indentation.indent)
    of "dedent": p.parseSetting(key, g.indentation.dedent)
    of "tabs": p.parseSetting(key, g.indentation.tabs)
    of "brackets":
      var more = true
      while more:
        let open = p.expect(tkString)
        let close = p.expect(tkString)
        g.indentation.brackets.add Bracket(pos: open.pos,
          open: p.decodeLiteral(open), close: p.decodeLiteral(close))
        more = p.accept(tkComma)
    else:
      p.d.error(key.pos, "unknown indentation setting '" & key.text &
        "' (expected newline, indent, dedent, brackets or tabs)")
      while not p.at(tkSemi) and not p.at(tkRBrace) and not p.at(tkEof):
        p.advance()
    discard p.expect(tkSemi)
  discard p.expect(tkRBrace)

# ---- rules ----

proc parseAlts(p: var Parser, top: bool): seq[Alternative]

proc parseAtom(p: var Parser): GExpr =
  let t = p.cur
  case t.kind
  of tkId:
    p.advance()
    if t.text.isLexerName:
      result = GExpr(kind: ekTokenRef, pos: t.pos, name: t.text)
    else:
      result = GExpr(kind: ekRuleRef, pos: t.pos, name: t.text)
  of tkString:
    p.advance()
    if p.accept(tkRange):
      let hiTok = p.expect(tkString)
      let lo = p.singleRune(t)
      let hi = p.singleRune(hiTok)
      if int32(hi) < int32(lo):
        p.d.error(t.pos, "reversed range '" & t.text & "'..'" & hiTok.text & "'")
      result = GExpr(kind: ekRange, pos: t.pos, lo: lo, hi: hi)
    else:
      result = GExpr(kind: ekLiteral, pos: t.pos, text: p.decodeLiteral(t))
  of tkCharSet:
    p.advance()
    result = GExpr(kind: ekCharSet, pos: t.pos, ranges: p.decodeSet(t))
  of tkDot:
    p.advance()
    result = GExpr(kind: ekWildcard, pos: t.pos)
  of tkTilde:
    p.advance()
    result = GExpr(kind: ekNot, pos: t.pos, inner: p.parseAtom(), greedy: true)
  of tkLParen:
    p.advance()
    let alts = p.parseAlts(top = false)
    discard p.expect(tkRParen)
    if alts.len == 1:
      result = alts[0].body
      result.pos = t.pos
    else:
      result = GExpr(kind: ekAlt, pos: t.pos)
      for a in alts: result.items.add a.body
  else:
    p.fail("expected a grammar element but found " & describe(t))

proc parseElement(p: var Parser): GExpr =
  var label = ""
  if p.at(tkId) and p.peekTok(1).kind == tkAssign:
    label = p.cur.text
    p.advance()
    p.advance()
  let atom = p.parseAtom()
  atom.label = label
  result = atom
  if p.cur.kind in {tkQuestion, tkStar, tkPlus}:
    let kind: range[ekOpt .. ekPlus] =
      case p.cur.kind
      of tkQuestion: ekOpt
      of tkStar: ekStar
      else: ekPlus
    p.advance()
    let greedy = not p.accept(tkQuestion)
    result = GExpr(kind: kind, pos: atom.pos, inner: atom, greedy: greedy)

proc parseCommand(p: var Parser, alt: var Alternative) =
  let t = p.expect(tkId)
  case t.text
  of "skip":
    alt.commands.add LexerCommand(pos: t.pos, kind: lcSkip)
  of "channel", "type":
    discard p.expect(tkLParen)
    let arg = p.expect(tkId)
    discard p.expect(tkRParen)
    let kind = if t.text == "channel": lcChannel else: lcType
    alt.commands.add LexerCommand(pos: t.pos, kind: kind, arg: arg.text)
  else:
    p.d.error(t.pos, "unknown lexer command '" & t.text &
      "' (expected skip, channel or type)")
    if p.accept(tkLParen):
      p.skipPast(tkRParen)

proc parseAlt(p: var Parser, top: bool): Alternative =
  result.pos = p.cur.pos
  if p.at(tkLt):
    let ltPos = p.cur.pos
    p.advance()
    let key = p.expect(tkId)
    if key.text != "assoc":
      p.d.error(key.pos, "expected 'assoc' but found '" & key.text & "'")
    discard p.expect(tkAssign)
    let v = p.expect(tkId)
    case v.text
    of "left": result.assoc = assocLeft
    of "right": result.assoc = assocRight
    else: p.d.error(v.pos, "expected 'left' or 'right' but found '" & v.text & "'")
    discard p.expect(tkGt)
    result.hasAssoc = true
    if not top:
      p.d.error(ltPos, "'<assoc>' is only allowed at the start of a rule alternative")
  result.body = newSeqExpr(p.cur.pos)
  while p.cur.kind notin {tkPipe, tkSemi, tkRParen, tkHash, tkArrow, tkEof} and
      not p.atRuleStart():
    result.body.items.add p.parseElement()
  if p.at(tkHash):
    if not top:
      p.d.error(p.cur.pos, "alternative labels are only allowed on rule alternatives")
    p.advance()
    let label = p.expect(tkId)
    result.label = label.text
    result.labelPos = label.pos
  if p.at(tkArrow):
    if not top:
      p.d.error(p.cur.pos, "lexer commands are only allowed at the end of a rule alternative")
    p.advance()
    p.parseCommand(result)
    while p.accept(tkComma): p.parseCommand(result)

proc parseAlts(p: var Parser, top: bool): seq[Alternative] =
  result.add p.parseAlt(top)
  while p.accept(tkPipe): result.add p.parseAlt(top)

proc parseRule(p: var Parser, g: var Grammar) =
  var r = Rule(pos: p.cur.pos)
  if p.atWord("fragment") and p.peekTok(1).kind == tkId:
    r.isFragment = true
    p.advance()
  let name = p.expect(tkId)
  r.name = name.text
  r.kind = if name.text.isLexerName: rkLexer else: rkParser
  discard p.expect(tkColon)
  r.alts = p.parseAlts(top = true)
  discard p.expect(tkSemi)
  g.rules.add r

# ---- top level ----

proc parseHeader(p: var Parser, g: var Grammar) =
  if p.atWord("grammar") and p.peekTok(1).kind == tkId:
    p.advance()
    g.name = p.cur.text
    g.pos = p.cur.pos
    p.advance()
    if not p.accept(tkSemi):
      p.d.error(p.cur.pos, "expected ';' after grammar name")
  else:
    p.d.error(p.cur.pos, "expected 'grammar Name;' at the start of the file")

proc parseTopLevel(p: var Parser, g: var Grammar) =
  case p.cur.kind
  of tkOptionsBlock: p.parseOptions(g)
  of tkTokensBlock: p.parseTokens(g)
  of tkIndentationBlock: p.parseIndentation(g)
  else: p.parseRule(g)

proc parseGrammar*(src: string, d: var Diagnostics): Grammar =
  ## Parses `.ldb` source. Errors go to `d`; the result holds everything
  ## that could be parsed.
  var p = Parser(d: move d)
  p.toks = tokenize(src, p.d)
  p.parseHeader(result)
  while not p.at(tkEof):
    let wasBlock = p.cur.kind in
      {tkOptionsBlock, tkTokensBlock, tkIndentationBlock}
    let start = p.i
    try:
      p.parseTopLevel(result)
    except SyntaxError:
      if wasBlock: p.skipPast(tkRBrace)
      else: p.skipRule()
      if p.i == start: p.advance()
  d = move p.d
