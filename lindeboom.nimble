# Package
version = "0.1.0"
author = "Laamella Gad"
description = "Nim Parser Generator"
license = "MIT"
srcDir = "src"
binDir = "bin"

# Dependencies
requires "nim >= 2.2.10"

import std/[os, strutils]

bin = @["lindeboom"]

proc grammarFiles(): seq[string] =
  ## Every grammar with checked-in generated modules.
  result = @[thisDir() / "src" / "lindeboom" / "grammar" / "ldb.ldb"]
  for dir in listDirs(thisDir() / "examples"):
    for f in listFiles(dir):
      if f.endsWith(".ldb"): result.add f

proc regenerate(exe: string) =
  for grammar in grammarFiles():
    exec quoteShell(exe) & " gen " & quoteShell(grammar)

proc regenerateAll() =
  ## Bootstrap the generator from the checked-in front end, then regenerate
  ## every parser from its grammar.
  let outDir = thisDir() / "bin"
  mkDir(outDir)
  let bootstrap = outDir / toExe("lindeboom_bootstrap")
  exec "nim c --hints:off -o:" & quoteShell(bootstrap) & " " &
    quoteShell(thisDir() / "src" / "lindeboom.nim")
  regenerate(bootstrap)
  rmFile(bootstrap)

before build:
  regenerateAll()

before test:
  regenerateAll()
