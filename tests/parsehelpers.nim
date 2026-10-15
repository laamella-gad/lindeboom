## Helpers for parser generator tests.

import std/[strutils, tables]
import lindeboom/[grammar, lexgen, parsegen]

proc analyzed*(grammarSrc: string): (Analysis, LexerTables, Diagnostics) =
  ## Analysis of a grammar that must load without errors; analysis problems
  ## are in the returned diagnostics.
  var (g, d) = loadGrammar(grammarSrc, "test.ldb")
  doAssert not d.hasErrors, $d.items
  let v = buildVocabulary(g)
  let t = buildLexer(g, v, d)
  let a = analyze(g, v, d)
  (a, t, d)

proc problems*(grammarSrc: string): seq[string] =
  ## Analysis diagnostics as `line:col: severity: message`.
  let (_, _, d) = analyzed(grammarSrc)
  for x in d:
    var m = $x
    m.removePrefix("test.ldb:")
    result.add m

proc tree*(grammarSrc, input: string, rule = ""): string =
  ## The parse tree of `input`, or the errors as `line:col: message` lines.
  let (a, t, d) = analyzed(grammarSrc)
  doAssert not d.hasErrors, $d.items
  var r = a.parserRules[0]
  if rule.len > 0: r = a.ruleIndex[rule]
  var di = Diagnostics(filename: "input")
  let n = a.interpret(tokenize[int](t, input, di), input, r, di)
  if di.hasErrors:
    var errors: seq[string]
    for x in di.items: errors.add $x.pos.line & ":" & $x.pos.col & ": " & x.msg
    result = errors.join("\n")
  else:
    result = n.treeRepr(a.treeNames)

proc recovered*(grammarSrc, input: string): string =
  ## The parse tree of `input` followed by its errors as `line:col: message`
  ## lines; the tree has error nodes where the parser recovered.
  let (a, t, d) = analyzed(grammarSrc)
  doAssert not d.hasErrors, $d.items
  var di = Diagnostics(filename: "input")
  let n = a.interpret(tokenize[int](t, input, di), input, a.parserRules[0], di)
  result = n.treeRepr(a.treeNames)
  for x in di.items: result.add $x.pos.line & ":" & $x.pos.col & ": " & x.msg & "\n"
