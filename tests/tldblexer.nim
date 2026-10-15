## The lexer generated from `ldb.ldb`.

import std/assertions
import lindeboom/grammar/ldb_lexer

proc kinds(src: string): seq[TokenKind] =
  var d: Diagnostics
  for t in tokenize(src, d): result.add t.kind
  doAssert not d.hasErrors, $d.items

block ldblexer_punctuation:
  doAssert kinds(": ; | ( ) ? * + = ~ . .. # -> , < > }") == @[
    tkColon, tkSemi, tkPipe, tkLParen, tkRParen, tkQuestion, tkStar, tkPlus,
    tkEq, tkTilde, tkDot, tkDotDot, tkHash, tkMinusGt, tkComma,
    tkLt, tkGt, tkRBrace, tkEOF]

block ldblexer_block_keywords:
  doAssert kinds("options {") == @[tkOPTIONS, tkEOF]
  doAssert kinds("tokens\n  {") == @[tkTOKENS, tkEOF]
  doAssert kinds("indentation {") == @[tkINDENTATION, tkEOF]
  # without a brace they are plain identifiers, so they can name rules
  doAssert kinds("tokens : options ;") == @[tkID, tkColon, tkID, tkSemi, tkEOF]
  doAssert kinds("grammar fragment grammars") == @[tkGrammar, tkFragment, tkID, tkEOF]

block ldblexer_strings_and_sets:
  let src = "'a\\'b' [a-z\\]] 42"
  var d: Diagnostics
  let toks = tokenize(src, d)
  doAssert not d.hasErrors
  doAssert toks[0].kind == tkSTRING and toks[0].text(src) == "'a\\'b'"
  doAssert toks[1].kind == tkCHARSET and toks[1].text(src) == "[a-z\\]]"
  doAssert toks[2].kind == tkINT and toks[2].text(src) == "42"

block ldblexer_comments_and_positions:
  let src = "// line\n/* block\n */ abc\n  /*é*/ x"
  var d: Diagnostics
  let toks = tokenize(src, d)
  doAssert toks[0].text(src) == "abc" and toks[0].pos == SourcePos(line: 3, col: 5)
  # columns count code points, not bytes
  doAssert toks[1].kind == tkID and toks[1].pos == SourcePos(line: 4, col: 9)

block ldblexer_errors:
  var d: Diagnostics
  discard tokenize("a 'abc\n", d)
  doAssert d.items[0].msg == "unexpected character '\\''", $d.items
  d = Diagnostics()
  discard tokenize("a /* never closed", d)
  doAssert d.items[0].msg == "unexpected character '/'", $d.items
