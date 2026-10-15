## Parses input with a grammar directly, without generating code. Makes the
## same decisions and builds the same tree as the generated parser.

import std/[packedsets, tables]
import ../runtime/parser, ../grammar/[ast, vocabulary], ./analysis

type
  Node* = ParseNode[int, int, int]
  Parser = ParserState[int, int, int]

proc candidates(a: Analysis, p: var Parser, alts: seq[GExpr]): seq[int] =
  ## The alternatives that the current token can start, in order.
  for i, alt in alts:
    if p.peek in a.predict(alt): result.add i
  if result.len == 0: p.fail(a.expected(alts))

proc runRule(a: Analysis, p: var Parser, r: int, prec = 0): Node

proc run(a: Analysis, p: var Parser, n: Node, e: GExpr, label: int)

proc attempt(a: Analysis, p: var Parser, n: Node, e: GExpr, label: int): bool =
  ## Runs `e` speculatively: on a syntax error, returns false and leaves `p`
  ## and `n` as they were.
  var node = n
  let m = p.mark(node)
  try:
    a.run(p, n, e, label)
    p.commit(m)
    result = true
  except SyntaxError:
    p.reset(node, m)

proc runLoop(a: Analysis, p: var Parser, n: Node, e: GExpr, label: int) =
  ## The iterations of `*` or `+` after the first one.
  let first = a.first(e.inner)
  let follow = a.grammarFollow(e)
  if a.isAmbiguous(e):
    var more = true
    while more and p.more(n, first, follow): more = a.attempt(p, n, e.inner, label)
  else:
    while p.more(n, first, follow): a.run(p, n, e.inner, label)

proc run(a: Analysis, p: var Parser, n: Node, e: GExpr, label: int) =
  let label = if e.label.len > 0: a.labelIndex[e.label] else: label
  if e.isTokenSet:
    let s = a.tokens(e)
    if p.peek notin s: p.fail(s)
    p.take(n, label)
  else:
    case e.kind
    of ekSeq:
      for x in e.items: a.run(p, n, x, label)
    of ekAlt:
      let cands = a.candidates(p, e.items)
      var k = 0
      while k < cands.high and not a.attempt(p, n, e.items[cands[k]], label): inc k
      if k == cands.high: a.run(p, n, e.items[cands[k]], label)
    of ekOpt:
      if p.peek in a.first(e.inner):
        if a.isAmbiguous(e): discard a.attempt(p, n, e.inner, label)
        else: a.run(p, n, e.inner, label)
    of ekStar:
      a.runLoop(p, n, e, label)
    of ekPlus:
      a.run(p, n, e.inner, label)
      a.runLoop(p, n, e, label)
    of ekRuleRef:
      n.add(a.runRule(p, a.ruleIndex[e.name], a.operandPrec.getOrDefault(e)), label)
    of ekLiteral, ekTokenRef:
      let k = a.tokenKind(e)
      if p.peek != k: p.fail([k])
      p.take(n, label)
    else:
      raiseAssert "not a parser element: " & $e.kind

func isLabelled(a: Analysis, r: int): bool =
  ## Whether the alternatives of rule `r` have labels, and so node kinds of
  ## their own.
  a.g.rules[r].alts[0].label.len > 0

proc runAlt(a: Analysis, p: var Parser, r, k: int, n: var Node) =
  ## Alternative `k` of rule `r`, a primary or prefix one if `r` is a
  ## precedence rule, into `n`, or a new node for a labelled alternative.
  if a.isLabelled(r): n = p.newNode(a.altKinds[r][k])
  a.run(p, n, a.g.rules[r].alts[k].body, 0)

proc extend(a: Analysis, p: var Parser, r, k: int, n: var Node) =
  ## Binary or suffix alternative `k` of rule `r` after the expression `n`.
  let items = a.g.rules[r].alts[k].body.items
  let label = if items[0].label.len > 0: a.labelIndex[items[0].label] else: 0
  n = p.wrap(n, a.altKinds[r][k], label)
  for x in items[1 .. ^1]: a.run(p, n, x, 0)

proc runRuleBody(a: Analysis, p: var Parser, r, prec: int, result: var Node) =
  let alts = a.g.rules[r].alts
  var heads: seq[int]
  var bodies: seq[GExpr]
  for k in 0 .. alts.high:
    if not a.isLoopAlt(r, k):
      heads.add k
      bodies.add alts[k].body
  if not a.isLabelled(r): result = p.newNode(a.altKinds[r][0])
  let cands = if heads.len == 1: @[0] else: a.candidates(p, bodies)
  var i = 0
  var done = false
  while not done and i < cands.high:
    let m = p.mark(result)
    try:
      a.runAlt(p, r, heads[cands[i]], result)
      p.commit(m)
      done = true
    except SyntaxError:
      p.reset(result, m)
      inc i
  if not done: a.runAlt(p, r, heads[cands[i]], result)
  var more = a.isPrecRule[r]
  while more:
    # binary and suffix alternatives the current token can continue; all but
    # the last are tried speculatively
    var loopCands: seq[int]
    for k in 0 .. alts.high:
      if a.isLoopAlt(r, k) and p.peek in a.continuation(alts[k].body): loopCands.add k
    done = false
    for j, k in loopCands:
      if not done and a.precedence(r, k) >= prec:
        if j < loopCands.high:
          let m = p.mark(result)
          try:
            a.extend(p, r, k, result)
            p.commit(m)
            done = true
          except SyntaxError:
            p.reset(result, m)
        else:
          a.extend(p, r, k, result)
          done = true
    more = done

proc runRule(a: Analysis, p: var Parser, r: int, prec = 0): Node =
  p.enter(r)
  try:
    a.runRuleBody(p, r, prec, result)
  except SyntaxError:
    p.recover(result)
  p.leave()

func treeNames*(a: Analysis): TreeNames =
  result = TreeNames(kinds: a.kinds, labels: a.labels)
  for t in a.v.tokens: result.tokens.add t.name

proc interpret*(a: Analysis, tokens: seq[LexerToken[int]], src: string, rule: int,
    d: var Diagnostics): Node =
  ## Parses `tokens` (from `tokenize`) starting at `g.rules[rule]`, which must
  ## be followed by the end of the input. Syntax errors are added to `d`; the
  ## tree has error nodes where the parser recovered from them.
  var names: seq[string]
  for t in a.v.tokens: names.add t.name
  var follows = newSeq[TokenSet](a.g.rules.len)
  for r in a.parserRules: follows[r] = a.ruleFollow(r)
  var p = initParserState[int, int, int](tokens, src, names,
    proc (r, kind: int): bool = kind in follows[r])
  result = a.runRule(p, rule)
  p.finish(result, d)
