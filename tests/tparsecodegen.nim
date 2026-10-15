## Generated parsers must compile, also standalone, and agree with the
## interpreter.

import std/[assertions, os, strutils]
import lindeboom/[grammar, lexgen]
import ./codegenhelpers

let tmp = getTempDir() / "lindeboom_tparsecodegen"

let cases = [
  Case(grammarFile: root / "tests" / "grammars" / "features.ldb", inputs: @[
    "", "let a = 1 + (b - -2);", "list(); list(a, 1 + 2);", "type t?; type u;",
    "raw a 1 ( ; any + ; maybe x; maybe; ;", "let a = 1 # comment\n;",
    "let = 1;", "list(a,);", "raw ;", "type t", "let a = 1; $",
    "calc a - b - c * d ^ e ^ f;", "calc -a ^ b * c() - [d + e];", "calc a()();",
    "calc a + ;", "calc a ^;", "sum 1 + 2 + 3;", "sum 1 +;"]),
  Case(grammarFile: root / "examples" / "calc" / "calc.ldb", inputs: @[
    "1 + 2 * (3 - 4)", "-1", "1 +", "(1"]),
  Case(grammarFile: root / "examples" / "json" / "json.ldb", inputs: @[
    "{\"a\": [1, true, null, {}], \"b\": \"\\u00e9\"}", "[]", "{\"a\" 1}", "[1,]"]),
  Case(grammarFile: root / "tests" / "grammars" / "ambiguous.ldb", inputs: @[
    "alt a b; alt a 1; alt a;", "alt a 1 2;", "alt;", "loop a, b, c; loop a;", "loop a, ;",
    "plus a . b . c; plus a;", "opt a = b; opt b;", "opt a =;",
    "ix a[b]; ix a[b:c][d]; ix a[b[c]:d];", "ix a[b:];", "ix a[b c];"]),
  Case(grammarFile: root / "examples" / "minipy" / "minipy.ldb", inputs: @[
    "x = f(1); g(x);\n", "return\n", "x = -a ** 2 + b[1] * c(d, e)\n", "x = \n",
    "f(1)(2) = 3\n", "pass; pass\n",
    "def f(n):\n    if n < 2:\n        return 1\n    elif n:\n        pass\n    else: return [\n" &
      "  n\n]\n\nwhile x: x = x - 1\n", "if x:\n    y\n  z\n", "if x:\ny\n"])]

block parsecodegen_matches_interpreter:
  for c in cases:
    let dir = tmp / c.grammarFile.splitFile.name
    let a = generate(c, dir, standalone = false)
    let got = runDriver(compile(dir, standalone = false), dir, c.inputs)
    var (g, d) = loadGrammar(readFile(c.grammarFile), c.grammarFile)
    let t = buildLexer(g, a.v, d)
    for i, input in c.inputs:
      let expected = interpreted(a, t, input)
      doAssert got[i] == expected, c.grammarFile & " " & input.escape & ":\n" & got[i] &
        "\nexpected:\n" & expected

block parsecodegen_standalone:
  let c = cases[2]
  let dir = tmp / "standalone"
  discard generate(c, dir, standalone = true)
  let got = runDriver(compile(dir, standalone = true), dir, @["[1]"])
  doAssert got == @["json\n└── array\n    ├── '['\n    ├── elements: number\n" &
    "    │   └── NUMBER \"1\"\n    └── ']'\n"], $got

removeDir(tmp)
