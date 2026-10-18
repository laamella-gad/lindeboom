## `lindeboom` command-line tool.

import std/[os, parseopt, tables]
import lindeboom/[grammar, lexgen, parsegen]

const
  version = "0.1.0"
  usage = """
Usage:
  lindeboom check <grammar.ldb>            report grammar problems
  lindeboom gen [options] <grammar.ldb>    write <name>_lexer.nim and <name>_parser.nim
  lindeboom parse [options] <grammar.ldb> <input>
                                           parse input without generating code

Options:
  -o, --out <dir>   gen: output directory (default: the grammar's directory)
  --standalone      gen: copy the runtime into <dir>/lindeboom_runtime
  -r, --rule <name> parse: start rule (default: the first parser rule)
  --tree            parse: print the parse tree
  --tokens          parse: print the tokens instead of parsing
  -h, --help        show this help
  -v, --version     show the version"""

type
  Options = object
    outDir, rule: string
    standalone, tree, tokens: bool

  Loaded = object
    g: Grammar
    v: Vocabulary
    tables: LexerTables
    a: Analysis

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

proc load(filename: string, parser: bool, l: var Loaded): int =
  ## Loads, checks and analyzes a grammar; the parser analysis only if
  ## `parser`. Returns 0, or the exit code after reporting problems.
  var src: string
  if not readInput(filename, src):
    return 2
  var d: Diagnostics
  (l.g, d) = loadGrammar(src, filename)
  if not d.hasErrors:
    l.v = buildVocabulary(l.g)
    l.tables = buildLexer(l.g, l.v, d)
    if parser: l.a = analyze(l.g, l.v, d)
  if d.report(): result = 1

proc check(filename: string): int =
  var l: Loaded
  result = load(filename, true, l)
  if result == 0:
    var parserRules, lexerRules = 0
    for r in l.g.rules:
      if r.kind == rkParser: inc parserRules
      else: inc lexerRules
    echo filename, ": ok (", parserRules, " parser rules, ", lexerRules,
      " lexer rules)"

proc write(path, content: string): bool =
  try:
    writeFile(path, content)
    echo "wrote ", path
    result = true
  except IOError:
    stderr.writeLine "lindeboom: cannot write '" & path & "'"

proc gen(filename: string, o: Options): int =
  var l: Loaded
  result = load(filename, true, l)
  if result == 0:
    let dir = if o.outDir.len > 0: o.outDir else: filename.parentDir
    let base = dir / moduleBase(l.g)
    var lexerImport = "lindeboom/runtime/lexer"
    var parserImport = "lindeboom/runtime/parser"
    var ok = true
    try:
      createDir(dir)
      if o.standalone:
        createDir(dir / "lindeboom_runtime")
        lexerImport = "./lindeboom_runtime/lexer"
        parserImport = "./lindeboom_runtime/parser"
    except OSError, IOError:
      stderr.writeLine "lindeboom: cannot create '" & dir & "'"
      ok = false
    if ok and o.standalone:
      for (name, content) in runtimeFiles:
        ok = ok and write(dir / "lindeboom_runtime" / name, content)
    let name = filename.extractFilename
    ok = ok and write(base & "_lexer.nim", genLexerModule(l.v, l.tables, name, lexerImport)) and
      write(base & "_parser.nim", genParserModule(l.a, name, parserImport))
    if not ok: result = 2

proc printTokens(l: Loaded, input, inputFile: string): int =
  var d = Diagnostics(filename: inputFile)
  for t in tokenize[int](l.tables, input, d):
    var text = ""
    text.addQuoted(t.text(input))
    echo t.pos.line, ":", t.pos.col, " ", l.v.tokens[t.kind].name, " ", text,
      if t.hidden: " (hidden)" else: ""
  if d.report(): result = 1

proc parse(grammarFile, inputFile: string, o: Options): int =
  var l: Loaded
  var input: string
  result = load(grammarFile, not o.tokens, l)
  if result == 0 and not readInput(inputFile, input):
    result = 2
  if result == 0 and o.tokens:
    result = printTokens(l, input, inputFile)
  elif result == 0:
    var rule = if l.a.parserRules.len > 0: l.a.parserRules[0] else: -1
    if o.rule.len > 0: rule = l.a.ruleIndex.getOrDefault(o.rule, -1)
    if rule < 0:
      stderr.writeLine "lindeboom: no parser rule '" & o.rule & "'"
      result = 2
    else:
      var d = Diagnostics(filename: inputFile)
      let tree = l.a.interpret(tokenize[int](l.tables, input, d), input, rule, d)
      let failed = d.report()
      if o.tree:
        stdout.write tree.treeRepr(l.a.treeNames)
      elif not failed:
        echo inputFile, ": ok"
      if failed: result = 1

proc main(): int =
  var args: seq[string]
  var o: Options
  for kind, key, val in getopt(shortNoVal = {'h', 'v'},
      longNoVal = @["help", "version", "standalone", "tree", "tokens"], mode = LaxMode):
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
      of "o", "out": o.outDir = val
      of "r", "rule": o.rule = val
      of "standalone": o.standalone = true
      of "tree": o.tree = true
      of "tokens": o.tokens = true
      else:
        stderr.writeLine "lindeboom: unknown option '" & key & "'\n\n" & usage
        return 2
    of cmdEnd:
      discard
  if args.len == 2 and args[0] == "check":
    result = check(args[1])
  elif args.len == 2 and args[0] == "gen":
    result = gen(args[1], o)
  elif args.len == 3 and args[0] == "parse":
    result = parse(args[1], args[2], o)
  else:
    stderr.writeLine usage
    result = 2

when isMainModule:
  quit main()
