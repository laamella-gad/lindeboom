## Parses input with a grammar directly, without generating code. Makes the
## same decisions and builds the same tree as the generated parser.

import std/[packedsets, tables]
import ../runtime/parser, ../grammar/[ast, vocabulary], ./analysis

type
  Node* = ParseNode[int, int, int]
  Parser = ParserState[int, int, int]

proc fail(a: Analysis, p: Parser, expected: TokenSet) {.noreturn.} =
  var names: seq[string]
  for k in expected.sortedKinds: names.add a.v.tokens[k].name
  syntaxError(p.tokens[p.i].pos, expectedMessage(names, a.v.tokens[p.peek].name))

proc decide(a: Analysis, p: Parser, alts: seq[GExpr]): int =
  ## Index of the alternative selected by the current token.
  var all: TokenSet
  result = -1
  for i, alt in alts:
    let s = a.predict(alt)
    if result < 0 and p.peek in s: result = i
    all.incl s
  if result < 0: a.fail(p, all)

proc runRule(a: Analysis, p: var Parser, r: int, prec = 0): Node

proc run(a: Analysis, p: var Parser, n: Node, e: GExpr, label: int) =
  let label = if e.label.len > 0: a.labelIndex[e.label] else: label
  if e.isTokenSet:
    let s = a.tokens(e)
    if p.peek notin s: a.fail(p, s)
    p.take(n, label)
  else:
    case e.kind
    of ekSeq:
      for x in e.items: a.run(p, n, x, label)
    of ekAlt:
      a.run(p, n, e.items[a.decide(p, e.items)], label)
    of ekOpt:
      if p.peek in a.first(e.inner): a.run(p, n, e.inner, label)
    of ekStar:
      while p.peek in a.first(e.inner): a.run(p, n, e.inner, label)
    of ekPlus:
      a.run(p, n, e.inner, label)
      while p.peek in a.first(e.inner): a.run(p, n, e.inner, label)
    of ekRuleRef:
      n.add(a.runRule(p, a.ruleIndex[e.name], a.operandPrec.getOrDefault(e)), label)
    of ekLiteral, ekTokenRef:
      let k = a.tokenKind(e)
      if p.peek != k: a.fail(p, [k].toPackedSet)
      p.take(n, label)
    else:
      raiseAssert "not a parser element: " & $e.kind

func loopAlt(a: Analysis, p: Parser, r: int): int =
  ## The binary or suffix alternative of rule `r` selected by the current
  ## token, -1 if none.
  result = -1
  for k, alt in a.g.rules[r].alts:
    if a.isLoopAlt(r, k) and p.peek in a.continuation(alt.body): result = k

proc runRule(a: Analysis, p: var Parser, r: int, prec = 0): Node =
  let alts = a.g.rules[r].alts
  var heads: seq[int]
  var bodies: seq[GExpr]
  for k in 0 .. alts.high:
    if not a.isLoopAlt(r, k): heads.add k
  for k in heads: bodies.add alts[k].body
  let i = heads[if heads.len == 1: 0 else: a.decide(p, bodies)]
  result = p.newNode(a.altKinds[r][i])
  a.run(p, result, alts[i].body, 0)
  var k = a.loopAlt(p, r)
  while k >= 0 and a.precedence(r, k) >= prec:
    let items = alts[k].body.items
    let label = if items[0].label.len > 0: a.labelIndex[items[0].label] else: 0
    result = p.wrap(result, a.altKinds[r][k], label)
    for x in items[1 .. ^1]: a.run(p, result, x, 0)
    k = a.loopAlt(p, r)

func treeNames*(a: Analysis): TreeNames =
  result = TreeNames(kinds: a.kinds, labels: a.labels)
  for t in a.v.tokens: result.tokens.add t.name

proc interpret*(a: Analysis, tokens: seq[LexerToken[int]], src: string, rule: int,
    d: var Diagnostics): Node =
  ## Parses `tokens` (from `tokenize`) starting at `g.rules[rule]`, which must
  ## be followed by the end of the input. Returns nil after a lexical or
  ## syntax error, which is added to `d`.
  if not d.hasErrors:
    var p = initParserState[int, int, int](tokens, src)
    try:
      result = a.runRule(p, rule)
      if p.peek != 0: a.fail(p, [0].toPackedSet)
    except SyntaxError as e:
      d.error(e.pos, e.msg)
      result = nil
