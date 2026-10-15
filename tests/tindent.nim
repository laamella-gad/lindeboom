## The indentation filter. Results with `tabs = strict` are those of
## CPython 3.12's `tokenize` for the same input.

import std/[assertions, strutils]
import lindeboom/[grammar, lexgen]

proc grammarWith(tabs: string, tabWidth = 8): string = """
grammar Ind;
options { tabWidth = $2; }
tokens { INDENT, DEDENT }
indentation {
  newline = NL; indent = INDENT; dedent = DEDENT;
  brackets = '(' ')', '[' ']', '{' '}';
  tabs = $1;
}
f : (ID | INT | '(' | ')' | '[' | ']' | '{' | '}' | ':' | ',' | '=' | '+' | NL | INDENT | DEDENT)* EOF ;
ID      : [a-z]+ ;
INT     : [0-9]+ ;
NL      : '\r'? '\n' ;
WS      : [ \t]+ -> skip ;
COMMENT : '#' ~[\r\n]* -> skip ;
CONT    : '\\' '\r'? '\n' -> skip ;
""" % [tabs, $tabWidth]

proc filtered(grammarSrc, input: string): string =
  ## The tokens of `input` as CPython's tokenize names them, or the error.
  var (g, d) = loadGrammar(grammarSrc, "test.ldb")
  let v = buildVocabulary(g)
  let t = buildLexer(g, v, d)
  doAssert not d.hasErrors, $d.items
  var di = Diagnostics(filename: "input")
  var names: seq[string]
  for tok in tokenize[int](t, input, di):
    let name = v.tokens[tok.kind].name
    case name
    of "NL": names.add "NEWLINE"
    of "INDENT", "DEDENT", "EOF": names.add name
    else: names.add tok.text(input)
  for x in di.items: return "ERR " & $x.pos.line & ":" & $x.pos.col & ": " & x.msg
  names.join(" ")

proc expect(tabs, input, expected: string, tabWidth = 8) =
  let got = filtered(grammarWith(tabs, tabWidth), input)
  doAssert got == expected, input.escape & " (tabs = " & tabs & "):\n" & got &
    "\nexpected:\n" & expected

block indent_matches_cpython:
  const cases = [
    ("", "EOF"),
    ("a\n", "a NEWLINE EOF"),
    ("a", "a NEWLINE EOF"),
    ("if x:\n  y\nz\n", "if x : NEWLINE INDENT y NEWLINE DEDENT z NEWLINE EOF"),
    ("a:\n b:\n  c\nd\n",
      "a : NEWLINE INDENT b : NEWLINE INDENT c NEWLINE DEDENT DEDENT d NEWLINE EOF"),
    ("a:\n  b\n  c\n    d\n  e\nf\n", "a : NEWLINE INDENT b NEWLINE c NEWLINE INDENT d " &
      "NEWLINE DEDENT e NEWLINE DEDENT f NEWLINE EOF"),
    # blank and comment-only lines
    ("a:\n\n   # c\n b\n\n# x\nc\n", "a : NEWLINE INDENT b NEWLINE DEDENT c NEWLINE EOF"),
    ("\n\n  # c\na\n", "a NEWLINE EOF"),
    # line joining inside brackets and after `\`
    ("f(a,\n    b)\nc\n", "f ( a , b ) NEWLINE c NEWLINE EOF"),
    ("x = [\n1,\n  2]\n", "x = [ 1 , 2 ] NEWLINE EOF"),
    ("a = {(\n)}\n  \nb\n", "a = { ( ) } NEWLINE b NEWLINE EOF"),
    ("a = 1 + \\\n    2\nb\n", "a = 1 + 2 NEWLINE b NEWLINE EOF"),
    ("x\n)\n  y\n", "x NEWLINE ) NEWLINE INDENT y NEWLINE DEDENT EOF"),
    # end of file
    ("a:\n  b:\n    c", "a : NEWLINE INDENT b : NEWLINE INDENT c NEWLINE DEDENT DEDENT EOF"),
    ("a:\n  b:\n    c\n\n\n",
      "a : NEWLINE INDENT b : NEWLINE INDENT c NEWLINE DEDENT DEDENT EOF"),
    ("a:\r\n  b\r\nc\r\n", "a : NEWLINE INDENT b NEWLINE DEDENT c NEWLINE EOF"),
    ("  a\n", "INDENT a NEWLINE DEDENT EOF"),
    # errors
    ("a:\n    b\n  c\n", "ERR 3:3: unindent does not match any outer indentation level"),
    # tabs
    ("a:\n\tb\n\tc\n", "a : NEWLINE INDENT b NEWLINE c NEWLINE DEDENT EOF"),
    ("a:\n\t b\n\t c\nd\n", "a : NEWLINE INDENT b NEWLINE c NEWLINE DEDENT d NEWLINE EOF"),
    ("a:\n\tb\n        c\n", "ERR 3:9: inconsistent use of tabs and spaces in indentation"),
    ("a:\n  \tb\n\tc\n", "ERR 3:2: inconsistent use of tabs and spaces in indentation")]
  for (input, expected) in cases: expect("strict", input, expected)

block indent_tab_modes:
  # a tab and eight spaces are the same with `expand`
  expect("expand", "a:\n\tb\n        c\n", "a : NEWLINE INDENT b NEWLINE c NEWLINE DEDENT EOF")
  expect("expand", "a:\n\tb\n    c\n", "ERR 3:5: unindent does not match any outer indentation level")
  expect("expand", "a:\n\tb\n    c\n", "a : NEWLINE INDENT b NEWLINE c NEWLINE DEDENT EOF",
    tabWidth = 4)
  # `strict` needs the line to be indented further whatever the tab width
  expect("strict", "a:\n        b\n\t c\n",
    "ERR 3:3: inconsistent use of tabs and spaces in indentation")
  expect("error", "a:\n  b\n", "a : NEWLINE INDENT b NEWLINE DEDENT EOF")
  expect("error", "a:\n\tb\n", "ERR 2:2: tab in indentation; this grammar indents with spaces only")
  # tabs elsewhere on the line are fine
  expect("error", "a\t:\n", "a : NEWLINE EOF")

block indent_hidden_tokens:
  # hidden comments pass through and leave comment-only lines blank
  let src = grammarWith("strict").replace("~[\\r\\n]* -> skip", "~[\\r\\n]* -> channel(HIDDEN)")
  doAssert "channel(HIDDEN)" in src
  let got = filtered(src, "a:\n  #c\n  b #d\n#e\n")
  doAssert got == "a : NEWLINE #c INDENT b #d NEWLINE #e DEDENT EOF", got

block indent_filter_goes_on_after_errors:
  var (g, d) = loadGrammar(grammarWith("strict"), "test.ldb")
  let v = buildVocabulary(g)
  let t = buildLexer(g, v, d)
  var di = Diagnostics(filename: "input")
  let input = "a:\n    b\n  c\nd:\n    e\n  f\n"
  var names: seq[string]
  for tok in tokenize[int](t, input, di):
    if v.tokens[tok.kind].name notin ["NL", "INDENT", "DEDENT", "EOF"]: names.add tok.text(input)
  doAssert names == @["a", ":", "b", "c", "d", ":", "e", "f"], $names
  doAssert di.items.len == 2, $di.items

block indent_errors_in_grammar:
  var (g, d) = loadGrammar(grammarWith("expand").replace("'{' '}'", "'<' '>'"), "test.ldb")
  discard buildLexer(g, buildVocabulary(g), d)
  doAssert "test.ldb:6:32: error: bracket '<' is not used in any parser rule" in $d.items, $d.items
