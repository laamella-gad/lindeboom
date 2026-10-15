## Grammar analysis for LL(1) parsing: nullable, FIRST and FOLLOW sets,
## left recursion, conflicts, and the node kinds and labels of the tree.
##
## Every rule can be a start rule, so every rule can be followed by EOF.

import std/[algorithm, hashes, packedsets, sets, tables]
import ../runtime/diagnostics, ../grammar/[ast, idents, vocabulary]

type
  TokenSet* = PackedSet[int]

  Analysis* = object
    g*: Grammar
    v*: Vocabulary
    ruleIndex*: Table[string, int]       ## parser rule name -> index in `g.rules`
    parserRules*: seq[int]               ## indices of the parser rules
    ruleIdents*: seq[string]             ## per rule: `IfStmt` for `ifStmt`
    nullable: Table[GExpr, bool]
    first: Table[GExpr, TokenSet]
    follow: Table[GExpr, TokenSet]
    visible: TokenSet                    ## tokens the parser can see, except EOF
    ruleNullable: seq[bool]
    ruleFirst, ruleFollow: seq[TokenSet]
    kinds*: seq[string]                  ## node kind names; 0 is "token"
    kindIdents*: seq[string]             ## `nkToken`, `nkIf`, ...
    altKinds*: seq[seq[int]]             ## per rule and alternative: node kind
    labels*: seq[string]                 ## element labels; 0 is ""
    labelIdents*: seq[string]            ## `lbNone`, `lbCond`, ...
    labelIsList*: seq[bool]              ## can label several sons of a node
    labelIndex*: Table[string, int]

const reservedLabels = ["kind", "label", "tok", "sons", "len", "text", "pos",
  "items", "treeRepr"]

func hash(e: GExpr): Hash = hash(cast[pointer](e))

func visibleTokens(g: Grammar, v: Vocabulary): TokenSet =
  ## Every token kind except EOF and those that are always skipped or hidden.
  for k, t in v.tokens:
    if t.source in {tsLiteral, tsImaginary}: result.incl k
  for r in g.rules:
    if r.kind == rkLexer and not r.isFragment:
      for alt in r.alts:
        var kind = v.byName[r.name]
        var emit = true
        for cmd in alt.commands:
          case cmd.kind
          of lcSkip, lcChannel: emit = false
          of lcType: kind = v.byName[cmd.arg]
        if emit: result.incl kind

func tokenKind*(a: Analysis, e: GExpr): int =
  ## Kind of a literal or token reference.
  if e.kind == ekLiteral: a.v.byLiteral[e.text]
  elif e.name == "EOF": 0
  else: a.v.byName[e.name]

func isSingleToken(e: GExpr): bool =
  case e.kind
  of ekLiteral, ekTokenRef: true
  of ekSeq: e.items.len == 1 and e.items[0].label.len == 0 and e.items[0].isSingleToken
  else: false

func isTokenSet*(e: GExpr): bool =
  ## Matches one token out of a set: `.`, `~x` and `(A | B)`.
  case e.kind
  of ekWildcard, ekNot: true
  of ekAlt:
    for x in e.items:
      if x.label.len > 0 or not x.isSingleToken: return false
    true
  else: false

func tokens*(a: Analysis, e: GExpr): TokenSet =
  ## The tokens matched by a single token or token set.
  case e.kind
  of ekLiteral, ekTokenRef: result.incl a.tokenKind(e)
  of ekSeq, ekAlt:
    for x in e.items: result.incl a.tokens(x)
  of ekWildcard: result = a.visible
  of ekNot:
    result = a.visible
    result.excl a.tokens(e.inner)
  else: raiseAssert "not a token set: " & $e.kind

# ---- nullable and FIRST ----

proc computeNullable(a: var Analysis, e: GExpr): bool =
  ## Stores the result for `e` and its sub-expressions.
  case e.kind
  of ekSeq:
    result = true
    for x in e.items:
      if not a.computeNullable(x): result = false
  of ekAlt:
    result = false
    for x in e.items:
      if a.computeNullable(x): result = true
  of ekOpt, ekStar:
    discard a.computeNullable(e.inner)
    result = true
  of ekPlus: result = a.computeNullable(e.inner)
  of ekRuleRef: result = a.ruleNullable[a.ruleIndex[e.name]]
  else: result = false
  a.nullable[e] = result

proc computeFirst(a: var Analysis, e: GExpr): TokenSet =
  ## Stores the result for `e` and its sub-expressions. Needs `nullable`.
  if e.isTokenSet:
    result = a.tokens(e)
  else:
    case e.kind
    of ekSeq:
      var open = true
      for x in e.items:
        let f = a.computeFirst(x)
        if open: result.incl f
        open = open and a.nullable[x]
    of ekAlt:
      for x in e.items: result.incl a.computeFirst(x)
    of ekOpt, ekStar, ekPlus: result = a.computeFirst(e.inner)
    of ekRuleRef: result = a.ruleFirst[a.ruleIndex[e.name]]
    of ekLiteral, ekTokenRef: result = a.tokens(e)
    else: raiseAssert "not a parser element: " & $e.kind
  a.first[e] = result

proc computeFirstSets(a: var Analysis) =
  ## Fixpoint over the rules.
  var changed = true
  while changed:
    changed = false
    for i in a.parserRules:
      var n = false
      for alt in a.g.rules[i].alts:
        if a.computeNullable(alt.body): n = true
      if n != a.ruleNullable[i]:
        a.ruleNullable[i] = n
        changed = true
  changed = true
  while changed:
    changed = false
    for i in a.parserRules:
      var f: TokenSet
      for alt in a.g.rules[i].alts: f.incl a.computeFirst(alt.body)
      if f != a.ruleFirst[i]:
        a.ruleFirst[i] = f
        changed = true

# ---- FOLLOW ----

proc computeFollow(a: var Analysis, e: GExpr, follow: TokenSet, changed: var bool) =
  a.follow[e] = follow
  if not e.isTokenSet:
    case e.kind
    of ekSeq:
      var f = follow
      for i in countdown(e.items.high, 0):
        let x = e.items[i]
        a.computeFollow(x, f, changed)
        if a.nullable[x]: f.incl a.first[x]
        else: f = a.first[x]
    of ekAlt:
      for x in e.items: a.computeFollow(x, follow, changed)
    of ekOpt:
      a.computeFollow(e.inner, follow, changed)
    of ekStar, ekPlus:
      var f = follow
      f.incl a.first[e.inner]
      a.computeFollow(e.inner, f, changed)
    of ekRuleRef:
      let r = a.ruleIndex[e.name]
      if not (follow <= a.ruleFollow[r]):
        a.ruleFollow[r].incl follow
        changed = true
    else:
      discard

proc computeFollowSets(a: var Analysis) =
  for i in a.parserRules: a.ruleFollow[i].incl 0
  var changed = true
  while changed:
    changed = false
    for i in a.parserRules:
      for alt in a.g.rules[i].alts:
        a.computeFollow(alt.body, a.ruleFollow[i], changed)

func predict*(a: Analysis, e: GExpr): TokenSet =
  ## Tokens that select `e` at a decision: its FIRST set, plus its FOLLOW set
  ## if it can match empty input.
  result = a.first[e]
  if a.nullable[e]: result.incl a.follow[e]

func first*(a: Analysis, e: GExpr): TokenSet = a.first[e]

func sortedKinds*(s: TokenSet): seq[int] =
  for k in s: result.add k
  result.sort()

# ---- left recursion ----

proc leftRefs(a: Analysis, e: GExpr, refs: var seq[int]) =
  ## Rules that `e` can call before consuming a token.
  case e.kind
  of ekSeq:
    var i = 0
    while i < e.items.len:
      a.leftRefs(e.items[i], refs)
      i = if a.nullable[e.items[i]]: i + 1 else: e.items.len
  of ekAlt:
    for x in e.items: a.leftRefs(x, refs)
  of ekOpt, ekStar, ekPlus:
    a.leftRefs(e.inner, refs)
  of ekRuleRef:
    refs.add a.ruleIndex[e.name]
  else:
    discard

func leftCycle(a: Analysis, calls: seq[seq[int]], start: int): seq[int] =
  ## Shortest path of left calls from `start` back to itself, empty if none.
  var parent = newSeq[int](a.g.rules.len)
  for x in parent.mitems: x = -1
  var queue = @[start]
  var found = false
  var qi = 0
  while qi < queue.len and not found:
    let r = queue[qi]
    inc qi
    for c in calls[r]:
      if c == start and not found:
        found = true
        result = @[start]
        var x = r
        while x != start:
          result.add x
          x = parent[x]
        result.add start
        result.reverse()
      elif c != start and parent[c] < 0:
        parent[c] = r
        queue.add c

proc checkLeftRecursion(a: Analysis, d: var Diagnostics): HashSet[int] =
  ## Reports left-recursive rules and returns them.
  var calls = newSeq[seq[int]](a.g.rules.len)
  for i in a.parserRules:
    for alt in a.g.rules[i].alts: a.leftRefs(alt.body, calls[i])
  for i in a.parserRules:
    let cycle = a.leftCycle(calls, i)
    if cycle.len > 0:
      result.incl i
      var path = ""
      for k, r in cycle:
        if k > 0: path.add " -> "
        path.add a.g.rules[r].name
      d.error(a.g.rules[i].pos, "rule '" & a.g.rules[i].name & "' is left-recursive: " & path)

# ---- conflicts ----

func tokenList(a: Analysis, s: TokenSet): string =
  ## `ID, INT and '('`
  let kinds = s.sortedKinds
  for i, k in kinds:
    if i > 0: result.add(if i == kinds.high: " and " else: ", ")
    result.add a.v.tokens[k].name

proc checkAlternatives(a: Analysis, rule: string, alts: seq[GExpr], what: string,
    d: var Diagnostics) =
  for j in 1 .. alts.high:
    var i = 0
    while i < j:
      let common = a.predict(alts[i]) * a.predict(alts[j])
      if common.len > 0:
        d.error(alts[j].pos, "rule '" & rule &
          "' is not LL(1): alternatives " & $(i + 1) & " and " & $(j + 1) & what &
          " can both start with " & a.tokenList(common))
        i = j
      else:
        inc i

proc checkConflicts(a: Analysis, r: Rule, d: var Diagnostics) =
  if r.alts.len > 1:
    var bodies: seq[GExpr]
    for alt in r.alts: bodies.add alt.body
    a.checkAlternatives(r.name, bodies, "", d)
  for alt in r.alts:
    for e in alt.body.walk:
      if e.isTokenSet:
        discard
      elif e.kind == ekAlt:
        a.checkAlternatives(r.name, e.items, " of this block", d)
      elif e.kind in {ekOpt, ekStar, ekPlus}:
        let common = a.first[e.inner] * a.follow[e]
        if common.len > 0:
          let what = if e.kind == ekOpt: "the optional element" else: "another iteration of the loop"
          d.error(e.pos, "rule '" & r.name & "' is not LL(1): " & a.tokenList(common) &
            (if common.len == 1: " can" else: " can each") & " start " & what &
            " or follow it")

# ---- node kinds and labels ----

func countLabels(a: Analysis, e: GExpr, inherited: string,
    counts: var Table[string, int]) =
  ## Adds to `counts` how many sons of one node `e` can add per label, where
  ## 2 stands for "more than one".
  let label = if e.label.len > 0: e.label else: inherited
  if e.isTokenSet or e.kind in {ekRuleRef, ekLiteral, ekTokenRef}:
    if label.len > 0: counts[label] = min(counts.getOrDefault(label) + 1, 2)
  else:
    case e.kind
    of ekSeq:
      for x in e.items: a.countLabels(x, label, counts)
    of ekAlt:
      var most: Table[string, int]
      for x in e.items:
        var c: Table[string, int]
        a.countLabels(x, label, c)
        for k, n in c: most[k] = max(most.getOrDefault(k), n)
      for k, n in most: counts[k] = min(counts.getOrDefault(k) + n, 2)
    of ekOpt:
      a.countLabels(e.inner, label, counts)
    of ekStar, ekPlus:
      var c: Table[string, int]
      a.countLabels(e.inner, label, c)
      for k in c.keys: counts[k] = 2
    else:
      discard

proc assignNames(a: var Analysis, d: var Diagnostics) =
  var kindIndex: Table[string, int]
  var kindUsed, ruleUsed, labelUsed: HashSet[string]
  a.kinds = @["token"]
  a.kindIdents = @[uniqueIdent("nkToken", kindUsed)]
  a.labels = @[""]
  a.labelIdents = @[uniqueIdent("lbNone", labelUsed)]
  a.labelIsList = @[false]
  a.altKinds.setLen a.g.rules.len
  a.ruleIdents.setLen a.g.rules.len
  for i in a.parserRules:
    let r = a.g.rules[i]
    a.ruleIdents[i] = uniqueIdent(capitalized(r.name), ruleUsed)
    for alt in r.alts:
      let name = if alt.label.len > 0: alt.label else: r.name
      if name notin kindIndex:
        kindIndex[name] = a.kinds.len
        a.kinds.add name
        a.kindIdents.add uniqueIdent("nk" & capitalized(name), kindUsed)
      a.altKinds[i].add kindIndex[name]
      for e in alt.body.walk:
        if e.label.len > 0 and e.label notin a.labelIndex:
          if e.label in reservedLabels:
            d.error(e.pos, "label '" & e.label &
              "' clashes with the parse tree API; choose another name")
          a.labelIndex[e.label] = a.labels.len
          a.labels.add e.label
          a.labelIdents.add uniqueIdent("lb" & capitalized(e.label), labelUsed)
          a.labelIsList.add false
      var counts: Table[string, int]
      a.countLabels(alt.body, "", counts)
      for label, n in counts:
        if n > 1: a.labelIsList[a.labelIndex[label]] = true

proc analyze*(g: Grammar, v: Vocabulary, d: var Diagnostics): Analysis =
  ## Analysis of `g`, which must have passed `checkGrammar` without errors.
  ## Reports left recursion, LL(1) conflicts and label problems.
  result = Analysis(g: g, v: v, visible: visibleTokens(g, v))
  for i, r in g.rules:
    if r.kind == rkParser:
      result.ruleIndex[r.name] = i
      result.parserRules.add i
  result.ruleNullable.setLen g.rules.len
  result.ruleFirst.setLen g.rules.len
  result.ruleFollow.setLen g.rules.len
  result.computeFirstSets()
  result.computeFollowSets()
  result.assignNames(d)
  let leftRecursive = result.checkLeftRecursion(d)
  for i in result.parserRules:
    if i notin leftRecursive: result.checkConflicts(g.rules[i], d)
