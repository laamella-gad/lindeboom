## Parse trees and the parser runtime shared by generated parsers and
## `lindeboom parse`.
##
## A tree has one node type, in the style of the Nim compiler's `PNode`:
## `kind` is the rule or alternative label that produced the node, `sons` are
## its children in input order. Kind 0 is a token, label 0 means no label.

import std/strutils
import ./lexer

export lexer

type
  SourceText = ref object
    data: string

  ParseNode*[K, L, T] = ref object
    kind*: K            ## `K(0)` for a token
    label*: L           ## element label in the parent, `L(0)` if none
    tok*: LexerToken[T] ## when `kind == K(0)`
    sons*: seq[ParseNode[K, L, T]]
    source: SourceText

  ParseResult*[N] = object
    tree*: N            ## nil if there were errors
    diagnostics*: Diagnostics

  SyntaxError* = object of CatchableError
    pos*: SourcePos

  ParserState*[K, L, T] = object
    ## Input of a generated parser: the visible tokens, ending with EOF.
    tokens*: seq[LexerToken[T]]
    i*: int
    source: SourceText

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
    if x.label == label: return x

func sonsWith*[K, L, T](n: ParseNode[K, L, T], label: L): seq[ParseNode[K, L, T]] =
  ## All sons with `label`.
  for x in n.sons:
    if x.label == label: result.add x

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
    if ord(x.label) != 0: s.add names.labels[ord(x.label)] & ": "
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

func expectedMessage*(expected: openArray[string], found: string): string =
  ## `expected ID, INT or '(' but found ':'`
  result = "expected "
  for i, x in expected:
    if i > 0: result.add(if i == expected.high: " or " else: ", ")
    result.add describeToken(x)
  result.add " but found " & describeToken(found)

proc syntaxError*(pos: SourcePos, msg: string) {.noreturn.} =
  raise (ref SyntaxError)(msg: msg, pos: pos)

func peek*[K, L, T](p: ParserState[K, L, T]): T = p.tokens[p.i].kind

proc newNode*[K, L, T](p: ParserState[K, L, T], kind: K): ParseNode[K, L, T] =
  ParseNode[K, L, T](kind: kind, source: p.source)

proc add*[K, L, T](n, son: ParseNode[K, L, T], label = L(0)) =
  son.label = label
  n.sons.add son

proc take*[K, L, T](p: var ParserState[K, L, T], n: ParseNode[K, L, T],
    label = L(0)) =
  ## Adds the current token to `n` and moves past it. EOF is not added and
  ## stays current.
  if p.tokens[p.i].kind != T(0):
    n.add(ParseNode[K, L, T](kind: K(0), tok: p.tokens[p.i], source: p.source),
      label)
    inc p.i

proc fail*[K, L, T](p: ParserState[K, L, T], expected: set[T]) {.noreturn.} =
  var names: seq[string]
  for x in expected: names.add $x
  syntaxError(p.tokens[p.i].pos, expectedMessage(names, $p.peek))

proc match*[K, L, T](p: var ParserState[K, L, T], n: ParseNode[K, L, T],
    kind: T, label = L(0)) =
  if p.peek != kind: p.fail({kind})
  p.take(n, label)

proc matchSet*[K, L, T](p: var ParserState[K, L, T], n: ParseNode[K, L, T],
    kinds: set[T], label = L(0)) =
  if p.peek notin kinds: p.fail(kinds)
  p.take(n, label)

proc initParserState*[K, L, T](tokens: seq[LexerToken[T]], src: string):
    ParserState[K, L, T] =
  ## `tokens` from `tokenize`, hidden tokens are dropped.
  result.source = SourceText(data: src)
  for t in tokens:
    if not t.hidden: result.tokens.add t

proc runParser*[K, L, T](tokens: seq[LexerToken[T]], src: string,
    d: var Diagnostics,
    rule: proc (p: var ParserState[K, L, T]): ParseNode[K, L, T] {.nimcall.}):
    ParseNode[K, L, T] =
  ## Parses `tokens` with `rule`, which must be followed by the end of the
  ## input. Returns nil after a lexical or syntax error, which is added to
  ## `d`.
  if not d.hasErrors:
    var p = initParserState[K, L, T](tokens, src)
    try:
      result = rule(p)
      if p.peek != T(0): p.fail({T(0)})
    except SyntaxError as e:
      d.error(e.pos, e.msg)
      result = nil
