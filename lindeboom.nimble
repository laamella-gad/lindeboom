# Package
version = "0.1.0"
author = "Laamella Gad"
description = "Nim Parser Generator"
license = "MIT"
srcDir = "src"
binDir = "bin"

# Dependencies
requires "nim >= 2.2.10"

bin = @["lindeboom"]

task test, "Run the test suite":
  exec "nim c -r tests/tester.nim"
