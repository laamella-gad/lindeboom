import std/[assertions, unicode]
import lindeboom/grammar
import ./helpers

proc parse(src: string): Grammar =
  var d = Diagnostics(filename: "test.ldb")
  result = parseGrammar(src, d)
  doAssert not d.hasErrors, $d.items

block parser_header_and_prequel:
  let g = parse("""
    grammar Calc;
    options { tabWidth = 4; }
    tokens { INDENT, DEDENT, }
    indentation {
      newline = NL; indent = INDENT; dedent = DEDENT;
      brackets = '(' ')', '[' ']';
      tabs = strict;
    }
    """)
  doAssert g.name == "Calc"
  doAssert g.options.len == 1 and g.options[0].name == "tabWidth" and
    g.options[0].value == "4"
  doAssert g.tokens.len == 2 and g.tokens[1].name == "DEDENT"
  doAssert g.hasIndentation
  doAssert g.indentation.newline.value == "NL"
  doAssert g.indentation.tabs.value == "strict"
  doAssert g.indentation.brackets.len == 2
  doAssert g.indentation.brackets[1].open == "[" and
    g.indentation.brackets[1].close == "]"

block parser_rules_and_alternatives:
  let g = parse("""
    grammar G;
    expr : <assoc=right> left=expr '^' right=expr  # pow
         | args=ID (',' args=ID)*                  # list
         ;
    fragment DIGIT : [0-9] ;
    WS : [ \t]+ -> skip ;
    """)
  doAssert g.rules.len == 3
  let expr = g.rules[0]
  doAssert expr.kind == rkParser and expr.alts.len == 2
  doAssert expr.alts[0].hasAssoc and expr.alts[0].assoc == assocRight
  doAssert expr.alts[0].label == "pow"
  let items = expr.alts[0].body.items
  doAssert items.len == 3
  doAssert items[0].kind == ekRuleRef and items[0].label == "left"
  doAssert items[1].kind == ekLiteral and items[1].text == "^"
  let list = expr.alts[1].body.items
  doAssert list[0].kind == ekTokenRef and list[0].label == "args"
  doAssert list[1].kind == ekStar and list[1].greedy
  doAssert list[1].inner.kind == ekSeq and list[1].inner.items[1].label == "args"
  doAssert g.rules[1].isFragment and g.rules[1].kind == rkLexer
  doAssert g.rules[2].alts[0].commands[0].kind == lcSkip

block parser_lexer_elements:
  let g = parse("""
    grammar G;
    A : 'a'..'z' ~[\n\r] . 'x'*? 'é\u{1F600}' [\-a\]] ~('a' | 'b') ;
    """)
  let items = g.rules[0].alts[0].body.items
  doAssert items[0].kind == ekRange and items[0].lo == Rune('a') and
    items[0].hi == Rune('z')
  doAssert items[1].kind == ekNot and items[1].inner.kind == ekCharSet
  doAssert items[1].inner.ranges == @[(Rune('\n'), Rune('\n')),
    (Rune('\r'), Rune('\r'))]
  doAssert items[2].kind == ekWildcard
  doAssert items[3].kind == ekStar and not items[3].greedy
  doAssert items[4].text == "é\u{1F600}"
  doAssert items[5].ranges == @[(Rune('-'), Rune('-')), (Rune('a'), Rune('a')),
    (Rune(']'), Rune(']'))]
  doAssert items[6].kind == ekNot and items[6].inner.kind == ekAlt

block parser_char_set_ranges:
  let g = parse("grammar G; A : [a-zA-Z_] ;")
  doAssert g.rules[0].alts[0].body.items[0].ranges == @[
    (Rune('a'), Rune('z')), (Rune('A'), Rune('Z')), (Rune('_'), Rune('_'))]

block parser_syntax_errors:
  # the parser recovers, so each broken rule reports its own error
  let msgs = messages("""
grammar G;
a : b ) ;
c : d
""")
  const continuing = "';', '=', '|', '#', '->', '(', '.', '~', '?', '*', '+', ID, STRING or CHARSET"
  doAssert msgs == @["2:7: error: expected " & continuing & " but found ')'",
    "4:1: error: expected " & continuing & " but found end of input"], $msgs
  doAssert "a : 'x' ;".hasMessage("1:1: error: expected 'grammar' but found ID")
  doAssert "grammar G; a : ('x' # l) ;".hasMessage(
    "1:21: error: expected '|', '(', ')', '..', '.', '~', '?', '*', '+', ID, STRING or CHARSET but found '#'")
  doAssert "grammar G; A : 'abc ;".hasMessage("1:16: error: unexpected character '\\''")

block parser_identifier_checks:
  doAssert "grammar G; A : 'x' -> channel ;".hasMessage(
    "lexer command 'channel' needs an argument, as in 'channel(NAME)'")
  doAssert "grammar G; A : 'x' -> skip(X) ;".hasMessage("lexer command 'skip' takes no argument")
  doAssert "grammar G; A : 'x' -> more ;".hasMessage("unknown lexer command 'more'")
  doAssert "grammar G; a : <assok=left> 'x' ;".hasMessage("expected 'assoc' but found 'assok'")
  doAssert "grammar G; a : <assoc=up> 'x' ;".hasMessage("expected 'left' or 'right' but found 'up'")
  let ind = "grammar G; tokens { I, D } indentation { newline = '(' ')'; brackets = NL; " &
    "dedent = D; dedent = D; } a : NL I D '(' ; NL : '\\n' ;"
  doAssert ind.hasMessage("1:42: error: indentation setting 'newline' takes a name")
  doAssert ind.hasMessage("'brackets' takes pairs of literals, as in '(' ')'")
  doAssert ind.hasMessage("duplicate indentation setting 'dedent'")
  doAssert "grammar G; indentation { } indentation { } a : 'x' ;".hasMessage(
    "1:28: error: duplicate 'indentation' block")

block parser_bad_escapes:
  doAssert "grammar G; A : '\\q' ;".hasMessage("invalid escape sequence '\\q'")
  doAssert "grammar G; A : 'ab'..'z' ;".hasMessage("must be a single character")
  doAssert "grammar G; A : [z-a] ;".hasMessage("reversed range")
  doAssert "grammar G; A : '' ;".hasMessage("empty literal")
