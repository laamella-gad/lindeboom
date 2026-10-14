import std/[assertions, strutils, tables, unicode]
import lindeboom/[grammar, lexgen]
import lindeboom/lexgen/charsets
import ./lexhelpers

func encode(c: int32): seq[uint8] =
  for b in toUtf8(Rune(c)): result.add uint8(b)

proc matches(s: seq[ByteRange], bytes: seq[uint8]): bool =
  if s.len == bytes.len:
    result = true
    for k in 0 ..< s.len:
      if bytes[k] notin s[k].lo .. s[k].hi: result = false

block charsets_utf8_sequences_match_exactly:
  let sets = [anyChar(), @[(0x80'i32, 0x7FF'i32)], @[(0x7F'i32, 0x800'i32)],
    @[(0xFFFF'i32, 0x10000'i32)], @[(0xD7FF'i32, 0xE000'i32)],
    complement(@[(int32('a'), int32('z'))]), @[(0x1234'i32, 0x56789'i32)]]
  for cs in sets:
    let seqs = utf8Sequences(cs)
    var c = 0'i32
    while c <= maxCode:
      var inSet = c notin 0xD800'i32 .. 0xDFFF'i32
      if inSet:
        inSet = false
        for r in cs:
          if c in r.lo .. r.hi: inSet = true
      var n = 0
      if c notin 0xD800'i32 .. 0xDFFF'i32:
        for s in seqs:
          if s.matches(encode(c)): inc n
      doAssert n == ord(inSet), $c & " matched " & $n & " times"
      c += (if c < 0x11000: 1 else: 61)

block charsets_normalize_and_complement:
  doAssert normalize([(5'i32, 9'i32), (1'i32, 3'i32), (4'i32, 4'i32), (20'i32, 30'i32),
    (25'i32, 26'i32)]) == @[(1'i32, 9'i32), (20'i32, 30'i32)]
  doAssert complement(@[(0'i32, 0x60'i32), (0x62'i32, maxCode)]) == @[(0x61'i32, 0x61'i32)]
  doAssert complement(@[(0'i32, 0xD000'i32)]) ==
    @[(0xD001'i32, 0xD7FF'i32), (0xE000'i32, maxCode)]

block vocabulary_order_and_names:
  let (v, _, _) = build("""
    grammar G;
    tokens { INDENT }
    a : 'if' ID '(' '**' '==' 'é' 'a_b' INDENT ;
    ID : [a-z]+ ;
    """)
  var names, idents: seq[string]
  for t in v.tokens:
    names.add t.name
    idents.add t.ident
  doAssert names == @["EOF", "'if'", "'('", "'**'", "'=='", "'é'", "'a_b'", "ID",
    "INDENT"], $names
  doAssert idents == @["tkEOF", "tkIf", "tkLParen", "tkStarStar", "tkEqEq",
    "tkU00E9", "tkA_b", "tkID", "tkINDENT"], $idents

block vocabulary_literal_aliases_rule:
  let (v, _, _) = build("grammar G; a : '+' IF 'if' ; PLUS : '+' ; IF : 'if' | 'IF' ;")
  doAssert v.byLiteral["+"] == v.byName["PLUS"]
  # 'if' is not exactly IF's body, so it is a token of its own
  doAssert v.tokens[v.byLiteral["if"]].ident == "tkIf2"
  doAssert v.tokens[v.byName["IF"]].ident == "tkIF"

block vocabulary_idents_are_valid_nim:
  let (v, _, _) = build("grammar G; a : A__B C_ ; A__B : 'a' ; C_ : 'c' ;")
  doAssert v.tokens[1].ident == "tkA_B" and v.tokens[2].ident == "tkC"

block lex_longest_match_and_priority:
  const g = """
    grammar G;
    a : ('if' | '=' | '==' | ID | NUM | KW | TWICE)* ;
    ID : [a-z]+ ;
    KW : 'while' ;
    NUM : [0-9]+ ;
    TWICE : [0-9]+ ;
    WS : ' '+ -> skip ;
    """
  # literals win ties with rules; longer matches win over literals
  doAssert lexOne(g, "if iffy ===") == "'if' if | ID iffy | '==' == | '=' ="
  # equal length: earlier rule wins, so TWICE never matches
  doAssert lexOne(g, "while 42") == "ID while | NUM 42"

block lex_shadowed_rules_warn:
  let (_, _, d) = build("grammar G; a : ID KW TWICE ; ID : [a-z]+ ; KW : 'while' ; TWICE : [a-z]+ ;")
  doAssert d.items.len == 2
  doAssert d.items[0].msg == "lexer rule 'KW' never produces a token: its input is always matched by 'ID', which takes priority"
  doAssert d.items[1].msg.startsWith("lexer rule 'TWICE' never produces a token")

block lex_alternatives_of_one_rule_take_longest:
  doAssert lexOne("grammar G; a : A* ; A : 'a' | 'ab' ;", "aba") == "A ab | A a"

block lex_non_greedy:
  const g = """
    grammar G;
    a : (ID | STR | COMMENT)* ;
    COMMENT : '/*' .*? '*/' ;
    STR : '"' ('\\' . | .)*? '"' ;
    ID : [a-z*/]+ ;
    WS : ' '+ -> skip ;
    """
  doAssert lexOne(g, "/* a * / b */ c */") == "COMMENT /* a * / b */ | ID c | ID */"
  doAssert lexOne(g, "\"a\" \"b\\\"c\"") == "STR \"a\" | STR \"b\\\"c\""

block lex_greedy_optional_inside_non_greedy:
  doAssert lexOne("grammar G; a : A* ; A : '<' .*? '>' 'x'? ;", "<a>x<b>") ==
    "A <a>x | A <b>"

block lex_fragments_and_sets:
  const g = """
    grammar G;
    a : (NUM | NAME)* ;
    NUM : DIGIT+ ('.' DIGIT+)? | '0x' HEX+ ;
    NAME : ~[ 0-9.] (~[ .])* ;
    fragment DIGIT : [0-9] ;
    fragment HEX : DIGIT | [a-fA-F] | 'A'..'F' ;
    WS : ' ' -> skip ;
    """
  doAssert lexOne(g, "1.5 0xfF x1 éa😀") == "NUM 1.5 | NUM 0xfF | NAME x1 | NAME éa😀"

block lex_commands:
  const g = """
    grammar G;
    tokens { KEYWORD }
    a : (ID | KEYWORD | COMMENT)* ;
    COMMENT : '#' ~[\n]* -> channel(HIDDEN) ;
    LET : 'let' -> type(KEYWORD) ;
    ID : [a-z]+ ;
    WS : [ \n]+ -> skip ;
    """
  doAssert lex(g, "let x # hi\ny") == @["KEYWORD let", "ID x", "COMMENT # hi (hidden)", "ID y"]

block lex_positions:
  let (_, t, _) = build("grammar G; a : ID* ; ID : ~[ \\n]+ ; WS : [ \\n]+ -> skip ;")
  var d: Diagnostics
  let toks = tokenize[int](t, "ab  é😀 c\n\n  d", d)
  doAssert not d.hasErrors
  var got: seq[(int, int, int, int)]
  for tok in toks: got.add (tok.pos.line, tok.pos.col, tok.start, tok.stop)
  doAssert got == @[(1, 1, 0, 2), (1, 5, 4, 10), (1, 8, 11, 12), (3, 3, 16, 17),
    (3, 4, 17, 17)], $got
  doAssert toks[^1].kind == 0

block lex_empty_input:
  let (_, t, _) = build("grammar G; a : ID ; ID : [a-z]+ ;")
  var d: Diagnostics
  let toks = tokenize[int](t, "", d)
  doAssert toks.len == 1 and toks[0].kind == 0 and toks[0].pos == SourcePos(line: 1, col: 1)

block lex_errors:
  const g = "grammar G; a : (ID | STR)* ; ID : [a-z]+ ; STR : '\"' ~[\"]* '\"' ; WS : ' ' -> skip ;"
  doAssert lex(g, "ab $") == @["ID ab", "1:4: unexpected character '$'"]
  doAssert lex(g, "ab \"cd") == @["ID ab", "1:4: unexpected character '\"'"]
  doAssert lex(g, "a\tb") == @["ID a", "1:2: unexpected character '\\t'"]
  doAssert lex(g, "a \xFFb") == @["ID a", "1:3: invalid UTF-8 byte 0xFF"]
  doAssert lex(g, "a \xC3") == @["ID a", "1:3: invalid UTF-8 byte 0xC3"]
  doAssert lex(g, "a 😀") == @["ID a", "1:3: unexpected character '😀'"]
