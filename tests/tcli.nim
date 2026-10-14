import std/[assertions, os, osproc, strutils]

let root = currentSourcePath().parentDir.parentDir
let exe = root / "bin" / "lindeboom_test"
doAssert execCmd("nim c --hints:off -o:" & quoteShell(exe) & " " &
  quoteShell(root / "src" / "nim_parser_generator.nim")) == 0

proc run(args: string): (string, int) =
  execCmdEx(quoteShell(exe) & " " & args)

block cli_check_ok:
  let (output, code) = run("check " & quoteShell(root / "examples" / "minipy" / "minipy.ldb"))
  doAssert code == 0, output
  doAssert "ok (12 parser rules, 8 lexer rules)" in output, output

block cli_check_errors:
  let f = getTempDir() / "lindeboom_tcli_bad.ldb"
  writeFile(f, "grammar G;\na : b ;\n")
  let (output, code) = run("check " & quoteShell(f))
  doAssert code == 1, output
  doAssert f & ":2:5: error: undefined rule 'b'" in output, output
  doAssert "1 error" in output, output
  removeFile(f)

block cli_usage:
  doAssert run("")[1] == 2
  doAssert run("check /no/such/file.ldb")[1] == 2
  doAssert run("--version")[1] == 0
