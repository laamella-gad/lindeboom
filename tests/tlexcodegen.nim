## The generated lexer module must compile and agree with the interpreter.

import std/[assertions, os, osproc, strutils]
import lindeboom/[grammar, lexgen]

let root = currentSourcePath().parentDir.parentDir
let dir = getTempDir() / "lindeboom_tlexcodegen"
createDir(dir)

let grammarFile = root / "examples" / "minipy" / "minipy.ldb"
let inputFile = root / "examples" / "minipy" / "fact.py"
var (g, d) = loadGrammar(readFile(grammarFile), grammarFile)
let v = buildVocabulary(g)
let tables = buildLexer(g, v, d)
doAssert not d.hasErrors
writeFile(dir / "minipy_lexer.nim", genLexerModule(v, tables, "minipy.ldb"))
writeFile(dir / "driver.nim", """
import std/os
import minipy_lexer

let src = readFile(paramStr(1))
var d = Diagnostics(filename: paramStr(1))
for t in tokenize(src, d):
  echo t.pos.line, ":", t.pos.col, " ", t.kind, " ", t.text(src).len
doAssert d.items.len == 0
""")

block lexcodegen_module_matches_interpreter:
  let exe = dir / "driver"
  let (output, code) = execCmdEx("nim c --hints:off --path:" & quoteShell(root / "src") &
    " --nimcache:" & quoteShell(dir / "nimcache") &
    " -o:" & quoteShell(exe) & " " & quoteShell(dir / "driver.nim"))
  doAssert code == 0, output
  let (generated, runCode) = execCmdEx(quoteShell(exe) & " " & quoteShell(inputFile))
  doAssert runCode == 0, generated
  let src = readFile(inputFile)
  var di: Diagnostics
  var expected = ""
  for t in tokenize[int](tables, src, di):
    expected.add $t.pos.line & ":" & $t.pos.col & " " & v.tokens[t.kind].name & " " &
      $t.text(src).len & "\n"
  doAssert generated == expected, generated

block lexcodegen_enum_names:
  let src = readFile(dir / "minipy_lexer.nim")
  doAssert "    tkEOF = \"EOF\"\n" in src
  doAssert "    tkIf = \"'if'\"\n" in src
  doAssert "    tkStarStar = \"'**'\"\n" in src
  doAssert "    tkLINE_CONT = \"LINE_CONT\"\n" in src

removeDir(dir)
