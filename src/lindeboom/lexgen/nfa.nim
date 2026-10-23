## Thompson NFA over UTF-8 bytes, built from a grammar's lexer rules and the
## literals used in its parser rules.
##
## Edge order matters: the DFA keeps threads in priority order to implement
## non-greedy loops (see `dfa.nim`). Each token gets a priority group, lower
## groups winning ties: literals first, then lexer rules in file order.

import std/[tables, unicode]
import ../runtime/lexer, ../grammar/[ast, vocabulary], ./charsets

type
  Edge* = object
    target*: int32
    eps*: bool        ## epsilon edge; otherwise matches bytes `lo..hi`
    lo*, hi*: uint8

  NfaState* = object
    edges*: seq[Edge]
    accept*: int32    ## index into `Nfa.accepts`, -1 if not accepting
    nonGreedy*: bool  ## decision of a non-greedy operator
    group*: int32     ## priority group of the token this state belongs to

  Accept* = object
    kind*: int32      ## token kind produced, after `type()`
    action*: TokenAction
    group*: int32     ## kind of the literal or lexer rule matched

  Nfa* = object
    states*: seq[NfaState]  ## state 0 is the start state
    accepts*: seq[Accept]

  Builder = object
    nfa: Nfa
    g: Grammar
    rules: Table[string, int]
    group: int32

proc newState(b: var Builder, nonGreedy = false): int32 =
  result = int32(b.nfa.states.len)
  b.nfa.states.add NfaState(accept: -1, nonGreedy: nonGreedy, group: b.group)

proc eps(b: var Builder, a, c: int32) =
  b.nfa.states[a].edges.add Edge(target: c, eps: true)

func charSet(e: GExpr): CharSet =
  ## The code points matched by a single-character expression.
  case e.kind
  of ekCharSet:
    var rs: seq[CodeRange]
    for r in e.ranges: rs.add (int32(r.lo), int32(r.hi))
    result = normalize(rs)
  of ekRange:
    result = @[(int32(e.lo), int32(e.hi))]
  of ekLiteral:
    let c = int32(e.text.runeAt(0))
    result = @[(c, c)]
  of ekAlt, ekSeq:
    var rs: seq[CodeRange]
    for x in e.items: rs.add x.charSet
    result = normalize(rs)
  of ekWildcard:
    result = anyChar()
  of ekNot:
    result = e.inner.charSet.complement
  else:
    raiseAssert "not a single-character expression: " & $e.kind

proc addSet(b: var Builder, s: int32, cs: CharSet): int32 =
  result = b.newState()
  for byteSeq in utf8Sequences(cs):
    var cur = s
    for k, br in byteSeq:
      let t = if k == byteSeq.high: result else: b.newState()
      b.nfa.states[cur].edges.add Edge(target: t, lo: br.lo, hi: br.hi)
      cur = t

func asciiOnly(s: CharSet): bool =
  for r in s:
    if r.hi >= 0x80: return false
  true

proc addRawByteFallback(b: var Builder, s, t: int32) =
  ## Let a wildcard, or a negated set that excludes only ASCII, also match
  ## a single raw non-ASCII byte. This keeps the code-point semantics for
  ## Unicode-aware sets while letting byte-oriented languages (Lua strings
  ## and comments) lex input that is not valid UTF-8. Valid UTF-8 still
  ## matches through the normal sequences; this is an extra path, not a
  ## replacement.
  b.nfa.states[s].edges.add Edge(target: t, lo: 0x80, hi: 0xFF)

proc compileAlts(b: var Builder, bodies: seq[GExpr], s: int32): int32

proc compile(b: var Builder, e: GExpr, s: int32): int32 =
  ## Adds `e` starting at state `s`; returns the state where it ends.
  case e.kind
  of ekSeq:
    result = s
    for x in e.items: result = b.compile(x, result)
  of ekAlt:
    result = b.compileAlts(e.items, s)
  of ekOpt:
    let d = b.newState(nonGreedy = not e.greedy)
    let body = b.newState()
    result = b.newState()
    b.eps(s, d)
    if e.greedy:
      b.eps(d, body)
      b.eps(d, result)
    else:
      b.eps(d, result)
      b.eps(d, body)
    b.eps(b.compile(e.inner, body), result)
  of ekStar, ekPlus:
    # `x*`: s -> d, d -> body -> d, d -> exit. `x+`: s -> body -> d.
    let d = b.newState(nonGreedy = not e.greedy)
    let body = b.newState()
    result = b.newState()
    b.eps(s, if e.kind == ekStar: d else: body)
    b.eps(b.compile(e.inner, body), d)
    if e.greedy:
      b.eps(d, body)
      b.eps(d, result)
    else:
      b.eps(d, result)
      b.eps(d, body)
  of ekLiteral:
    result = s
    for r in e.text.runes:
      result = b.addSet(result, @[(int32(r), int32(r))])
  of ekCharSet, ekRange:
    result = b.addSet(s, e.charSet)
  of ekWildcard:
    result = b.addSet(s, e.charSet)
    b.addRawByteFallback(s, result)
  of ekNot:
    result = b.addSet(s, e.charSet)
    if asciiOnly(e.inner.charSet):
      b.addRawByteFallback(s, result)
  of ekTokenRef:
    var bodies: seq[GExpr]
    for a in b.g.rules[b.rules[e.name]].alts: bodies.add a.body
    result = b.compileAlts(bodies, s)
  of ekRuleRef:
    raiseAssert "parser rule in lexer rule: " & e.name

proc compileAlts(b: var Builder, bodies: seq[GExpr], s: int32): int32 =
  result = b.newState()
  for body in bodies:
    let a = b.newState()
    b.eps(s, a)
    b.eps(b.compile(body, a), result)

proc addAccept(b: var Builder, state: int32, kind: int32, action: TokenAction) =
  b.nfa.states[state].accept = int32(b.nfa.accepts.len)
  b.nfa.accepts.add Accept(kind: kind, action: action, group: b.group)

func action(a: Alternative, v: Vocabulary, kind: var int32): TokenAction =
  result = taEmit
  for cmd in a.commands:
    case cmd.kind
    of lcSkip: result = taSkip
    of lcChannel:
      if result != taSkip: result = taHidden
    of lcType: kind = int32(v.byName[cmd.arg])

proc buildNfa*(g: Grammar, v: Vocabulary): Nfa =
  ## Assumes `g` passed `checkGrammar` without errors.
  var b = Builder(g: g)
  for i, r in g.rules: b.rules[r.name] = i
  discard b.newState()
  for kind, t in v.tokens:
    b.group = int32(kind)
    case t.source
    of tsLiteral:
      let s = b.newState()
      b.eps(0, s)
      var e = s
      for r in t.text.runes: e = b.addSet(e, @[(int32(r), int32(r))])
      b.addAccept(e, int32(kind), taEmit)
    of tsRule:
      let s = b.newState()
      b.eps(0, s)
      for a in g.rules[t.rule].alts:
        let start = b.newState()
        b.eps(s, start)
        var k = int32(kind)
        let act = a.action(v, k)
        b.addAccept(b.compile(a.body, start), k, act)
    of tsEof, tsImaginary:
      discard
  b.nfa
