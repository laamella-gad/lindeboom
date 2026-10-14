## `lindeboom` command-line tool.

import std/parseopt
import lindeboom/[grammar, lexgen]

const
  version = "0.1.0"
  usage = """
Usage:
  lindeboom check <grammar.ldb>                    report grammar problems
  lindeboom parse --tokens <grammar.ldb> <input>   print the tokens of input

Options:
  -h, --help       show this help
  -v, --version    show the version"""

proc readInput(filename: string, src: var string): bool =
  try:
    src = readFile(filename)
    result = true
  except IOError:
    stderr.writeLine "lindeboom: cannot read '" & filename & "'"

proc report(d: Diagnostics): bool =
  ## Prints `d`; true if there were errors.
  for x in d.sorted:
    stderr.writeLine d.format(x)
  if d.hasErrors:
    let n = d.errorCount
    stderr.writeLine $n & " error" & (if n == 1: "" else: "s")
    result = true

proc check(filename: string): int =
  ## Returns the process exit code.
  var src: string
  if not readInput(filename, src):
    return 2
  var (g, d) = loadGrammar(src, filename)
  if not d.hasErrors:
    discard buildLexer(g, buildVocabulary(g), d)
  if d.report():
    result = 1
  else:
    var parserRules, lexerRules = 0
    for r in g.rules:
      if r.kind == rkParser: inc parserRules
      else: inc lexerRules
    echo filename, ": ok (", parserRules, " parser rules, ", lexerRules,
      " lexer rules)"

proc printTokens(grammarFile, inputFile: string): int =
  var gsrc, input: string
  if not readInput(grammarFile, gsrc) or not readInput(inputFile, input):
    return 2
  var (g, d) = loadGrammar(gsrc, grammarFile)
  var tables: LexerTables
  let v = buildVocabulary(g)
  if not d.hasErrors:
    tables = buildLexer(g, v, d)
  if d.report():
    return 1
  var di = Diagnostics(filename: inputFile)
  for t in tokenize[int](tables, input, di):
    var text = ""
    text.addQuoted(t.text(input))
    echo t.pos.line, ":", t.pos.col, " ", v.tokens[t.kind].name, " ", text,
      if t.hidden: " (hidden)" else: ""
  if di.report(): result = 1

proc main(): int =
  var args: seq[string]
  var tokens = false
  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      args.add key
    of cmdLongOption, cmdShortOption:
      case key
      of "h", "help":
        echo usage
        return 0
      of "tokens":
        tokens = true
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
  elif args.len == 3 and args[0] == "parse" and tokens:
    result = printTokens(args[1], args[2])
  else:
    stderr.writeLine usage
    result = 2

when isMainModule:
  quit main()
