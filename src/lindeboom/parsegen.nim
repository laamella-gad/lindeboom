## Parser generator: LL(1) analysis, code generation and the interpreter
## behind `lindeboom parse`.

import ./runtime/parser, ./parsegen/[analysis, codegen, interpreter]

export parser, analysis, codegen, interpreter

const runtimeFiles* = [
  ("diagnostics.nim", staticRead("runtime/diagnostics.nim")),
  ("lexer.nim", staticRead("runtime/lexer.nim")),
  ("parser.nim", staticRead("runtime/parser.nim"))]
  ## The runtime sources, for `lindeboom gen --standalone`.
