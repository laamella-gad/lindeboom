## Lexer generator: compiles a grammar's lexer rules to DFA tables.

import std/[sets, tables]
import ./runtime/[diagnostics, lexer], ./grammar/[ast, vocabulary],
  ./lexgen/[nfa, dfa, codegen]

export lexer, vocabulary, codegen

func quoted(t: TokenInfo): string =
  ## Literal names are quoted already.
  if t.source == tsLiteral: t.name else: "'" & t.name & "'"

proc buildLexer*(g: Grammar, v: Vocabulary, d: var Diagnostics): LexerTables =
  ## Tables for `g`, which must have passed `checkGrammar` without errors.
  ## Warns about tokens that can never be produced.
  let n = buildNfa(g, v)
  var o: Overlaps
  let m = buildDfa(n, o)
  for kind, t in v.tokens:
    if t.source in {tsLiteral, tsRule} and int32(kind) notin o.matched:
      let what = (if t.source == tsRule: "lexer rule " else: "literal ") & t.quoted
      if int32(kind) in o.shadowedBy:
        let by = v.tokens[o.shadowedBy[int32(kind)]]
        d.warning(t.pos, what & " never produces a token: its input is always matched by " &
          by.quoted & ", which takes priority")
      else:
        d.warning(t.pos, what & " never produces a token")
  result.classes = m.classes
  result.classCount = m.classCount
  result.next = m.next
  for a in m.accept:
    if a < 0:
      result.acceptKind.add -1
      result.acceptAction.add taEmit
    else:
      result.acceptKind.add n.accepts[a].kind
      result.acceptAction.add n.accepts[a].action
