## Emits a generated parser module: `NodeKind`, `NodeLabel`, label
## accessors, one recursive-descent proc per rule and a `parse` proc per rule.

import std/[algorithm, packedsets, strutils, tables]
import ../grammar/[ast, vocabulary], ./analysis

type
  Gen = object
    a: Analysis
    s: string

const nimKeywords = ["addr", "and", "as", "asm", "bind", "block", "break", "case",
  "cast", "concept", "const", "continue", "converter", "defer", "discard",
  "distinct", "div", "do", "elif", "else", "end", "enum", "except", "export",
  "finally", "for", "from", "func", "if", "import", "in", "include", "interface",
  "is", "isnot", "iterator", "let", "macro", "method", "mixin", "mod", "nil", "not",
  "notin", "object", "of", "or", "out", "proc", "ptr", "raise", "ref", "return",
  "shl", "shr", "static", "template", "try", "tuple", "type", "using", "var",
  "when", "while", "xor", "yield"]

func procName(name: string): string =
  if name in nimKeywords: "`" & name & "`" else: name

func nimString(s: string): string =
  result = ""
  result.addQuoted s

func moduleBase*(g: Grammar): string =
  ## `MiniPy` -> `miniPy`, the prefix of the generated module names.
  result = g.name
  if result.len > 0: result[0] = toLowerAscii(result[0])

proc line(g: var Gen, indent: int, text: string) =
  g.s.add repeat("  ", indent) & text & "\n"

proc wrappedPieces(g: var Gen, indent: int, head: string, pieces: seq[string]) =
  ## `head` & pieces joined by " ", wrapped at 80 columns.
  var cur = repeat("  ", indent) & head
  for i, x in pieces:
    if cur.len + x.len + 1 > 80 and i > 0:
      g.s.add cur & "\n"
      cur = repeat("  ", indent + 2) & x
    else:
      cur.add(if i > 0: " " & x else: x)
  g.s.add cur & "\n"

proc wrapped(g: var Gen, indent: int, head: string, items: seq[string], tail: string) =
  ## `head` & items joined by ", " & `tail`, wrapped at 80 columns.
  var pieces: seq[string]
  for i, x in items: pieces.add x & (if i < items.high: "," else: tail)
  if items.len == 0: pieces.add tail
  g.wrappedPieces(indent, head, pieces)

proc wrappedSets(g: var Gen, indent: int, head: string, sets: seq[seq[string]],
    tail: string) =
  ## `head` & the sets as `{A, B}` joined by ", " & `tail`, wrapped at 80
  ## columns.
  var pieces: seq[string]
  for k, items in sets:
    let after = if k < sets.high: "," else: tail
    if items.len == 0: pieces.add "{}" & after
    for i, x in items:
      pieces.add (if i == 0: "{" else: "") & x & (if i < items.high: "," else: "}" & after)
  g.wrappedPieces(indent, head, pieces)

func idents(g: Gen, s: TokenSet): seq[string] =
  for k in s.sortedKinds: result.add g.a.v.tokens[k].ident

func labelArg(label: string): string =
  if label.len > 0: ", " & label else: ""

proc genExpr(g: var Gen, e: GExpr, label: string, indent: int)

proc genBody(g: var Gen, e: GExpr, label: string, indent: int) =
  ## Like `genExpr`, but never emits an empty block.
  let before = g.s.len
  g.genExpr(e, label, indent)
  if g.s.len == before: g.line(indent, "discard")

type Group = tuple
  cands: seq[int]  ## the alternatives a token can start, in order
  tokens: TokenSet

func cmpGroups(x, y: Group): int =
  ## By first alternative, then fewer alternatives, then the alternatives.
  result = cmp(x.cands[0], y.cands[0])
  if result == 0: result = cmp(x.cands.len, y.cands.len)
  var i = 0
  while result == 0 and i < x.cands.len:
    result = cmp(x.cands[i], y.cands[i])
    inc i

func groups(sets: seq[TokenSet]): seq[Group] =
  ## The tokens of `sets` grouped by the alternatives they select, ordered
  ## by first alternative, unambiguous groups first.
  var byCands: Table[seq[int], TokenSet]
  var all: TokenSet
  for s in sets: all.incl s
  for k in all:
    var cands: seq[int]
    for i, s in sets:
      if k in s: cands.add i
    byCands.mgetOrPut(cands, TokenSet()).incl k
  for cands, tokens in byCands: result.add (cands, tokens)
  result.sort(cmpGroups)

proc genCandidates(g: var Gen, alts: seq[GExpr], kinds: seq[string], cands: seq[int],
    label: string, indent: int) =
  ## Tries `cands` in order, backtracking from all but the last.
  let i = cands[0]
  let ind = if cands.len > 1: indent + 1 else: indent
  if cands.len > 1:
    g.line(indent, "let m = p.mark(result)")
    g.line(indent, "try:")
  if kinds[i].len > 0: g.line(ind, "result = p.newNode(" & kinds[i] & ")")
  g.genBody(alts[i], label, ind)
  if cands.len > 1:
    g.line(ind, "p.commit(m)")
    g.line(indent, "except SyntaxError:")
    g.line(indent + 1, "p.reset(result, m)")
    g.genCandidates(alts, kinds, cands[1 .. ^1], label, indent + 1)

proc genDecision(g: var Gen, alts: seq[GExpr], kinds: seq[string], label: string,
    indent: int) =
  ## `case p.peek` choosing between `alts`; a non-empty `kinds[i]` starts a
  ## new node of that kind for alternative i.
  var sets: seq[TokenSet]
  var all: TokenSet
  for alt in alts:
    sets.add g.a.predict(alt)
    all.incl sets[^1]
  g.line(indent, "case p.peek")
  for (cands, tokens) in groups(sets):
    g.wrapped(indent, "of ", g.idents(tokens), ":")
    g.genCandidates(alts, kinds, cands, label, indent + 1)
  if all.len < g.a.v.tokens.len:
    g.line(indent, "else:")
    g.wrapped(indent + 1, "p.fail({", g.idents(g.a.expected(alts)), "})")

proc genMore(g: var Gen, e: GExpr, head, tail: string, indent: int) =
  ## `head p.more(...) tail`: whether loop `e` goes on.
  g.wrappedSets(indent, head & "p.more(result, ", @[g.idents(g.a.first(e.inner)),
    g.idents(g.a.grammarFollow(e))], ")" & tail)

proc genIteration(g: var Gen, e: GExpr, label: string, indent: int) =
  ## One more iteration of `*` or `+` inside its `while`; when ambiguous,
  ## leaves the loop if it fails.
  if g.a.isAmbiguous(e):
    g.line(indent, "let m = p.mark(result)")
    g.line(indent, "try:")
    g.genBody(e.inner, label, indent + 1)
    g.line(indent + 1, "p.commit(m)")
    g.line(indent, "except SyntaxError:")
    g.line(indent + 1, "p.reset(result, m)")
    g.line(indent + 1, "break")
  else:
    g.genBody(e.inner, label, indent)

proc genExpr(g: var Gen, e: GExpr, label: string, indent: int) =
  let label = if e.label.len > 0: g.a.labelIdents[g.a.labelIndex[e.label]] else: label
  if e.isTokenSet:
    g.wrapped(indent, "p.matchSet(result, {", g.idents(g.a.tokens(e)), "}" & labelArg(label) & ")")
  else:
    case e.kind
    of ekSeq:
      for x in e.items: g.genExpr(x, label, indent)
    of ekAlt:
      g.genDecision(e.items, newSeq[string](e.items.len), label, indent)
    of ekOpt:
      g.wrapped(indent, "if p.peek in {", g.idents(g.a.first(e.inner)), "}:")
      if g.a.isAmbiguous(e):
        g.line(indent + 1, "let m = p.mark(result)")
        g.line(indent + 1, "try:")
        g.genBody(e.inner, label, indent + 2)
        g.line(indent + 2, "p.commit(m)")
        g.line(indent + 1, "except SyntaxError:")
        g.line(indent + 2, "p.reset(result, m)")
      else:
        g.genBody(e.inner, label, indent + 1)
    of ekStar:
      g.genMore(e, "while ", ":", indent)
      g.genIteration(e, label, indent + 1)
    of ekPlus:
      if g.a.isAmbiguous(e):
        g.genBody(e.inner, label, indent)
        g.genMore(e, "while ", ":", indent)
        g.genIteration(e, label, indent + 1)
      else:
        g.line(indent, "while true:")
        g.genBody(e.inner, label, indent + 1)
        g.genMore(e, "if not ", ": break", indent + 1)
    of ekRuleRef:
      let r = g.a.ruleIndex[e.name]
      let prec =
        if not g.a.isPrecRule[r]: ""
        else: ", " & $g.a.operandPrec.getOrDefault(e)
      g.line(indent, "result.add(rule" & g.a.ruleIdents[r] & "(p" & prec & ")" &
        labelArg(label) & ")")
    of ekLiteral, ekTokenRef:
      g.line(indent, "p.match(result, " & g.a.v.tokens[g.a.tokenKind(e)].ident &
        labelArg(label) & ")")
    else:
      raiseAssert "not a parser element: " & $e.kind

proc genExtend(g: var Gen, i, k, indent: int) =
  ## Binary or suffix alternative `k` of rule `i` after the expression so far.
  let items = g.a.g.rules[i].alts[k].body.items
  let label = if items[0].label.len > 0: g.a.labelIdents[g.a.labelIndex[items[0].label]] else: ""
  g.line(indent, "result = p.wrap(result, " & g.a.kindIdents[g.a.altKinds[i][k]] &
    labelArg(label) & ")")
  for x in items[1 .. ^1]: g.genExpr(x, "", indent)

proc genLoop(g: var Gen, i, indent: int) =
  ## The binary and suffix alternatives of precedence rule `i`.
  let r = g.a.g.rules[i]
  var loopAlts: seq[int]
  var sets: seq[TokenSet]
  for k, alt in r.alts:
    if g.a.isLoopAlt(i, k):
      loopAlts.add k
      sets.add g.a.continuation(alt.body)
  g.line(indent, "while true:")
  g.line(indent + 1, "case p.peek")
  for (cands, tokens) in groups(sets):
    g.wrapped(indent + 1, "of ", g.idents(tokens), ":")
    if cands.len == 1:
      let k = loopAlts[cands[0]]
      g.line(indent + 2, "if prec > " & $g.a.precedence(i, k) & ": break")
      g.genExtend(i, k, indent + 2)
    else:
      # all but the last are tried speculatively
      g.line(indent + 2, "var done = false")
      for j, c in cands:
        let k = loopAlts[c]
        g.line(indent + 2, (if j > 0: "if not done and " else: "if ") & "prec <= " &
          $g.a.precedence(i, k) & ":")
        if j < cands.high:
          g.line(indent + 3, "let m = p.mark(result)")
          g.line(indent + 3, "try:")
          g.genExtend(i, k, indent + 4)
          g.line(indent + 4, "p.commit(m)")
          g.line(indent + 4, "done = true")
          g.line(indent + 3, "except SyntaxError:")
          g.line(indent + 4, "p.reset(result, m)")
        else:
          g.genExtend(i, k, indent + 3)
          g.line(indent + 3, "done = true")
      g.line(indent + 2, "if not done: break")
  g.line(indent + 1, "else:")
  g.line(indent + 2, "break")

proc genRule(g: var Gen, i, number: int) =
  ## Rule `i`, rule number `number` for recovery.
  let r = g.a.g.rules[i]
  let labelled = r.alts[0].label.len > 0
  let prec = g.a.isPrecRule[i]
  g.line(0, "proc rule" & g.a.ruleIdents[i] & "(p: var Parser" &
    (if prec: ", prec: int" else: "") & "): Node =")
  g.line(1, "## `" & r.name & "`, line " & $r.pos.line)
  var kinds: seq[string]
  var heads: seq[GExpr]
  for k, alt in r.alts:
    if not g.a.isLoopAlt(i, k):
      kinds.add(if labelled: g.a.kindIdents[g.a.altKinds[i][k]] else: "")
      heads.add alt.body
  if not labelled:
    g.line(1, "result = p.newNode(" & g.a.kindIdents[g.a.altKinds[i][0]] & ")")
  g.line(1, "p.enter(" & $number & ")")
  g.line(1, "try:")
  if heads.len == 1:
    if labelled: g.line(2, "result = p.newNode(" & kinds[0] & ")")
    g.genBody(heads[0], "", 2)
  else:
    g.genDecision(heads, kinds, "", 2)
  if prec: g.genLoop(i, 2)
  g.line(1, "except SyntaxError:")
  g.line(2, "p.recover(result)")
  g.line(1, "p.leave()")
  g.s.add "\n"

proc genParserModule*(a: Analysis, grammarFile: string,
    runtimeImport = "lindeboom/runtime/parser"): string =
  ## Source of `<name>_parser.nim`. `a` must have been built without errors.
  var g = Gen(a: a)
  let lexerModule = moduleBase(a.g) & "_lexer"
  g.s = "## Generated by lindeboom from " & grammarFile & ". Do not edit.\n\n"
  g.s.add "import " & runtimeImport & "\nimport ./" & lexerModule & "\n\n"
  g.s.add "export parser, " & lexerModule & "\n\n"
  g.s.add "type\n  NodeKind* = enum\n"
  for k, name in a.kinds:
    g.line(2, a.kindIdents[k] & " = " & nimString(name))
  g.s.add "\n  NodeLabel* = enum\n"
  for k, name in a.labels:
    g.line(2, a.labelIdents[k] & " = " & nimString(name))
  g.s.add "\n  Node* = ParseNode[NodeKind, NodeLabel, TokenKind]\n"
  g.s.add "  Parser = ParserState[NodeKind, NodeLabel, TokenKind]\n\n"

  for k in 1 .. a.labels.high:
    if a.labelIsList[k]:
      g.line(0, "func " & procName(a.labels[k]) & "*(n: Node): seq[Node] = n.sonsWith(" &
        a.labelIdents[k] & ")")
    else:
      g.line(0, "func " & procName(a.labels[k]) & "*(n: Node): Node = n.son(" &
        a.labelIdents[k] & ")")
  if a.labels.len > 1: g.s.add "\n"

  for i in a.parserRules:
    g.line(0, "proc rule" & a.ruleIdents[i] & "(p: var Parser" &
      (if a.isPrecRule[i]: ", prec: int" else: "") & "): Node")
  g.s.add "\n"
  for number, i in a.parserRules: g.genRule(i, number)

  g.s.add "const followSets: array[" & $a.parserRules.len & ", set[TokenKind]] = [\n"
  for number, i in a.parserRules:
    g.wrapped(1, "{", g.idents(a.ruleFollow(i)),
      "}" & (if number < a.parserRules.high: "," else: "]") & " # " & a.g.rules[i].name)
  g.s.add """

proc follows(rule, kind: int): bool = TokenKind(kind) in followSets[rule]

proc parseWith(src, filename: string,
    rule: proc (p: var Parser): Node {.nimcall.}): ParseResult[Node] =
  result.diagnostics.filename = filename
  let tokens = tokenize(src, result.diagnostics)
  result.tree = runParser[NodeKind, NodeLabel, TokenKind](tokens, src,
    result.diagnostics, follows, rule)
"""
  for i in a.parserRules:
    let r = a.g.rules[i]
    g.s.add "\nproc parse" & a.ruleIdents[i] &
      "*(src: string, filename = \"input\"): ParseResult[Node] =\n"
    g.line(1, "## Parses `src` with rule `" & r.name & "`.")
    if a.isPrecRule[i]:
      g.line(1, "parseWith(src, filename, proc (p: var Parser): Node = rule" &
        a.ruleIdents[i] & "(p, 0))")
    else:
      g.line(1, "parseWith(src, filename, rule" & a.ruleIdents[i] & ")")
  g.s
