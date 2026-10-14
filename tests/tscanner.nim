import std/assertions
import lindeboom/runtime/diagnostics, lindeboom/grammar/scanner

proc kinds(src: string): seq[TokenKind] =
  var d: Diagnostics
  for t in tokenize(src, d): result.add t.kind
  doAssert not d.hasErrors, $d.items

block scanner_punctuation:
  doAssert kinds(": ; | ( ) ? * + = += ~ . .. # -> , < > }") == @[
    tkColon, tkSemi, tkPipe, tkLParen, tkRParen, tkQuestion, tkStar, tkPlus,
    tkAssign, tkPlusAssign, tkTilde, tkDot, tkRange, tkHash, tkArrow, tkComma,
    tkLt, tkGt, tkRBrace, tkEof]

block scanner_block_keywords:
  doAssert kinds("options {") == @[tkOptionsBlock, tkEof]
  doAssert kinds("tokens\n  {") == @[tkTokensBlock, tkEof]
  doAssert kinds("indentation {") == @[tkIndentationBlock, tkEof]
  # without a brace they are plain identifiers, so they can name rules
  doAssert kinds("tokens : options ;") == @[tkId, tkColon, tkId, tkSemi, tkEof]

block scanner_strings_and_sets:
  var d: Diagnostics
  let toks = tokenize("'a\\'b' [a-z\\]] 42", d)
  doAssert not d.hasErrors
  doAssert toks[0].kind == tkString and toks[0].text == "a\\'b"
  doAssert toks[1].kind == tkCharSet and toks[1].text == "a-z\\]"
  doAssert toks[2].kind == tkInt and toks[2].text == "42"

block scanner_comments_and_positions:
  var d: Diagnostics
  let toks = tokenize("// line\n/* block\n */ abc\n  é x", d)
  doAssert toks[0].text == "abc" and toks[0].pos == SourcePos(line: 3, col: 5)
  # columns count code points, not bytes
  doAssert toks[1].kind == tkId and toks[1].pos == SourcePos(line: 4, col: 5)

block scanner_errors:
  var d: Diagnostics
  discard tokenize("'abc\n/* never closed", d)
  doAssert d.errorCount == 2
  doAssert d.items[0].msg == "unterminated string literal"
  doAssert d.items[1].msg == "unterminated comment"
