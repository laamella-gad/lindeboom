## Generated parsers must compile, also standalone, and agree with the
## interpreter.

import std/[assertions, os, osproc, strutils]
import lindeboom/[grammar, lexgen, parsegen]

let root = currentSourcePath().parentDir.parentDir
let tmp = getTempDir() / "lindeboom_tparsecodegen"

type Case = object
  grammarFile: string
  inputs: seq[string]

let cases = [
  Case(grammarFile: root / "tests" / "grammars" / "features.ldb", inputs: @[
    "", "let a = 1 + (b - -2);", "list(); list(a, 1 + 2);", "type t?; type u;",
    "raw a 1 ( ; any + ; maybe x; maybe; ;", "let a = 1 # comment\n;",
    "let = 1;", "list(a,);", "raw ;", "type t", "let a = 1; $"]),
  Case(grammarFile: root / "examples" / "calc" / "calc.ldb", inputs: @[
    "1 + 2 * (3 - 4)", "-1", "1 +", "(1"]),
  Case(grammarFile: root / "examples" / "json" / "json.ldb", inputs: @[
    "{\"a\": [1, true, null, {}], \"b\": \"\\u00e9\"}", "[]", "{\"a\" 1}", "[1,]"])]

proc interpreted(a: Analysis, t: LexerTables, input: string): string =
  ## What the driver prints for `input`.
  var d = Diagnostics(filename: "input")
  let n = a.interpret(tokenize[int](t, input, d), input, a.parserRules[0], d)
  for x in d: result.add $x & "\n"
  if n != nil: result.add n.treeRepr(a.treeNames)

proc generate(c: Case, dir: string, standalone: bool): Analysis =
  ## Writes the lexer, parser and a driver to `dir`.
  var (g, d) = loadGrammar(readFile(c.grammarFile), c.grammarFile)
  let v = buildVocabulary(g)
  let t = buildLexer(g, v, d)
  result = analyze(g, v, d)
  doAssert not d.hasErrors, $d.items
  createDir(dir)
  let base = moduleBase(g)
  var lexerImport = "lindeboom/runtime/lexer"
  var parserImport = "lindeboom/runtime/parser"
  if standalone:
    createDir(dir / "lindeboom_runtime")
    for (name, content) in runtimeFiles:
      writeFile(dir / "lindeboom_runtime" / name, content)
    lexerImport = "./lindeboom_runtime/lexer"
    parserImport = "./lindeboom_runtime/parser"
  writeFile(dir / base & "_lexer.nim", genLexerModule(v, t, "x.ldb", lexerImport))
  writeFile(dir / base & "_parser.nim", genParserModule(result, "x.ldb", parserImport))
  writeFile(dir / "driver.nim", """
import std/os
import ./$1_parser

for f in commandLineParams():
  let res = parse$2(readFile(f))
  for d in res.diagnostics: echo d
  if res.tree != nil: stdout.write res.tree.treeRepr
  stdout.write "----\n"
""" % [base, result.ruleIdents[result.parserRules[0]]])

proc compile(dir: string, standalone: bool): string =
  result = dir / "driver"
  let path = if standalone: "" else: " --path:" & quoteShell(root / "src")
  let (output, code) = execCmdEx("nim c --hints:off --warningAsError:UnusedImport" & path &
    " -o:" & quoteShell(result) & " " & quoteShell(dir / "driver.nim"))
  doAssert code == 0, output

proc runDriver(exe, dir: string, inputs: seq[string]): seq[string] =
  var files: seq[string]
  for i, input in inputs:
    files.add dir / "input" & $i
    writeFile(files[^1], input)
  var cmd = quoteShell(exe)
  for f in files: cmd.add " " & quoteShell(f)
  let (output, code) = execCmdEx(cmd)
  doAssert code == 0, output
  for i, s in output.split("----\n")[0 ..< inputs.len]:
    result.add s.replace(files[i], "input")

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
