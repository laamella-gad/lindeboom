## Helpers for lexer generator tests.

import std/strutils
import lindeboom/[grammar, lexgen]

proc build*(grammarSrc: string): (Vocabulary, LexerTables, Diagnostics) =
  var (g, d) = loadGrammar(grammarSrc, "test.ldb")
  doAssert not d.hasErrors, $d.items
  let v = buildVocabulary(g)
  let t = buildLexer(g, v, d)
  (v, t, d)

proc lex*(grammarSrc, input: string): seq[string] =
  ## Tokens of `input` as `NAME text`, without EOF; hidden tokens get a
  ## trailing `(hidden)`. A lexical error is the last entry, as
  ## `line:col: message`.
  let (v, t, _) = build(grammarSrc)
  var d = Diagnostics(filename: "input")
  for tok in tokenize[int](t, input, d):
    if tok.kind != 0:
      result.add v.tokens[tok.kind].name & " " & tok.text(input) &
        (if tok.hidden: " (hidden)" else: "")
  for x in d.items:
    result.add $x.pos.line & ":" & $x.pos.col & ": " & x.msg

proc lexOne*(grammarSrc, input: string): string =
  lex(grammarSrc, input).join(" | ")
