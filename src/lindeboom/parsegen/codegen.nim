## Emits a generated parser module: `NodeKind`, `NodeLabel`, label
## accessors, one recursive-descent proc per rule and a `parse` proc per rule.

import std/[packedsets, strutils, tables]
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

proc wrapped(g: var Gen, indent: int, head: string, items: seq[string], tail: string) =
  ## `head` & items joined by ", " & `tail`, wrapped at 80 columns.
  var cur = repeat("  ", indent) & head
  for i, x in items:
    let item = x & (if i < items.high: "," else: tail)
    if cur.len + item.len + 1 > 80 and i > 0:
      g.s.add cur & "\n"
      cur = repeat("  ", indent + 2) & item
    else:
      cur.add(if i > 0: " " & item else: item)
  if items.len == 0: cur.add tail
  g.s.add cur & "\n"

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

proc genDecision(g: var Gen, alts: seq[GExpr], kinds: seq[string], label: string,
    indent: int) =
  ## `case p.peek` choosing between `alts`; a non-empty `kinds[i]` starts a
  ## new node of that kind for alternative i.
  var all: TokenSet
  g.line(indent, "case p.peek")
  for i, alt in alts:
    let s = g.a.predict(alt)
    if s.len > 0:
      all.incl s
      g.wrapped(indent, "of ", g.idents(s), ":")
      if kinds[i].len > 0: g.line(indent + 1, "result = p.newNode(" & kinds[i] & ")")
      g.genBody(alt, label, indent + 1)
  if all.len < g.a.v.tokens.len:
    g.line(indent, "else:")
    g.wrapped(indent + 1, "p.fail({", g.idents(all), "})")

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
    of ekOpt, ekStar:
      let s = g.a.first(e.inner)
      g.wrapped(indent, (if e.kind == ekOpt: "if" else: "while") & " p.peek in {",
        g.idents(s), "}:")
      g.genBody(e.inner, label, indent + 1)
    of ekPlus:
      g.line(indent, "while true:")
      g.genBody(e.inner, label, indent + 1)
      g.wrapped(indent + 1, "if p.peek notin {", g.idents(g.a.first(e.inner)), "}: break")
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

proc genLoop(g: var Gen, i: int) =
  ## The binary and suffix alternatives of precedence rule `i`.
  let r = g.a.g.rules[i]
  g.line(1, "while true:")
  g.line(2, "case p.peek")
  for k, alt in r.alts:
    if g.a.isLoopAlt(i, k):
      let items = alt.body.items
      g.wrapped(2, "of ", g.idents(g.a.continuation(alt.body)), ":")
      g.line(3, "if prec > " & $g.a.precedence(i, k) & ": break")
      let label = if items[0].label.len > 0: g.a.labelIdents[g.a.labelIndex[items[0].label]] else: ""
      g.line(3, "result = p.wrap(result, " & g.a.kindIdents[g.a.altKinds[i][k]] &
        labelArg(label) & ")")
      for x in items[1 .. ^1]: g.genExpr(x, "", 3)
  g.line(2, "else:")
  g.line(3, "break")

proc genRule(g: var Gen, i: int) =
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
  if heads.len == 1:
    if labelled: g.line(1, "result = p.newNode(" & kinds[0] & ")")
    g.genBody(heads[0], "", 1)
  else:
    g.genDecision(heads, kinds, "", 1)
  if prec: g.genLoop(i)
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
  for i in a.parserRules: g.genRule(i)

  g.s.add """
proc parseWith(src, filename: string,
    rule: proc (p: var Parser): Node {.nimcall.}): ParseResult[Node] =
  result.diagnostics.filename = filename
  let tokens = tokenize(src, result.diagnostics)
  result.tree = runParser[NodeKind, NodeLabel, TokenKind](tokens, src,
    result.diagnostics, rule)
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
