## Parser for `.ldb` grammar files: runs the parser generated from `ldb.ldb`
## and turns its tree into a `Grammar`, decoding literals and checking the
## settings, lexer commands and `<assoc>` that `ldb.ldb` leaves to plain
## identifiers.
##
## Every syntax error is reported, but after one there is no `Grammar`; the
## other checks report every problem they find.

import std/[strutils, unicode]
import ../runtime/diagnostics, ./ast, ./ldb_parser

func raw(n: Node): string =
  ## The contents of a string literal or character set token, escapes kept.
  let s = n.text
  s[1 ..< s.high]

# ---- escapes ----

proc decodeEscape(d: var Diagnostics, s: string, i: var int, pos: SourcePos,
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
      d.error(pos, "invalid escape sequence '\\" & c & "'")
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
      d.error(pos, "invalid unicode escape '\\u" & hex & "'")
    else:
      result = Rune(parseHexInt(hex))
  else:
    d.error(pos, "invalid escape sequence '\\" & c & "'")
    result = Rune(c)

proc readRune(d: var Diagnostics, s: string, i: var int, pos: SourcePos,
    inSet: bool): Rune =
  if s[i] == '\\':
    result = d.decodeEscape(s, i, pos, inSet)
  else:
    fastRuneAt(s, i, result)

proc decodeLiteral(d: var Diagnostics, t: Node): string =
  let s = t.raw
  var i = 0
  while i < s.len:
    result.add d.readRune(s, i, t.pos, false)
  if result.len == 0:
    d.error(t.pos, "empty literal")

proc decodeSet(d: var Diagnostics, t: Node): seq[RuneRange] =
  let s = t.raw
  var i = 0
  while i < s.len:
    let lo = d.readRune(s, i, t.pos, true)
    if i + 1 < s.len and s[i] == '-':
      inc i
      let hi = d.readRune(s, i, t.pos, true)
      if int32(hi) < int32(lo):
        d.error(t.pos, "reversed range in character set [" & s & "]")
      result.add (lo, hi)
    else:
      result.add (lo, lo)
  if result.len == 0:
    d.error(t.pos, "empty character set")

proc singleRune(d: var Diagnostics, t: Node): Rune =
  let s = d.decodeLiteral(t)
  if s.runeLen != 1:
    d.error(t.pos, "range bound '" & t.raw & "' must be a single character")
  if s.len > 0: result = s.runeAt(0)

func isToken(n: Node, kind: TokenKind): bool =
  n.kind == nkToken and n.tok.kind == kind

func posAfter(n: Node, i: int): SourcePos =
  ## Position of the first token at or after son `i` of `n`; for empty
  ## alternatives, which have no position of their own.
  var j = i
  while j < n.len and n[j].pos.line == 0: inc j
  if j < n.len: n[j].pos else: n.pos

# ---- prequel: options, tokens, indentation ----

proc buildOptions(n: Node, g: var Grammar) =
  for o in n:
    if o.kind == nkOption:
      let v = o.value
      let value = if v.tok.kind == tkSTRING: v.raw else: v.text
      g.options.add GrammarOption(pos: o.name.pos, name: o.name.text, value: value)

proc buildTokenNames(n: Node, g: var Grammar) =
  for x in n:
    if x.isToken(tkID):
      g.tokens.add TokenDecl(pos: x.pos, name: x.text)
    elif x.kind == nkTokenNames:
      buildTokenNames(x, g)

proc buildSetting(n: Node, s: var IndentSetting, d: var Diagnostics) =
  let key = n.key
  if n.value == nil:
    d.error(key.pos, "indentation setting '" & key.text & "' takes a name")
  elif s.value.len > 0:
    d.error(key.pos, "duplicate indentation setting '" & key.text & "'")
  else:
    s = IndentSetting(pos: n.value.pos, value: n.value.text)

proc buildIndentation(n: Node, g: var Grammar, d: var Diagnostics) =
  if g.hasIndentation:
    d.error(n.pos, "duplicate 'indentation' block")
  g.hasIndentation = true
  g.indentation.pos = n.pos
  for s in n:
    if s.kind == nkSetting:
      let key = s.key
      case key.text
      of "newline": buildSetting(s, g.indentation.newline, d)
      of "indent": buildSetting(s, g.indentation.indent, d)
      of "dedent": buildSetting(s, g.indentation.dedent, d)
      of "tabs": buildSetting(s, g.indentation.tabs, d)
      of "brackets":
        if s.value != nil:
          d.error(key.pos, "'brackets' takes pairs of literals, as in '(' ')'")
        for b in s:
          if b.kind == nkBracket:
            g.indentation.brackets.add Bracket(pos: b.open.pos,
              open: d.decodeLiteral(b.open), close: d.decodeLiteral(b.close))
      else:
        d.error(key.pos, "unknown indentation setting '" & key.text &
          "' (expected newline, indent, dedent, brackets or tabs)")

# ---- rules ----

proc buildAtom(n: Node, d: var Diagnostics): GExpr

proc buildSeq(n: Node, pos: SourcePos, d: var Diagnostics): GExpr

func tokenRef(t: Node): GExpr =
  if t.text.isLexerName: GExpr(kind: ekTokenRef, pos: t.pos, name: t.text)
  else: GExpr(kind: ekRuleRef, pos: t.pos, name: t.text)

proc buildPrimary(n: Node, d: var Diagnostics): GExpr =
  case n.kind
  of nkLiteral:
    if n.len == 3:
      let lo = d.singleRune(n[0])
      let hi = d.singleRune(n[2])
      if int32(hi) < int32(lo):
        d.error(n.pos, "reversed range '" & n[0].raw & "'..'" & n[2].raw & "'")
      result = GExpr(kind: ekRange, pos: n.pos, lo: lo, hi: hi)
    else:
      result = GExpr(kind: ekLiteral, pos: n.pos, text: d.decodeLiteral(n[0]))
  of nkCharSet:
    result = GExpr(kind: ekCharSet, pos: n.pos, ranges: d.decodeSet(n[0]))
  of nkWildcard:
    result = GExpr(kind: ekWildcard, pos: n.pos)
  of nkNot:
    result = GExpr(kind: ekNot, pos: n.pos, inner: buildAtom(n[1], d), greedy: true)
  of nkBlock:
    var alts: seq[GExpr]
    for i, x in n.sons:
      if x.kind == nkSubAlt: alts.add buildSeq(x, n.posAfter(i), d)
    if alts.len == 1:
      result = alts[0]
      result.pos = n.pos
    else:
      result = GExpr(kind: ekAlt, pos: n.pos, items: alts)
  else:
    raiseAssert "not a primary: " & $n.kind

proc buildAtom(n: Node, d: var Diagnostics): GExpr =
  if n.kind == nkToken: tokenRef(n)
  elif n.kind == nkAtom: buildAtom(n[0], d)
  else: buildPrimary(n, d)

proc buildElement(n: Node, d: var Diagnostics): GExpr =
  var atom: GExpr
  if n.kind == nkIdElement and n.len > 1 and n[1].isToken(tkEq):
    atom = buildAtom(n[2], d)
    atom.label = n[0].text
  else:
    atom = buildAtom(n[0], d)
  result = atom
  let suffix = n.sons[^1]
  if suffix.kind == nkSuffix:
    let kind: range[ekOpt .. ekPlus] =
      case suffix.op.tok.kind
      of tkQuestion: ekOpt
      of tkStar: ekStar
      else: ekPlus
    result = GExpr(kind: kind, pos: atom.pos, inner: atom, greedy: suffix.lazy == nil)

proc buildSeq(n: Node, pos: SourcePos, d: var Diagnostics): GExpr =
  result = newSeqExpr(pos)
  for x in n:
    if x.kind in {nkIdElement, nkPlainElement}: result.items.add buildElement(x, d)

proc buildAssoc(n: Node, alt: var Alternative, d: var Diagnostics) =
  if n.key.text != "assoc":
    d.error(n.key.pos, "expected 'assoc' but found '" & n.key.text & "'")
  case n.value.text
  of "left": alt.assoc = assocLeft
  of "right": alt.assoc = assocRight
  else: d.error(n.value.pos, "expected 'left' or 'right' but found '" & n.value.text & "'")
  alt.hasAssoc = true

proc buildCommand(n: Node, alt: var Alternative, d: var Diagnostics) =
  let name = n.name
  let arg = if n.arg != nil: n.arg.text else: ""
  case name.text
  of "skip":
    if n.arg != nil: d.error(name.pos, "lexer command 'skip' takes no argument")
    alt.commands.add LexerCommand(pos: name.pos, kind: lcSkip)
  of "channel", "type":
    if n.arg == nil:
      d.error(name.pos, "lexer command '" & name.text & "' needs an argument, as in '" &
        name.text & "(NAME)'")
    let kind = if name.text == "channel": lcChannel else: lcType
    alt.commands.add LexerCommand(pos: name.pos, kind: kind, arg: arg)
  else:
    d.error(name.pos, "unknown lexer command '" & name.text &
      "' (expected skip, channel or type)")

proc buildAlt(n: Node, pos: SourcePos, d: var Diagnostics): Alternative =
  result.pos = pos
  var bodyStart = 0
  if n.len > 0 and n[0].kind == nkAssoc:
    buildAssoc(n[0], result, d)
    bodyStart = 1
  result.body = buildSeq(n, n.posAfter(bodyStart), d)
  if result.body.items.len == 0 and bodyStart == n.len: result.body.pos = pos
  if n.altLabel != nil:
    result.label = n.altLabel.text
    result.labelPos = n.altLabel.pos
  for x in n:
    if x.kind == nkCommand: buildCommand(x, result, d)

proc buildRule(n: Node, g: var Grammar, d: var Diagnostics) =
  let name = n.name
  var r = Rule(pos: n.pos, name: name.text, isFragment: n[0].isToken(tkFragment))
  r.kind = if name.text.isLexerName: rkLexer else: rkParser
  for i, x in n.sons:
    if x.kind == nkRuleAlt:
      # an empty alternative is where the `|` or `;` after it is
      let pos = if x.pos.line > 0: x.pos else: n[i + 1].pos
      r.alts.add buildAlt(x, pos, d)
  g.rules.add r

# ---- top level ----

proc parseGrammar*(src: string, d: var Diagnostics): Grammar =
  ## Parses `.ldb` source. Errors go to `d`; after a syntax error the result
  ## is empty.
  let res = parseFile(src, d.filename)
  d.items.add res.diagnostics.items
  if not res.diagnostics.hasErrors:
    let n = res.tree
    result.name = n.name.text
    result.pos = n.name.pos
    for x in n:
      if x.kind == nkTopLevel:
        let b = x[0]
        case b.kind
        of nkOptions: buildOptions(b, result)
        of nkTokens: buildTokenNames(b, result)
        of nkIndentation: buildIndentation(b, result, d)
        else: buildRule(b, result, d)
