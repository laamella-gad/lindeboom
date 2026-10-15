import std/[assertions, os]
import ./helpers

const header = "grammar G;\n"

proc check(body, expected: string) =
  let src = header & body
  doAssert src.hasMessage(expected), body & " -> " & $messages(src)

block checks_examples_are_clean:
  for f in walkFiles(currentSourcePath().parentDir / ".." / "examples" / "*" / "*.ldb"):
    let msgs = messages(readFile(f))
    doAssert msgs.len == 0, f & " -> " & $msgs

block checks_declarations:
  check("a : 'x' ; a : 'y' ;", "duplicate rule 'a' (first defined at line 2)")
  check("tokens { A, A } a : A ;", "duplicate token 'A'")
  check("tokens { lower } a : 'x' ;", "token name 'lower' must start with an uppercase letter")
  check("tokens { A } a : A ; A : 'a' ;", "conflicts with the token declared")
  check("fragment a : 'x' ;", "fragment rule 'a' must be a lexer rule")
  check("a : 'x' ; EOF : 'e' ;", "'EOF' is predefined")

block checks_options:
  check("options { tabWidth = 0; } a : 'x' ;", "'tabWidth' must be a positive integer")
  check("options { colour = red; } a : 'x' ;", "warning: unknown option 'colour'")
  check("options { tabWidth = 2; tabWidth = 4; } a : 'x' ;", "duplicate option 'tabWidth'")

block checks_references:
  check("a : b ;", "undefined rule 'b'")
  check("a : B ;", "undefined token 'B'")
  check("a : F ; fragment F : 'f' ;", "fragment 'F' cannot be used in a parser rule")
  check("a : X ; X : a ;", "parser rule 'a' cannot be used in lexer rule 'X'")
  check("a : X ; X : Y ;", "undefined lexer rule 'Y'")
  check("a : X ; X : EOF ;", "'EOF' cannot be used in lexer rules")
  check("tokens { T } a : X T ; X : T ;", "token 'T' has no lexer rule")
  doAssert ok(header & "tokens { T } a : X T EOF ; X : 'x' -> type(T) ;")

block checks_placement:
  check("a : [a-z] ;", "character sets are only allowed in lexer rules")
  check("a : 'a'..'z' ;", "character ranges are only allowed in lexer rules")
  check("a : 'x'*? ;", "non-greedy operators are only allowed in lexer rules")
  check("a : 'x' -> skip ;", "lexer commands are only allowed in lexer rules")
  check("a : X ; X : 'x' # lab ;", "alternative labels are not allowed in lexer rules")
  check("a : X ; X : <assoc=right> 'x' ;", "'<assoc>' is not allowed in lexer rules")
  check("a : X ; X : y='x' ;", "element labels are not allowed in lexer rules")
  check("a : X ; X : ~'ab' ;", "'~' in lexer rules applies only to")
  check("a : ~(b) ; b : 'x' ;", "'~' in parser rules applies only to")
  doAssert ok(header & "a : ~('x' | X) ; X : ~[a-z] ~('a' | 'b'..'c') ;")

block checks_lexer_commands:
  check("a : X ; X : 'x' -> channel(OTHER) ;", "unknown channel 'OTHER'")
  check("a : X ; X : 'x' -> type(NOPE) ;", "undefined token 'NOPE' in 'type()'")
  check("a : X ; X : F ; fragment F : 'f' -> skip ;", "lexer commands are not allowed on fragment rules")
  check("a : X ; X : 'x' -> jump ;", "unknown lexer command 'jump'")

block checks_labels:
  check("a : 'x' # one | 'y' ;", "this alternative needs a label too")
  check("a : 'x' # one | 'y' # one ;", "duplicate alternative label 'one'")

block checks_empty_matches:
  check("a : X ; X : 'x'? ;", "lexer rule 'X' can match empty input")
  check("a : b* ; b : 'x'? ;", "loop body can match empty input")
  check("a : ('x'?)+ ;", "loop body can match empty input")
  check("a : X ; X : F* ; fragment F : 'f'? ;", "loop body can match empty input")
  # an empty fragment is fine; only tokens must consume input
  doAssert ok(header & "a : X ; X : 'x' F ; fragment F : 'f'? ;")

block checks_unused:
  check("a : 'x' ; b : 'y' ;", "warning: rule 'b' is not reachable from start rule 'a'")
  check("a : 'x' ; fragment F : 'f' ;", "warning: fragment 'F' is never used")
  check("tokens { T } a : 'x' ;", "warning: token 'T' is declared but never used")

block checks_indentation:
  const ind = "tokens { INDENT, DEDENT }\n"
  check(ind & "indentation { indent = INDENT; dedent = DEDENT; } a : INDENT DEDENT ;",
    "'indentation' block needs a 'newline' setting")
  check(ind & "indentation { newline = F; indent = INDENT; dedent = DEDENT; } a : 'x' ; fragment F : 'f' ;",
    "'newline' must name a lexer rule that is not a fragment")
  check("indentation { newline = NL; indent = INDENT; dedent = DEDENT; } a : NL ; NL : '\\n' ;",
    "'indent' token 'INDENT' is not declared; add it to 'tokens { }'")
  check("tokens { INDENT } indentation { newline = NL; indent = INDENT; dedent = NL; } a : NL ; NL : '\\n' ;",
    "'dedent' token 'NL' must be declared in 'tokens { }', not as a lexer rule")
  check(ind & "indentation { newline = NL; indent = INDENT; dedent = INDENT; } a : NL ; NL : '\\n' ;",
    "'indent' and 'dedent' must be different tokens")
  check(ind & "indentation { newline = NL; indent = INDENT; dedent = DEDENT; tabs = mixed; } a : NL ; NL : '\\n' ;",
    "'tabs' must be expand, strict or error")
  check(ind & "indentation { newline = NL; indent = INDENT; dedent = DEDENT; width = 4; } a : NL ; NL : '\\n' ;",
    "unknown indentation setting 'width'")

block checks_lexer_recursion:
  check("a : A ; A : '(' A? ')' ;", "lexer rule 'A' refers to itself")
  check("a : A ; A : '(' B ')' ; fragment B : A | 'x' ;", "lexer rule 'A' refers to itself")
  doAssert ok(header & "a : A B ; A : C C ; B : C ; fragment C : 'c' ;")
