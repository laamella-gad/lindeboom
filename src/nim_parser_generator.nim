## `lindeboom` command-line tool.

import std/parseopt
import lindeboom/grammar

const
  version = "0.1.0"
  usage = """
Usage:
  lindeboom check <grammar.ldb>   report grammar problems

Options:
  -h, --help       show this help
  -v, --version    show the version"""

proc check(filename: string): int =
  ## Returns the process exit code.
  var src: string
  try:
    src = readFile(filename)
  except IOError:
    stderr.writeLine "lindeboom: cannot read '" & filename & "'"
    return 2
  let (g, d) = loadGrammar(src, filename)
  for x in d.sorted:
    stderr.writeLine d.format(x)
  if d.hasErrors:
    let n = d.errorCount
    stderr.writeLine $n & " error" & (if n == 1: "" else: "s")
    result = 1
  else:
    var parserRules, lexerRules = 0
    for r in g.rules:
      if r.kind == rkParser: inc parserRules
      else: inc lexerRules
    echo filename, ": ok (", parserRules, " parser rules, ", lexerRules,
      " lexer rules)"

proc main(): int =
  var args: seq[string]
  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      args.add key
    of cmdLongOption, cmdShortOption:
      case key
      of "h", "help":
        echo usage
        return 0
      of "v", "version":
        echo "lindeboom ", version
        return 0
      else:
        stderr.writeLine "lindeboom: unknown option '" & key & "'\n\n" & usage
        return 2
    of cmdEnd:
      discard
  if args.len == 2 and args[0] == "check":
    result = check(args[1])
  else:
    stderr.writeLine usage
    result = 2

when isMainModule:
  quit main()
