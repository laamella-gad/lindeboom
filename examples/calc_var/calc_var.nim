## An integer calculator with variables and an interactive shell, after
## plzoo's calc_var:
##
## ```
## calc_var> x=10
## calc_var> 3 * x + 7
## 37
## calc_var> x / 0
## Error: division by zero
## ```
##
## Reads one command per line; the prompt is shown only when the input is a
## terminal. Regenerate the parser with
## `lindeboom gen examples/calc_var/calc_var.ldb`.

import std/[strutils, tables, terminal]
import ./calcVar_parser

type
  Env* = Table[string, int]
    ## The values of the defined variables.
  CalcError = object of CatchableError

proc eval(n: Node, env: Env): int =
  ## Integer arithmetic wraps around on overflow and division truncates, as
  ## with OCaml's `int`.
  case n.kind
  of nkVariable:
    let x = n.text
    if x notin env: raise newException(CalcError, "unknown variable " & x)
    result = env[x]
  of nkNumeral:
    try:
      result = parseInt(n.text)
    except ValueError:
      raise newException(CalcError, "numeral " & n.text & " is too large")
  of nkNegate:
    result = 0 -% eval(n.operand, env)
  of nkTimes, nkPlus:
    let a = eval(n.left, env)
    let b = eval(n.right, env)
    case n.op.tok.kind
    of tkStar: result = a *% b
    of tkPlus: result = a +% b
    of tkMinus: result = a -% b
    of tkSlash:
      if b == 0: raise newException(CalcError, "division by zero")
      result = if b == -1: 0 -% a else: a div b
    else: raiseAssert $n.op.tok.kind
  of nkParen:
    result = eval(n[1], env)
  of nkDefinition, nkEvaluation, nkToken, nkError:
    raiseAssert "not an expression: " & $n.kind

proc exec*(env: var Env, command: string): seq[string] =
  ## Runs one command and returns the lines it prints: the value of an
  ## expression, nothing for a definition, or the errors.
  let res = parseToplevel(command)
  if res.diagnostics.hasErrors:
    for d in res.diagnostics: result.add "Error: column " & $d.pos.col & ": " & d.msg
  else:
    let n = res.tree
    try:
      let value = eval(n.value, env)
      if n.kind == nkDefinition: env[n.name.text] = value
      else: result.add $value
    except CalcError as e:
      result.add "Error: " & e.msg

when isMainModule:
  let interactive = stdin.isatty
  if interactive: echo "calc_var -- programming languages zoo\nType Ctrl-D to exit"
  var env: Env
  var line: string
  var more = true
  while more:
    if interactive: stdout.write "calc_var> "
    more = stdin.readLine(line)
    if more and line.strip.len > 0:
      for output in env.exec(line): echo output
  if interactive: echo ""
