## Parse trees and the parser runtime shared by generated parsers and
## `lindeboom parse`.
##
## A tree has one node type, in the style of the Nim compiler's `PNode`:
## `kind` is the rule or alternative label that produced the node, `sons` are
## its children in input order. Kind 0 is a token, kind 1 an error node: the
## tokens skipped where the parser recovered from a syntax error. `edge` is
## the element label of a node in its parent; label 0 means no label. (It is
## not called `label`, which is a common element label in grammars.)
##
## Error recovery works as in ANTLR. While the parser tries an alternative
## speculatively, a syntax error makes it backtrack. Otherwise the error is
## reported, and the rule it occurs in skips tokens until one that can follow
## a rule being parsed, then returns what it has so far. A loop facing a
## token that can neither start another iteration nor follow the loop skips
## tokens until one that can. No error is reported until a token has been
## matched since the last one.

import std/[algorithm, strutils]
import ./lexer

export lexer

type
  SourceText = ref object
    data: string

  ParseNode*[K, L, T] = ref object
    kind*: K            ## `K(0)` for a token, `K(1)` for an error node
    edge*: L            ## element label in the parent, `L(0)` if none
    tok*: LexerToken[T] ## when `kind == K(0)`
    sons*: seq[ParseNode[K, L, T]]
    source: SourceText

  ParseResult*[N] = object
    tree*: N            ## has error nodes if there were syntax errors
    diagnostics*: Diagnostics

  SyntaxError* = object of CatchableError
    pos*: SourcePos

  FollowProc* = proc (rule, kind: int): bool {.closure.}
    ## Whether token kind `kind` can follow rule number `rule`.

  ParserState*[K, L, T] = object
    ## Input of a generated parser: the visible tokens, ending with EOF.
    tokens*: seq[LexerToken[T]]
    i*: int
    source: SourceText
    names: seq[string]      ## token names by kind
    ruleNames: seq[string]  ## rule names by number
    follows: FollowProc
    errors: seq[SyntaxErrorInfo]
    failAt: int             ## farthest token where a match failed
    failExpected: seq[int]  ## token kinds expected there
    rules: seq[int]         ## the rules being parsed, innermost last
    speculating: int        ## speculative parses in progress
    recovering: bool        ## an error was reported and no token matched since
    reportedAt: int         ## token of the last reported error
    recoveredAt: int        ## token where the last recovery stopped
    recoveredDepth: int     ## rules being parsed then

  Mark*[K, L, T] = object
    ## Parser position to return to when a speculative parse fails.
    i*: int
    node: ParseNode[K, L, T]
    sons: int
    rules: int
    recovering: bool

  TreeNames* = object
    ## Display names by ordinal, for `treeRepr`.
    kinds*, labels*, tokens*: seq[string]

# ---- tree access ----

func len*[K, L, T](n: ParseNode[K, L, T]): int = n.sons.len

func `[]`*[K, L, T](n: ParseNode[K, L, T], i: int): ParseNode[K, L, T] = n.sons[i]

iterator items*[K, L, T](n: ParseNode[K, L, T]): ParseNode[K, L, T] =
  for x in n.sons: yield x

func son*[K, L, T](n: ParseNode[K, L, T], label: L): ParseNode[K, L, T] =
  ## The first son with `label`, nil if there is none.
  for x in n.sons:
    if x.edge == label: return x

func sonsWith*[K, L, T](n: ParseNode[K, L, T], label: L): seq[ParseNode[K, L, T]] =
  ## All sons with `label`.
  for x in n.sons:
    if x.edge == label: result.add x

func token*[K, L, T](n: ParseNode[K, L, T], kind: T): ParseNode[K, L, T] =
  ## The first son that is a token of `kind`, nil if there is none; for a
  ## token without an element label, as `'virtual'` in `'virtual'? ID`.
  for x in n.sons:
    if x.kind == K(0) and x.tok.kind == kind: return x

func has*[K, L, T](n: ParseNode[K, L, T], kind: T): bool =
  ## Whether a son of `n` is a token of `kind`.
  n.token(kind) != nil

func firstToken[K, L, T](n: ParseNode[K, L, T]): ParseNode[K, L, T] =
  if n.kind == K(0):
    result = n
  else:
    var i = 0
    while result == nil and i < n.sons.len:
      result = n.sons[i].firstToken
      inc i

func lastToken[K, L, T](n: ParseNode[K, L, T]): ParseNode[K, L, T] =
  if n.kind == K(0):
    result = n
  else:
    var i = n.sons.high
    while result == nil and i >= 0:
      result = n.sons[i].lastToken
      dec i

func text*[K, L, T](n: ParseNode[K, L, T]): string =
  ## The source text of `n`, including skipped input between its tokens.
  let a = n.firstToken
  if a != nil:
    result = n.source.data[a.tok.start ..< n.lastToken.tok.stop]

func pos*[K, L, T](n: ParseNode[K, L, T]): SourcePos =
  ## Position of the first token of `n`; line 0 if `n` has no tokens.
  let a = n.firstToken
  if a != nil: result = a.tok.pos

# ---- ASCII art ----

proc addTree[K, L, T](s: var string, n: ParseNode[K, L, T], names: TreeNames,
    prefix: string) =
  if n.kind == K(0):
    let name = names.tokens[ord(n.tok.kind)]
    s.add name
    let text = n.text
    if not name.startsWith('\'') and text.len > 0:
      s.add ' '
      s.addQuoted text
  else:
    s.add names.kinds[ord(n.kind)]
  s.add '\n'
  for i, x in n.sons:
    let last = i == n.sons.high
    s.add prefix & (if last: "└── " else: "├── ")
    if ord(x.edge) != 0: s.add names.labels[ord(x.edge)] & ": "
    s.addTree(x, names, prefix & (if last: "    " else: "│   "))

proc treeRepr*[K, L, T](n: ParseNode[K, L, T], names: TreeNames): string =
  ## `n` as an indented tree, one node per line.
  result.addTree(n, names, "")

func enumNames[E: enum](_: typedesc[E]): seq[string] =
  for x in E: result.add $x

proc treeRepr*[K: enum, L: enum, T: enum](n: ParseNode[K, L, T]): string =
  ## `n` as an indented tree, one node per line, using the enum names.
  n.treeRepr(TreeNames(kinds: enumNames(K), labels: enumNames(L),
    tokens: enumNames(T)))

# ---- parsing ----

func describeToken*(name: string): string =
  ## A token name for an error message.
  if name == "EOF": "end of input" else: name

func describeFound*(name, text: string): string =
  ## The token found, for an error message: its name, with its text unless
  ## the name says it (a literal, EOF) or the text is only white space.
  result = describeToken(name)
  if not name.startsWith('\'') and name != "EOF" and text.strip.len > 0:
    result.add " " & quoteText(text)

func expectedMessage*(expected: openArray[string], found: string): string =
  ## `expected ID, INT or '(' but found ':'`; `found` is as from
  ## `describeFound`.
  result = "expected "
  for i, x in expected:
    if i > 0: result.add(if i == expected.high: " or " else: ", ")
    result.add describeToken(x)
  result.add " but found " & found

func peek*[K, L, T](p: ParserState[K, L, T]): T = p.tokens[p.i].kind

proc newNode*[K, L, T](p: ParserState[K, L, T], kind: K): ParseNode[K, L, T] =
  ParseNode[K, L, T](kind: kind, source: p.source)

proc add*[K, L, T](n, son: ParseNode[K, L, T], label = L(0)) =
  son.edge = label
  n.sons.add son

proc wrap*[K, L, T](p: ParserState[K, L, T], left: ParseNode[K, L, T], kind: K,
    label = L(0)): ParseNode[K, L, T] =
  ## A new node of `kind` with `left` as its first son, for an operator that
  ## follows the expression `left`.
  result = p.newNode(kind)
  result.add(left, label)

proc take*[K, L, T](p: var ParserState[K, L, T], n: ParseNode[K, L, T],
    label = L(0)) =
  ## Adds the current token to `n` and moves past it. EOF is not added and
  ## stays current.
  if p.tokens[p.i].kind != T(0):
    n.add(ParseNode[K, L, T](kind: K(0), tok: p.tokens[p.i], source: p.source),
      label)
    inc p.i
  p.recovering = false

proc expect*[K, L, T, S](p: var ParserState[K, L, T], expected: S) =
  ## Notes that one of the `expected` token kinds was needed, or could have
  ## gone on, at the current token; if parsing fails there they are in the
  ## message. The error that is reported is the one at the farthest token,
  ## which after backtracking need not be the last one.
  if p.i > p.failAt:
    p.failAt = p.i
    p.failExpected.setLen 0
  if p.i == p.failAt:
    for x in expected:
      if ord(x) notin p.failExpected: p.failExpected.add ord(x)

proc report[K, L, T](p: var ParserState[K, L, T]) =
  ## Reports the farthest failure, unless the parser is still recovering
  ## from an error there or before. Expected tokens are listed by kind, with
  ## EOF last.
  if not p.recovering and p.failAt > p.reportedAt:
    var kinds = p.failExpected
    kinds.sort()
    var e = SyntaxErrorInfo(hasToken: true)
    for k in kinds:
      if k != 0: e.expected.add k
    if 0 in kinds: e.expected.add 0
    let found = p.tokens[p.failAt]
    e.pos = found.pos
    e.found = ord(found.kind)
    e.text = found.text(p.source.data)
    for r in p.rules: e.rules.add p.ruleNames[r]
    var expected: seq[string]
    for k in e.expected: expected.add p.names[k]
    e.msg = expectedMessage(expected, describeFound(p.names[e.found], e.text))
    p.errors.add e
    p.reportedAt = p.failAt
  p.recovering = true
  p.failAt = -1
  p.failExpected.setLen 0

proc fail*[K, L, T, S](p: var ParserState[K, L, T], expected: S) {.noreturn.} =
  ## Fails to match one of the `expected` token kinds at the current token.
  ## Unless speculating, reports the error; the rule recovers from it.
  p.expect(expected)
  if p.speculating == 0: p.report()
  raise (ref SyntaxError)(msg: "syntax error", pos: p.tokens[p.i].pos)

proc canFollow[K, L, T](p: ParserState[K, L, T], kind: T): bool =
  ## Whether `kind` is EOF or can follow one of the rules being parsed.
  result = kind == T(0)
  for r in p.rules:
    if p.follows(r, ord(kind)): result = true

proc skip[K, L, T](p: var ParserState[K, L, T], err: ParseNode[K, L, T]) =
  ## Adds the current token to the error node `err` and moves past it.
  err.sons.add ParseNode[K, L, T](kind: K(0), tok: p.tokens[p.i], source: p.source)
  inc p.i

proc errorNode[K, L, T](p: ParserState[K, L, T]): ParseNode[K, L, T] =
  p.newNode(K(1))

proc enter*[K, L, T](p: var ParserState[K, L, T], rule: int) =
  ## Starts parsing rule number `rule`.
  p.rules.add rule

proc leave*[K, L, T](p: var ParserState[K, L, T]) =
  ## Ends the innermost rule.
  discard p.rules.pop()

proc recover*[K, L, T](p: var ParserState[K, L, T], n: var ParseNode[K, L, T]) =
  ## After a syntax error in the innermost rule, whose node so far is `n`
  ## (nil if there is none yet): passes the error on while speculating,
  ## otherwise skips tokens until one that can follow a rule being parsed,
  ## into an error node added to `n`.
  if p.speculating > 0: raise (ref SyntaxError)(msg: "syntax error")
  let err = p.errorNode
  # recovering again where the last recovery stopped, in a rule at least as
  # deep, would not make progress
  if p.i == p.recoveredAt and p.rules.len >= p.recoveredDepth and p.peek != T(0):
    p.skip(err)
  while not p.canFollow(p.peek): p.skip(err)
  p.recoveredAt = p.i
  p.recoveredDepth = p.rules.len
  if n == nil: n = err
  else: n.add err

proc more*[K, L, T, S](p: var ParserState[K, L, T], n: ParseNode[K, L, T],
    first, follow: S): bool =
  ## Whether a loop whose body starts with `first` and that is followed by
  ## `follow` goes on. Unless speculating, a token in neither is an error:
  ## tokens are skipped into an error node added to `n` until one that is,
  ## or that can follow a rule being parsed. EOF just ends the loop, so
  ## `follow` need not have the EOF that can follow a start rule. When the
  ## loop ends, `first` is expected at the current token.
  result = p.peek in first
  if not result: p.expect(first)
  if not result and p.peek notin follow and p.peek != T(0) and p.speculating == 0:
    p.expect(follow)
    p.report()
    let err = p.errorNode
    while p.peek notin first and p.peek notin follow and not p.canFollow(p.peek):
      p.skip(err)
    n.add err
    result = p.peek in first

proc mark*[K, L, T](p: var ParserState[K, L, T], node: ParseNode[K, L, T]):
    Mark[K, L, T] =
  ## Starts a speculative parse at the current position, with the sons of
  ## `node` so far.
  result = Mark[K, L, T](i: p.i, node: node, sons: if node == nil: 0 else: node.sons.len,
    rules: p.rules.len, recovering: p.recovering)
  inc p.speculating

proc commit*[K, L, T](p: var ParserState[K, L, T], m: Mark[K, L, T]) =
  ## Ends the speculative parse started at `m`, which succeeded.
  dec p.speculating

proc reset*[K, L, T](p: var ParserState[K, L, T], node: var ParseNode[K, L, T],
    m: Mark[K, L, T]) =
  ## Returns to `m` after a failed speculative parse.
  p.i = m.i
  node = m.node
  if node != nil: node.sons.setLen m.sons
  p.rules.setLen m.rules
  p.recovering = m.recovering
  dec p.speculating

proc match*[K, L, T](p: var ParserState[K, L, T], n: ParseNode[K, L, T],
    kind: T, label = L(0)) =
  if p.peek != kind: p.fail({kind})
  p.take(n, label)

proc matchSet*[K, L, T](p: var ParserState[K, L, T], n: ParseNode[K, L, T],
    kinds: set[T], label = L(0)) =
  if p.peek notin kinds: p.fail(kinds)
  p.take(n, label)

proc initParserState*[K, L, T](tokens: seq[LexerToken[T]], src: string,
    names, ruleNames: seq[string], follows: FollowProc): ParserState[K, L, T] =
  ## `tokens` from `tokenize`, hidden tokens are dropped. `names` are the
  ## token names by kind and `ruleNames` the rule names by number, for
  ## messages.
  result.source = SourceText(data: src)
  result.names = names
  result.ruleNames = ruleNames
  result.follows = follows
  result.failAt = -1
  result.reportedAt = -1
  result.recoveredAt = -1
  for t in tokens:
    if not t.hidden: result.tokens.add t

proc finish*[K, L, T](p: var ParserState[K, L, T], n: ParseNode[K, L, T],
    d: var Diagnostics) =
  ## After the start rule, whose node is `n`: any input left is an error, and
  ## is skipped into an error node. Adds the syntax errors to `d`.
  if p.peek != T(0):
    p.expect([0])
    p.report()
    let err = p.errorNode
    while p.peek != T(0): p.skip(err)
    n.add err
  for e in p.errors: d.syntaxError(e)

proc runParser*[K, L, T](tokens: seq[LexerToken[T]], src: string,
    d: var Diagnostics, ruleNames: seq[string], follows: FollowProc,
    rule: proc (p: var ParserState[K, L, T]): ParseNode[K, L, T] {.nimcall.}):
    ParseNode[K, L, T] =
  ## Parses `tokens` with `rule`, which must be followed by the end of the
  ## input. Syntax errors are added to `d`; the tree has error nodes where
  ## the parser recovered from them.
  var p = initParserState[K, L, T](tokens, src, enumNames(T), ruleNames, follows)
  result = rule(p)
  p.finish(result, d)
