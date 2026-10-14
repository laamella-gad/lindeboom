## Semantic checks on a parsed grammar.

import std/[sets, strutils, tables, unicode]
import ../diagnostics, ./ast

type
  Checker = object
    g: Grammar
    rules: Table[string, int]       ## rule name -> index in g.rules
    imaginary: Table[string, int]   ## tokens {} name -> index in g.tokens

const knownOptions = ["tabWidth"]

func isFragmentRule(c: Checker, name: string): bool =
  name in c.rules and c.g.rules[c.rules[name]].isFragment

func isLexerRule(c: Checker, name: string): bool =
  name in c.rules and c.g.rules[c.rules[name]].kind == rkLexer

func isToken(c: Checker, name: string): bool =
  ## A token the parser can see: imaginary, or a non-fragment lexer rule.
  name in c.imaginary or (c.isLexerRule(name) and not c.isFragmentRule(name))

# ---- declarations ----

proc checkDeclarations(c: var Checker, d: var Diagnostics) =
  for i, t in c.g.tokens:
    if not t.name.isLexerName:
      d.error(t.pos, "token name '" & t.name & "' must start with an uppercase letter")
    elif t.name == "EOF":
      d.error(t.pos, "'EOF' is predefined")
    elif t.name in c.imaginary:
      d.error(t.pos, "duplicate token '" & t.name & "'")
    else:
      c.imaginary[t.name] = i
  for i, r in c.g.rules:
    if r.isFragment and r.kind == rkParser:
      d.error(r.pos, "fragment rule '" & r.name &
        "' must be a lexer rule (uppercase name)")
    if r.name == "EOF":
      d.error(r.pos, "'EOF' is predefined")
    elif r.name in c.rules:
      let first = c.g.rules[c.rules[r.name]].pos
      d.error(r.pos, "duplicate rule '" & r.name & "' (first defined at line " &
        $first.line & ")")
    elif r.name in c.imaginary:
      d.error(r.pos, "rule '" & r.name & "' conflicts with the token declared in 'tokens { }'")
    else:
      c.rules[r.name] = i
  if c.g.rules.len == 0:
    d.warning(c.g.pos, "grammar has no rules")

proc checkOptions(c: Checker, d: var Diagnostics) =
  var seen: HashSet[string]
  for o in c.g.options:
    if o.name in seen:
      d.error(o.pos, "duplicate option '" & o.name & "'")
    seen.incl o.name
    if o.name notin knownOptions:
      d.warning(o.pos, "unknown option '" & o.name & "'")
    elif o.name == "tabWidth":
      if not o.value.allCharsInSet(Digits) or o.value.len == 0 or
          o.value.parseInt == 0:
        d.error(o.pos, "option 'tabWidth' must be a positive integer")

# ---- references and placement ----

func isLexerNotOperand(e: GExpr): bool =
  case e.kind
  of ekCharSet, ekRange: true
  of ekLiteral: e.text.runeLen == 1
  of ekAlt:
    for x in e.items:
      if not x.isLexerNotOperand: return false
    true
  of ekSeq: e.items.len == 1 and e.items[0].isLexerNotOperand
  else: false

func isParserNotOperand(e: GExpr): bool =
  case e.kind
  of ekTokenRef, ekLiteral: true
  of ekAlt:
    for x in e.items:
      if not x.isParserNotOperand: return false
    true
  of ekSeq: e.items.len == 1 and e.items[0].isParserNotOperand
  else: false

proc checkParserExpr(c: Checker, r: Rule, e: GExpr, d: var Diagnostics) =
  case e.kind
  of ekRuleRef:
    if e.name notin c.rules:
      d.error(e.pos, "undefined rule '" & e.name & "'")
  of ekTokenRef:
    if e.name == "EOF" or e.name in c.imaginary:
      discard
    elif c.isFragmentRule(e.name):
      d.error(e.pos, "fragment '" & e.name & "' cannot be used in a parser rule")
    elif not c.isLexerRule(e.name):
      d.error(e.pos, "undefined token '" & e.name & "'")
  of ekCharSet:
    d.error(e.pos, "character sets are only allowed in lexer rules")
  of ekRange:
    d.error(e.pos, "character ranges are only allowed in lexer rules")
  of ekNot:
    if not e.inner.isParserNotOperand:
      d.error(e.pos, "'~' in parser rules applies only to tokens and sets of tokens")
  of ekOpt, ekStar, ekPlus:
    if not e.greedy:
      d.error(e.pos, "non-greedy operators are only allowed in lexer rules")
  else:
    discard

proc checkLexerExpr(c: Checker, r: Rule, e: GExpr, d: var Diagnostics) =
  if e.label.len > 0:
    d.error(e.pos, "element labels are not allowed in lexer rules")
  case e.kind
  of ekRuleRef:
    d.error(e.pos, "parser rule '" & e.name & "' cannot be used in lexer rule '" &
      r.name & "'")
  of ekTokenRef:
    if e.name == "EOF":
      d.error(e.pos, "'EOF' cannot be used in lexer rules")
    elif e.name in c.imaginary:
      d.error(e.pos, "token '" & e.name & "' has no lexer rule and cannot be used in lexer rule '" &
        r.name & "'")
    elif not c.isLexerRule(e.name):
      d.error(e.pos, "undefined lexer rule '" & e.name & "'")
  of ekNot:
    if not e.inner.isLexerNotOperand:
      d.error(e.pos, "'~' in lexer rules applies only to single characters, ranges and character sets")
  else:
    discard

proc checkLabels(r: Rule, d: var Diagnostics) =
  ## Alternative labels: all or none, no duplicates. Element labels: one kind
  ## (`=` or `+=`) per name.
  var labelled = 0
  var seen: HashSet[string]
  for a in r.alts:
    if a.label.len > 0:
      inc labelled
      if a.label in seen:
        d.error(a.labelPos, "duplicate alternative label '" & a.label & "' in rule '" &
          r.name & "'")
      seen.incl a.label
  if labelled > 0 and labelled < r.alts.len:
    for a in r.alts:
      if a.label.len == 0:
        d.error(a.pos, "rule '" & r.name &
          "' has labelled alternatives, so this alternative needs a label too")
  var kinds: Table[string, bool]
  for a in r.alts:
    for e in a.body.walk:
      if e.label.len > 0:
        if e.label in kinds and kinds[e.label] != e.labelIsList:
          d.error(e.pos, "label '" & e.label & "' is used with both '=' and '+='")
        kinds[e.label] = e.labelIsList

proc checkCommands(c: Checker, r: Rule, a: Alternative, d: var Diagnostics) =
  for cmd in a.commands:
    if r.isFragment:
      d.error(cmd.pos, "lexer commands are not allowed on fragment rules")
    case cmd.kind
    of lcSkip:
      discard
    of lcChannel:
      if cmd.arg != "HIDDEN":
        d.error(cmd.pos, "unknown channel '" & cmd.arg & "' (only HIDDEN is supported)")
    of lcType:
      if not c.isToken(cmd.arg):
        d.error(cmd.pos, "undefined token '" & cmd.arg & "' in 'type()'")

proc checkRules(c: Checker, d: var Diagnostics) =
  for r in c.g.rules:
    case r.kind
    of rkParser:
      checkLabels(r, d)
      for a in r.alts:
        if a.commands.len > 0:
          d.error(a.commands[0].pos, "lexer commands are only allowed in lexer rules")
        for e in a.body.walk: c.checkParserExpr(r, e, d)
    of rkLexer:
      for a in r.alts:
        if a.label.len > 0:
          d.error(a.labelPos, "alternative labels are not allowed in lexer rules")
        if a.hasAssoc:
          d.error(a.pos, "'<assoc>' is not allowed in lexer rules")
        c.checkCommands(r, a, d)
        for e in a.body.walk: c.checkLexerExpr(r, e, d)

# ---- empty matches ----

func nullable(e: GExpr, kind: RuleKind, nullRules: HashSet[string]): bool =
  case e.kind
  of ekSeq:
    for x in e.items:
      if not x.nullable(kind, nullRules): return false
    true
  of ekAlt:
    for x in e.items:
      if x.nullable(kind, nullRules): return true
    false
  of ekOpt, ekStar: true
  of ekPlus: e.inner.nullable(kind, nullRules)
  of ekRuleRef: e.name in nullRules
  of ekTokenRef:
    # tokens seen by the parser always consume input
    kind == rkLexer and e.name in nullRules
  of ekNot, ekLiteral, ekCharSet, ekRange, ekWildcard: false

proc nullableRules(g: Grammar): HashSet[string] =
  ## Fixpoint: rules that can match the empty string.
  var changed = true
  while changed:
    changed = false
    for r in g.rules:
      if r.name notin result:
        for a in r.alts:
          if r.name notin result and a.body.nullable(r.kind, result):
            result.incl r.name
            changed = true

proc checkEmpty(c: Checker, d: var Diagnostics) =
  let nullRules = nullableRules(c.g)
  for r in c.g.rules:
    if r.kind == rkLexer and not r.isFragment and r.name in nullRules:
      d.error(r.pos, "lexer rule '" & r.name & "' can match empty input")
    for a in r.alts:
      for e in a.body.walk:
        if e.kind in {ekStar, ekPlus} and e.inner.nullable(r.kind, nullRules):
          d.error(e.pos, "loop body can match empty input")

# ---- unused declarations ----

proc checkUnused(c: Checker, d: var Diagnostics) =
  var used: HashSet[string]
  var start = -1
  for i, r in c.g.rules:
    if start < 0 and r.kind == rkParser: start = i
    for a in r.alts:
      for e in a.body.walk:
        if e.kind in {ekRuleRef, ekTokenRef}: used.incl e.name
      for cmd in a.commands:
        if cmd.kind == lcType: used.incl cmd.arg
  if c.g.hasIndentation:
    used.incl c.g.indentation.indent.value
    used.incl c.g.indentation.dedent.value
  for r in c.g.rules:
    if r.isFragment and r.name notin used:
      d.warning(r.pos, "fragment '" & r.name & "' is never used")
  for t in c.g.tokens:
    if t.name in c.imaginary and t.name notin used:
      d.warning(t.pos, "token '" & t.name & "' is declared but never used")

  # parser rules reachable from the first parser rule
  if start >= 0:
    var reached = [c.g.rules[start].name].toHashSet
    var todo = @[start]
    while todo.len > 0:
      let r = c.g.rules[todo.pop()]
      for a in r.alts:
        for e in a.body.walk:
          if e.kind == ekRuleRef and e.name notin reached and e.name in c.rules:
            reached.incl e.name
            todo.add c.rules[e.name]
    for r in c.g.rules:
      if r.kind == rkParser and not r.isFragment and r.name notin reached:
        d.warning(r.pos, "rule '" & r.name & "' is not reachable from start rule '" &
          c.g.rules[start].name & "'")

# ---- indentation block ----

proc checkIndentation(c: Checker, d: var Diagnostics) =
  if c.g.hasIndentation:
    let ind = c.g.indentation
    for (key, s) in [("newline", ind.newline), ("indent", ind.indent),
        ("dedent", ind.dedent)]:
      if s.value.len == 0:
        d.error(ind.pos, "'indentation' block needs a '" & key & "' setting")
    if ind.newline.value.len > 0 and not
        (c.isLexerRule(ind.newline.value) and not c.isFragmentRule(ind.newline.value)):
      d.error(ind.newline.pos, "'newline' must name a lexer rule that is not a fragment, but '" &
        ind.newline.value & "' is not one")
    for (key, s) in [("indent", ind.indent), ("dedent", ind.dedent)]:
      if s.value.len > 0 and s.value notin c.imaginary:
        if c.isLexerRule(s.value):
          d.error(s.pos, "'" & key & "' token '" & s.value &
            "' must be declared in 'tokens { }', not as a lexer rule")
        else:
          d.error(s.pos, "'" & key & "' token '" & s.value &
            "' is not declared; add it to 'tokens { }'")
    if ind.indent.value.len > 0 and ind.indent.value == ind.dedent.value:
      d.error(ind.dedent.pos, "'indent' and 'dedent' must be different tokens")
    if ind.tabs.value.len > 0 and ind.tabs.value notin ["expand", "strict", "error"]:
      d.error(ind.tabs.pos, "'tabs' must be expand, strict or error")

proc checkGrammar*(g: Grammar, d: var Diagnostics) =
  ## Reports semantic errors and warnings for `g` to `d`.
  var c = Checker(g: g)
  c.checkDeclarations(d)
  c.checkOptions(d)
  c.checkRules(d)
  c.checkEmpty(d)
  c.checkUnused(d)
  c.checkIndentation(d)
