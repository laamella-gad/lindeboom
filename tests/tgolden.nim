## The generated modules checked in under `examples/` and the front end's own
## `ldb_lexer.nim` and `ldb_parser.nim` are golden files: they must equal what
## the generator produces now. After a deliberate change to the generated
## code, regenerate them with `lindeboom gen <grammar>`. For the front end,
## generate twice: the second run uses the front end the first one made.
##
## Also runs the example programs built on them.

import std/[assertions, os, osproc]
import lindeboom/[grammar, lexgen, parsegen]

let root = currentSourcePath().parentDir.parentDir
let tmp = getTempDir() / "lindeboom_tgolden"
createDir(tmp)

proc checkGolden(grammarFile: string) =
  var (g, d) = loadGrammar(readFile(grammarFile), grammarFile)
  let v = buildVocabulary(g)
  let t = buildLexer(g, v, d)
  let a = analyze(g, v, d)
  doAssert not d.hasErrors, $d.items
  let name = grammarFile.extractFilename
  let base = grammarFile.parentDir / moduleBase(g)
  let hint = ": out of date, run `lindeboom gen " & grammarFile.relativePath(root) & "`"
  doAssert readFile(base & "_lexer.nim") == genLexerModule(v, t, name),
    base & "_lexer.nim" & hint
  doAssert readFile(base & "_parser.nim") == genParserModule(a, name),
    base & "_parser.nim" & hint

proc build(source: string): string =
  result = tmp / source.splitFile.name
  let (output, code) = execCmdEx("nim c --hints:off --path:" & quoteShell(root / "src") &
    " -o:" & quoteShell(result) & " " & quoteShell(source))
  doAssert code == 0, output

block golden_calc:
  checkGolden(root / "examples" / "calc" / "calc.ldb")

block golden_json:
  checkGolden(root / "examples" / "json" / "json.ldb")

block golden_front_end:
  # the front end parses its own grammar and generates itself
  checkGolden(root / "src" / "lindeboom" / "grammar" / "ldb.ldb")

block example_calc:
  let exe = build(root / "examples" / "calc" / "calc.nim")
  doAssert execCmdEx(exe & " '1 + 2 * (3 - 4.5)'") == ("-2.0\n", 0)
  doAssert execCmdEx(exe & " '10 - 2 - 3'") == ("5.0\n", 0)
  doAssert execCmdEx(exe & " '2 * -3 / 4'") == ("-1.5\n", 0)
  doAssert execCmdEx(exe & " '1 +'") ==
    ("expression:1:4: error: expected '-', '(' or NUMBER but found end of input\n", 1)

block example_json:
  let exe = build(root / "examples" / "json" / "pretty.nim")
  let input = tmp / "in.json"
  writeFile(input, """{"a": [1, -2.5e3, true, null, {}], "bé😀": "x\ny\t\"", "c": []}""")
  let (output, code) = execCmdEx(quoteShell(exe) & " " & quoteShell(input))
  doAssert code == 0, output
  doAssert output == """
{
  "a": [
    1,
    -2.5e3,
    true,
    null,
    {}
  ],
  "bé😀": "x\ny\t\"",
  "c": []
}
""", output
  writeFile(input, "[1, 2,]")
  let (errOutput, errCode) = execCmdEx(quoteShell(exe) & " " & quoteShell(input))
  doAssert errCode == 1
  doAssert errOutput == input & ":1:7: error: expected '{', '[', 'true', 'false', " &
    "'null', STRING or NUMBER but found ']'\n", errOutput

removeDir(tmp)
