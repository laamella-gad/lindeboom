## Reads JSON and prints it back, indented: `pretty file.json`.
## Without a file, reads standard input.
##
## Regenerate the parser with `lindeboom gen examples/json/json.ldb`.

import std/[os, strutils, unicode]
import ./json_parser

func unescape(literal: string): string =
  ## The value of a JSON string literal, quotes included in `literal`.
  var i = 1
  while i < literal.high:
    if literal[i] == '\\':
      inc i
      case literal[i]
      of 'b': result.add '\b'
      of 'f': result.add '\f'
      of 'n': result.add '\n'
      of 'r': result.add '\r'
      of 't': result.add '\t'
      of 'u':
        var code = parseHexInt(literal[i + 1 .. i + 4])
        i += 4
        # a surrogate pair encodes one code point
        if code in 0xD800 .. 0xDBFF and literal.continuesWith("\\u", i + 1):
          let low = parseHexInt(literal[i + 3 .. i + 6])
          if low in 0xDC00 .. 0xDFFF:
            code = 0x10000 + (code - 0xD800) shl 10 + (low - 0xDC00)
            i += 6
        result.add Rune(code).toUTF8
      else: result.add literal[i]
    else:
      result.add literal[i]
    inc i

func escapeJson(s: string): string =
  result = "\""
  for r in s.runes:
    case r.int
    of ord('"'): result.add "\\\""
    of ord('\\'): result.add "\\\\"
    of ord('\n'): result.add "\\n"
    of ord('\r'): result.add "\\r"
    of ord('\t'): result.add "\\t"
    of 0 .. 8, 11, 12, 14 .. 31: result.add "\\u" & toHex(r.int, 4)
    else: result.add r.toUTF8
  result.add '"'

proc pretty(n: Node, indent: int, s: var string) =
  let pad = repeat("  ", indent + 1)
  case n.kind
  of nkObject, nkArray:
    let (open, close) = if n.kind == nkObject: ("{", "}") else: ("[", "]")
    let items = if n.kind == nkObject: n.members else: n.elements
    s.add open
    for i, x in items:
      s.add(if i > 0: ",\n" else: "\n")
      s.add pad
      if x.kind == nkPair:
        s.add escapeJson(unescape(x.key.text)) & ": "
        pretty(x.value, indent + 1, s)
      else:
        pretty(x, indent + 1, s)
    if items.len > 0: s.add "\n" & repeat("  ", indent)
    s.add close
  of nkString:
    s.add escapeJson(unescape(n.text))
  of nkNumber, nkTrue, nkFalse, nkNull:
    s.add n.text
  of nkJson:
    pretty(n[0], indent, s)
  of nkPair, nkToken:
    raiseAssert "handled by the parent"
  of nkError:
    raiseAssert "not in a tree without syntax errors"

when isMainModule:
  let filename = if paramCount() > 0: paramStr(1) else: "stdin"
  let src = if paramCount() > 0: readFile(filename) else: stdin.readAll()
  let res = parseJson(src, filename)
  for d in res.diagnostics: stderr.writeLine d
  if res.diagnostics.hasErrors: quit 1
  var s = ""
  pretty(res.tree, 0, s)
  echo s
