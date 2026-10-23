## MiniML: an eager, statically typed functional language, after plzoo's
## miniml:
## https://github.com/andrejbauer/plzoo/tree/master/src/miniml
##
## ```
## miniML> let fact =
##      ... fun f (n : int) : int is
##      ...   if n = 0 then 1 else n * f (n-1) ;;
## fact : int -> int = <fun>
## miniML> fact 10 ;;
## - : int = 3628800
## ```
##
## With file arguments, loads and runs each file in turn. Without, reads
## commands from standard input. A command ends with `;;`.
##
## Regenerate the parser with `lindeboom gen examples/miniml/miniml.ldb`.

import std/[os, strutils, tables, terminal]
import ./miniML_parser

type
  TyKind* = enum
    tyInt, tyBool, tyArrow

  Type* = ref object
    ## A MiniML type: `int`, `bool`, or a function type.
    case kind*: TyKind
    of tyArrow:
      arg*, res*: Type
    else:
      discard

  ExprKind = enum
    ekVar, ekInt, ekBool, ekBinary, ekIf, ekFun, ekApply

  Expr = ref object
    ## `kind` says which of these fields are used.
    pos*: SourcePos
    kind*: ExprKind
    name*: string
    intVal*: int
    boolVal*: bool
    left*, right*: Expr
    op*: string
    cond*, yes*, no*: Expr
    arg*: string
    argType*, resultType*: Type
    body*: Expr

  CommandKind = enum
    ckDefinition, ckEvaluation

  Command = object
    kind: CommandKind
    name: string
    value: Expr

  TypeEnv* = Table[string, Type]
  Env* = Table[string, Value]

  ValueKind = enum
    vkInt, vkBool, vkClosure

  Value* = ref object
    ## A runtime value: an integer, a boolean, or a closure.
    case kind*: ValueKind
    of vkInt:
      intVal*: int
    of vkBool:
      boolVal*: bool
    of vkClosure:
      closure*: Closure

  Closure = ref object
    fnName, argName: string
    body: Expr
    env: Env

  MiniMLError* = object of CatchableError
    ## A type or evaluation error with the expression's position.
    pos*: SourcePos

proc raiseAt(pos: SourcePos; msg: string) {.noreturn.} =
  var e = newException(MiniMLError, msg)
  e.pos = pos
  raise e

func intType(): Type = Type(kind: tyInt)

func boolType(): Type = Type(kind: tyBool)

func arrowType(arg, res: Type): Type = Type(kind: tyArrow, arg: arg, res: res)

proc sameType*(a, b: Type): bool =
  ## Structural equality of types.
  if a.kind != b.kind: return false
  case a.kind
  of tyArrow: sameType(a.arg, b.arg) and sameType(a.res, b.res)
  of tyInt, tyBool: true

proc typeText*(t: Type): string =
  ## `t` as MiniML source, with parentheses around a function argument.
  case t.kind
  of tyInt:
    result = "int"
  of tyBool:
    result = "bool"
  of tyArrow:
    let arg = if t.arg.kind == tyArrow: "(" & typeText(t.arg) & ")" else: typeText(t.arg)
    result = arg & " -> " & typeText(t.res)

proc toType(n: Node): Type =
  case n.kind
  of nkTypeInt: intType()
  of nkTypeBool: boolType()
  of nkTypeArrow: arrowType(toType(n.left), toType(n.right))
  of nkTypeParen: toType(n.value)
  else: raiseAssert "not a type: " & $n.kind

proc integer(n: Node; negative = false): int =
  let text = (if negative: "-" else: "") & n.value.text
  try:
    result = parseInt(text)
  except ValueError:
    raiseAt(n.pos, "integer literal " & text & " is too large")

proc toExpr(n: Node): Expr =
  case n.kind
  of nkSimple, nkParen:
    result = toExpr(n.value)
  of nkInt:
    result = Expr(kind: ekInt, pos: n.pos, intVal: integer(n))
  of nkNegative:
    result = Expr(kind: ekInt, pos: n.pos, intVal: integer(n, negative = true))
  of nkTrue:
    result = Expr(kind: ekBool, pos: n.pos, boolVal: true)
  of nkFalse:
    result = Expr(kind: ekBool, pos: n.pos, boolVal: false)
  of nkVar:
    result = Expr(kind: ekVar, pos: n.pos, name: n.name.text)
  of nkTimes, nkPlus, nkCompare:
    result = Expr(kind: ekBinary, pos: n.pos, left: toExpr(n.left),
      op: n.op.text, right: toExpr(n.right))
  of nkApply:
    result = Expr(kind: ekApply, pos: n.pos, left: toExpr(n.left),
      right: toExpr(n.argument))
  of nkIf:
    result = Expr(kind: ekIf, pos: n.pos, cond: toExpr(n.cond),
      yes: toExpr(n.yes), no: toExpr(n.no))
  of nkFun:
    result = Expr(kind: ekFun, pos: n.pos, name: n.name.text,
      arg: n.arg.text, argType: toType(n.argType),
      resultType: toType(n.resultType), body: toExpr(n.body))
  of nkToken, nkError, nkFile, nkDefinition, nkEvaluation, nkTypeArrow,
      nkTypeInt, nkTypeBool, nkTypeParen:
    raiseAssert "not an expression: " & $n.kind

proc toCommand(n: Node): Command =
  case n.kind
  of nkDefinition:
    result = Command(kind: ckDefinition, name: n.name.text, value: toExpr(n.value))
  of nkEvaluation:
    result = Command(kind: ckEvaluation, value: toExpr(n.value))
  else:
    raiseAssert "not a command: " & $n.kind

proc checkExpr(ctx: TypeEnv; expected: Type; e: Expr)

proc typeOf(ctx: TypeEnv; e: Expr): Type =
  case e.kind
  of ekVar:
    if e.name notin ctx: raiseAt(e.pos, "unknown variable '" & e.name & "'")
    result = ctx[e.name]
  of ekInt:
    result = intType()
  of ekBool:
    result = boolType()
  of ekBinary:
    checkExpr(ctx, intType(), e.left)
    checkExpr(ctx, intType(), e.right)
    result = if e.op in ["=", "<"]: boolType() else: intType()
  of ekIf:
    checkExpr(ctx, boolType(), e.cond)
    result = typeOf(ctx, e.yes)
    checkExpr(ctx, result, e.no)
  of ekFun:
    result = arrowType(e.argType, e.resultType)
    var inner = ctx
    inner[e.name] = result
    inner[e.arg] = e.argType
    checkExpr(inner, e.resultType, e.body)
  of ekApply:
    let fn = typeOf(ctx, e.left)
    if fn.kind != tyArrow:
      raiseAt(e.left.pos, "this expression is used as a function but its type is " &
        typeText(fn))
    checkExpr(ctx, fn.arg, e.right)
    result = fn.res

proc checkExpr(ctx: TypeEnv; expected: Type; e: Expr) =
  let got = typeOf(ctx, e)
  if not sameType(got, expected):
    raiseAt(e.pos, "this expression has type " & typeText(got) &
      " but is used as if it has type " & typeText(expected))

proc valueText*(v: Value): string =
  case v.kind
  of vkInt:
    result = $v.intVal
  of vkBool:
    result = if v.boolVal: "true" else: "false"
  of vkClosure:
    result = "<fun>"

proc eval(e: Expr; env: Env): Value =
  case e.kind
  of ekVar:
    if e.name notin env: raiseAt(e.pos, "unknown variable '" & e.name & "'")
    result = env[e.name]
  of ekInt:
    result = Value(kind: vkInt, intVal: e.intVal)
  of ekBool:
    result = Value(kind: vkBool, boolVal: e.boolVal)
  of ekBinary:
    let a = eval(e.left, env)
    let b = eval(e.right, env)
    case e.op
    of "*":
      result = Value(kind: vkInt, intVal: a.intVal *% b.intVal)
    of "+":
      result = Value(kind: vkInt, intVal: a.intVal +% b.intVal)
    of "-":
      result = Value(kind: vkInt, intVal: a.intVal -% b.intVal)
    of "=":
      result = Value(kind: vkBool, boolVal: a.intVal == b.intVal)
    of "<":
      result = Value(kind: vkBool, boolVal: a.intVal < b.intVal)
    else:
      raiseAssert "unknown operator: " & e.op
  of ekIf:
    if eval(e.cond, env).boolVal: result = eval(e.yes, env)
    else: result = eval(e.no, env)
  of ekFun:
    var captured = env
    let closure = Closure(fnName: e.name, argName: e.arg, body: e.body,
      env: captured)
    let self = Value(kind: vkClosure, closure: closure)
    closure.env[e.name] = self
    result = self
  of ekApply:
    let fn = eval(e.left, env)
    if fn.kind != vkClosure:
      raiseAt(e.left.pos, "this expression is not a function")
    let argument = eval(e.right, env)
    var callEnv = fn.closure.env
    callEnv[fn.closure.argName] = argument
    result = eval(fn.closure.body, callEnv)

proc execute*(ctx: var TypeEnv; env: var Env; src: string;
    filename = "input"): seq[string] =
  ## Parses and runs the commands in `src`, updating `ctx` and `env`, and
  ## returns the lines to print. Stops at the first type or evaluation error.
  let res = parseFile(src, filename)
  if res.diagnostics.hasErrors:
    for d in res.diagnostics:
      # If the input is missing a final ';;' and the grammar change made
      # recovery awkward, still try to parse what we have by appending ';;'.
      result.add $d
    # Fall back: if only missing final ';;', try appending it for the REPL.
    var diagCount = 0
    var firstMsg = ""
    for d in res.diagnostics:
      if diagCount == 0: firstMsg = $d
      diagCount.inc
    if diagCount == 1 and "expected ';;'" in firstMsg:
      let res2 = parseFile(src & "\n;;\n", filename)
      if not res2.diagnostics.hasErrors and res2.tree != nil:
        for n in res2.tree.commands:
          try:
            let command = toCommand(n)
            let ty = typeOf(ctx, command.value)
            let value = eval(command.value, env)
            case command.kind
            of ckDefinition:
              ctx[command.name] = ty
              env[command.name] = value
              result.add command.name & " : " & typeText(ty) & " = " & valueText(value)
            of ckEvaluation:
              result.add "- : " & typeText(ty) & " = " & valueText(value)
          except MiniMLError as e:
            result.add "Error: line " & $e.pos.line & ", column " & $e.pos.col &
              ": " & e.msg
            break
        return
    return
  if res.tree == nil: return
  for n in res.tree.commands:
    try:
      let command = toCommand(n)
      let ty = typeOf(ctx, command.value)
      let value = eval(command.value, env)
      case command.kind
      of ckDefinition:
        ctx[command.name] = ty
        env[command.name] = value
        result.add command.name & " : " & typeText(ty) & " = " & valueText(value)
      of ckEvaluation:
        result.add "- : " & typeText(ty) & " = " & valueText(value)
    except MiniMLError as e:
      result.add "Error: line " & $e.pos.line & ", column " & $e.pos.col &
        ": " & e.msg
      break

when isMainModule:
  let interactive = stdin.isatty
  var ctx: TypeEnv
  var env: Env

  if paramCount() > 0:
    for filename in commandLineParams():
      for output in execute(ctx, env, readFile(filename), filename):
        echo output
  else:
    if interactive:
      echo "miniML -- programming languages zoo"
      echo "Type Ctrl-D to exit"
    var buffer = ""
    var line: string
    while true:
      if interactive:
        stdout.write(if buffer.len == 0: "miniML> " else: "      > ")
        stdout.flushFile()
      if not stdin.readLine(line): break
      buffer.add line
      buffer.add '\n'
      if ";;" in buffer:
        for output in execute(ctx, env, buffer, "stdin"):
          echo output
        buffer.setLen(0)
    if buffer.strip.len > 0:
      for output in execute(ctx, env, buffer, "stdin"):
        echo output
    if interactive: echo ""
