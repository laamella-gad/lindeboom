## Golden parse trees for the Lua 5.4 example grammar, plus a syntax sample
## that must parse without errors. The trees live next to the sample sources
## in `tests/grammars/lua/`; regenerate one with
## `lindeboom parse --tree examples/lua/lua.ldb tests/grammars/lua/NAME.lua`.

import std/[assertions, os]
import lindeboom/[grammar, lexgen, parsegen]

let root = currentSourcePath().parentDir.parentDir
let grammarFile = root / "examples" / "lua" / "lua.ldb"
let goldenDir = root / "tests" / "grammars" / "lua"

var (g, d) = loadGrammar(readFile(grammarFile), grammarFile)
doAssert not d.hasErrors, $d.items
let v = buildVocabulary(g)
let t = buildLexer(g, v, d)
let a = analyze(g, v, d)
doAssert not d.hasErrors, $d.items

proc parseTree(name, src: string): string =
  var di = Diagnostics(filename: name)
  let tree = a.interpret(tokenize[int](t, src, di), src, a.parserRules[0], di)
  doAssert not di.hasErrors, $di.items
  tree.treeRepr(a.treeNames)

block lua_golden_trees:
  var count = 0
  for source in walkFiles(goldenDir / "*.lua"):
    let expectedFile = source.changeFileExt("tree")
    doAssert fileExists(expectedFile), "missing " & expectedFile
    doAssert parseTree(source.extractFilename, readFile(source)) == readFile(expectedFile),
      source & ": out of date, run `lindeboom parse --tree " &
        grammarFile.relativePath(root) & " " & source.relativePath(root) & "`"
    inc count
  doAssert count > 0, "no golden Lua sources in " & goldenDir

block lua_syntax_sample_parses:
  let sample = root / "examples" / "lua" / "sample.lua"
  doAssert parseTree(sample.extractFilename, readFile(sample)).len > 0
