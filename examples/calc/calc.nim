## Evaluates the expression given on the command line:
## `calc "1 + 2 * (3 - 4.5)"` prints `-2.0`.
##
## Regenerate the parser with `lindeboom gen examples/calc/calc.ldb`.

import std/[os, strutils]
import ./calc_parser

proc eval(n: Node): float =
  case n.kind
  of nkCalc, nkParen:
    result = eval(n.sons[if n.kind == nkCalc: 0 else: 1])
  of nkExpr, nkTerm:
    let operands = n.operands
    result = eval(operands[0])
    for i, op in n.ops:
      let x = eval(operands[i + 1])
      case op.tok.kind
      of tkPlus: result += x
      of tkMinus: result -= x
      of tkStar: result *= x
      of tkSlash: result /= x
      else: raiseAssert $op.tok.kind
  of nkNeg:
    result = -eval(n[1])
  of nkNum:
    result = parseFloat(n.text)
  of nkToken:
    raiseAssert "tokens are evaluated by their parent"

when isMainModule:
  let res = parseCalc(commandLineParams().join(" "), filename = "expression")
  for d in res.diagnostics: echo d
  if res.tree != nil:
    echo eval(res.tree)
  else:
    quit 1
