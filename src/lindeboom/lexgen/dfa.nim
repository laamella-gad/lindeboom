## Subset construction and minimization.
##
## A DFA state is an ordered list of NFA threads, highest priority first.
## A thread remembers whether it went through a non-greedy decision. As in
## ANTLR, once a thread of some token reaches its accept state, the
## lower-priority threads of that token that went through a non-greedy
## decision are dropped: `'/*' .*? '*/'` stops at the first `*/`. Between
## tokens the longest match wins, then the lowest priority group.

import std/[deques, sets, tables]
import ./nfa

type
  Item = int32  ## NFA state * 2 + 1 if the thread went through a non-greedy decision

  Dfa* = object
    classes*: array[256, uint8]
    classCount*: int
    next*: seq[int32]    ## state * classCount + class -> state, -1 if none
    accept*: seq[int32]  ## per state: index into `Nfa.accepts`, -1 if none

  Overlaps* = object
    ## Which tokens win where, for warnings about tokens that never match.
    matched*: HashSet[int32]               ## groups that win in some state
    shadowedBy*: Table[int32, int32]       ## group -> a group that beat it

func state(it: Item): int32 = it shr 1
func flagged(it: Item): bool = (it and 1) == 1
func item(state: int32, flagged: bool): Item = state * 2 + int32(flagged)

proc byteClasses(n: Nfa): (array[256, uint8], seq[uint8]) =
  ## Bytes no edge tells apart share a class. Returns the class of each byte
  ## and one representative byte per class.
  var boundary: array[257, bool]
  for s in n.states:
    for e in s.edges:
      if not e.eps:
        boundary[e.lo] = true
        boundary[int(e.hi) + 1] = true
  var cls = 0
  for b in 0..255:
    if b > 0 and boundary[b]: inc cls
    result[0][b] = uint8(cls)
    if result[1].len == cls: result[1].add uint8(b)

proc visit(n: Nfa, it: Item, seen: var HashSet[Item], items: var seq[Item]) =
  if not seen.containsOrIncl(it):
    let s = n.states[it.state]
    var hasBytes = s.accept >= 0
    for e in s.edges:
      if not e.eps: hasBytes = true
    if hasBytes: items.add it
    for e in s.edges:
      if e.eps:
        n.visit(item(e.target, it.flagged or n.states[e.target].nonGreedy),
          seen, items)

proc closure(n: Nfa, seeds: seq[Item]): seq[Item] =
  ## Epsilon closure in priority order, with the non-greedy cut applied.
  var seen: HashSet[Item]
  var all: seq[Item]
  for it in seeds: n.visit(it, seen, all)
  var accepted: HashSet[int32]  # groups that reached an accept state
  for it in all:
    let s = n.states[it.state]
    if not (it.flagged and s.group in accepted):
      result.add it
      if s.accept >= 0: accepted.incl s.group

func firstAccept(n: Nfa, items: seq[Item]): int32 =
  result = -1
  for it in items:
    if result < 0 and n.states[it.state].accept >= 0:
      result = n.states[it.state].accept

proc subsetConstruction(n: Nfa, o: var Overlaps): Dfa =
  let (classes, reps) = byteClasses(n)
  result.classes = classes
  result.classCount = reps.len
  var ids: Table[seq[Item], int32]
  var sets: seq[seq[Item]]
  let start = n.closure(@[item(0, false)])
  ids[start] = 0
  sets.add start
  var i = 0
  while i < sets.len:
    let cur = sets[i]
    let acc = n.firstAccept(cur)
    result.accept.add acc
    if acc >= 0:
      let winner = n.accepts[acc].group
      o.matched.incl winner
      for it in cur:
        let a = n.states[it.state].accept
        if a >= 0 and n.accepts[a].group != winner:
          discard o.shadowedBy.hasKeyOrPut(n.accepts[a].group, winner)
    for b in reps:
      var seeds: seq[Item]
      for it in cur:
        for e in n.states[it.state].edges:
          if not e.eps and b in e.lo..e.hi:
            seeds.add item(e.target, it.flagged or n.states[e.target].nonGreedy)
      var target = -1'i32
      if seeds.len > 0:
        let s = n.closure(seeds)
        target = ids.getOrDefault(s, -1)
        if target < 0:
          target = int32(sets.len)
          ids[s] = target
          sets.add s
      result.next.add target
    inc i

proc prune(d: var Dfa) =
  ## Removes transitions into states from which no accept state is reachable.
  let n = d.accept.len
  var preds = newSeq[seq[int32]](n)
  for s in 0 ..< n:
    for c in 0 ..< d.classCount:
      let t = d.next[s * d.classCount + c]
      if t >= 0: preds[t].add int32(s)
  var live = newSeq[bool](n)
  var todo: seq[int32]
  for s in 0 ..< n:
    if d.accept[s] >= 0:
      live[s] = true
      todo.add int32(s)
  while todo.len > 0:
    for p in preds[todo.pop()]:
      if not live[p]:
        live[p] = true
        todo.add p
  for k, t in d.next:
    if t >= 0 and not live[t]: d.next[k] = -1

proc minimize(d: Dfa, key: proc (accept: int32): int32): Dfa =
  ## Moore's partition refinement. `key` tells which accepts behave the same.
  ## States are renumbered breadth-first from the start state.
  let n = d.accept.len
  var blocks = newSeq[int32](n)
  var count = 0
  block:
    var initial: Table[int32, int32]
    for s in 0 ..< n:
      let k = key(d.accept[s])
      if k notin initial: initial[k] = int32(initial.len)
      blocks[s] = initial[k]
    count = initial.len
  var stable = false
  while not stable:
    var sigs: Table[seq[int32], int32]
    var newBlocks = newSeq[int32](n)
    for s in 0 ..< n:
      var sig = @[blocks[s]]
      for c in 0 ..< d.classCount:
        let t = d.next[s * d.classCount + c]
        sig.add(if t >= 0: blocks[t] else: -1)
      if sig notin sigs: sigs[sig] = int32(sigs.len)
      newBlocks[s] = sigs[sig]
    stable = sigs.len == count
    count = sigs.len
    blocks = newBlocks

  # one representative per block, numbered in breadth-first order
  var rep = newSeq[int32](count)
  for s in countdown(n - 1, 0): rep[blocks[s]] = int32(s)
  var order = newSeq[int32](count)
  for b in order.mitems: b = -1
  var queue = [blocks[0]].toDeque
  order[blocks[0]] = 0
  var visited = 1
  result.classes = d.classes
  result.classCount = d.classCount
  while queue.len > 0:
    let s = rep[queue.popFirst()]
    result.accept.add d.accept[s]
    for c in 0 ..< d.classCount:
      let t = d.next[s * d.classCount + c]
      if t < 0:
        result.next.add -1
      else:
        let b = blocks[t]
        if order[b] < 0:
          order[b] = int32(visited)
          inc visited
          queue.addLast b
        result.next.add order[b]

proc buildDfa*(n: Nfa, o: var Overlaps): Dfa =
  ## Minimal DFA for `n`.
  var d = n.subsetConstruction(o)
  d.prune()
  d.minimize(proc (a: int32): int32 =
    if a < 0: -1'i32
    else: n.accepts[a].kind * 3 + int32(ord(n.accepts[a].action)))
