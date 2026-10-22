import std/[assertions, os, osproc, strutils]

let root = currentSourcePath().parentDir.parentDir
let exe = root / "bin" / "lindeboom_test"
doAssert execCmd("nim c --hints:off -o:" & quoteShell(exe) & " " &
  quoteShell(root / "src" / "lindeboom.nim")) == 0

proc run(args: string): (string, int) =
  execCmdEx(quoteShell(exe) & " " & args)

let calc = quoteShell(root / "examples" / "calc" / "calc.ldb")
let tmp = getTempDir() / "lindeboom_tcli"
createDir(tmp)

block cli_check_ok:
  let (output, code) = run("check " & calc)
  doAssert code == 0, output
  doAssert "ok (4 parser rules, 3 lexer rules)" in output, output

block cli_check_nonLl1_grammar_without_warning:
  let (output, code) = run("check " & quoteShell(root / "examples" / "minipy" / "minipy.ldb"))
  doAssert code == 0, output
  doAssert "warning:" notin output, output
  doAssert "ok (12 parser rules, 8 lexer rules)" in output, output

block cli_check_errors:
  let f = getTempDir() / "lindeboom_tcli_bad.ldb"
  writeFile(f, "grammar G;\na : b ;\n")
  let (output, code) = run("check " & quoteShell(f))
  doAssert code == 1, output
  doAssert f & ":2:5: error: undefined rule 'b'" in output, output
  doAssert "1 error" in output, output
  removeFile(f)

block cli_parse_tokens:
  let f = getTempDir() / "lindeboom_tcli_input.py"
  writeFile(f, "def f(x):\n    return x ** 2\n")
  let (output, code) = run("parse --tokens " &
    quoteShell(root / "examples" / "minipy" / "minipy.ldb") & " " & quoteShell(f))
  doAssert code == 0, output
  doAssert output.startsWith("1:1 'def' \"def\"\n1:5 ID \"f\"\n"), output
  doAssert "2:5 INDENT \"\"\n2:5 'return'" in output, output
  doAssert "2:14 '**' \"**\"\n" in output, output
  doAssert output.endsWith("3:1 DEDENT \"\"\n3:1 EOF \"\"\n"), output
  doAssert output.endsWith("3:1 EOF \"\"\n"), output
  writeFile(f, "x = $")
  let (errOutput, errCode) = run("parse --tokens " &
    quoteShell(root / "examples" / "minipy" / "minipy.ldb") & " " & quoteShell(f))
  doAssert errCode == 1, errOutput
  doAssert f & ":1:5: error: unexpected character '$'" in errOutput, errOutput
  removeFile(f)

block cli_parse_tree:
  let f = tmp / "input.txt"
  writeFile(f, "1 + 2")
  let (output, code) = run("parse --tree " & calc & " " & quoteShell(f))
  doAssert code == 0, output
  doAssert output.startsWith("calc\n└── expr\n    ├── operands: term\n"), output
  let (okOutput, okCode) = run("parse " & calc & " " & quoteShell(f))
  doAssert (okOutput, okCode) == (f & ": ok\n", 0), okOutput
  writeFile(f, "1 +")
  let (errOutput, errCode) = run("parse " & calc & " " & quoteShell(f))
  doAssert errCode == 1, errOutput
  doAssert f & ":1:4: error: expected '-', '(' or NUMBER but found end of input" in errOutput,
    errOutput
  # with errors, the tree is still printed, with error nodes
  let (treeOutput, treeCode) = run("parse --tree " & calc & " " & quoteShell(f))
  doAssert treeCode == 1, treeOutput
  doAssert "└── operands: error\n" in treeOutput, treeOutput
  doAssert f & ":1:4: error: expected" in treeOutput, treeOutput

block cli_parse_rule:
  let f = tmp / "input.txt"
  writeFile(f, "7")
  let (output, code) = run("parse -r factor --tree " & calc & " " & quoteShell(f))
  doAssert (output, code) == ("num\n└── NUMBER \"7\"\n", 0), output
  let (errOutput, errCode) = run("parse --rule nope " & calc & " " & quoteShell(f))
  doAssert errCode == 2, errOutput
  doAssert "no parser rule 'nope'" in errOutput, errOutput

block cli_gen:
  let dir = tmp / "gen"
  let (output, code) = run("gen -o " & quoteShell(dir) & " " & calc)
  doAssert code == 0, output
  doAssert "wrote " & dir / "calc_parser.nim" in output, output
  doAssert readFile(dir / "calc_parser.nim") ==
    readFile(root / "examples" / "calc" / "calc_parser.nim")
  doAssert not dirExists(dir / "lindeboom_runtime")

block cli_gen_standalone:
  let dir = tmp / "standalone"
  let (output, code) = run("gen --standalone -o " & quoteShell(dir) & " " & calc)
  doAssert code == 0, output
  for f in ["diagnostics", "lexer", "parser"]:
    doAssert fileExists(dir / "lindeboom_runtime" / f & ".nim"), f
  doAssert "import ./lindeboom_runtime/parser" in readFile(dir / "calc_parser.nim")

block cli_usage:
  doAssert run("")[1] == 2
  doAssert run("check /no/such/file.ldb")[1] == 2
  doAssert run("--version")[1] == 0

removeDir(tmp)
