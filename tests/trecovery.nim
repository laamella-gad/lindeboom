## Error recovery: after a syntax error the parser reports it, skips tokens
## into an error node and carries on, so one parse reports several errors.

import std/[assertions, strutils]
import ./parsehelpers

const grammar = """
grammar G;
prog : stmt* EOF ;
stmt : ID '=' expr ';'   # assign
     | 'print' expr ';'  # print
     ;
expr : expr '+' expr     # add
     | ID                # name
     | INT               # num
     | '(' expr ')'      # paren
     ;
ID : [a-z]+ ;
INT : [0-9]+ ;
WS : ' ' -> skip ;
"""

proc expectRecovered(input, expected: string) =
  let got = recovered(grammar, input)
  doAssert got == expected.dedent, "\n" & got

block recovery_missing_operand:
  # the rule that fails gets an error node; its caller goes on
  expectRecovered("a = 1 + ; print b;", """
    prog
    ├── assign
    │   ├── ID "a"
    │   ├── '='
    │   ├── add
    │   │   ├── num
    │   │   │   └── INT "1"
    │   │   ├── '+'
    │   │   └── error
    │   └── ';'
    └── print
        ├── 'print'
        ├── name
        │   └── ID "b"
        └── ';'
    1:9: expected '(', ID or INT but found ';'
    """)

block recovery_missing_token:
  # a missing token ends the rule; the next statement parses normally
  expectRecovered("a = (1 + 2; print a;", """
    prog
    ├── assign
    │   ├── ID "a"
    │   ├── '='
    │   ├── paren
    │   │   ├── '('
    │   │   ├── add
    │   │   │   ├── num
    │   │   │   │   └── INT "1"
    │   │   │   ├── '+'
    │   │   │   └── num
    │   │   │       └── INT "2"
    │   │   └── error
    │   └── ';'
    └── print
        ├── 'print'
        ├── name
        │   └── ID "a"
        └── ';'
    1:11: expected ')' but found ';'
    """)

block recovery_one_error_per_statement:
  expectRecovered("print 1 print 2 print 3;", """
    prog
    ├── print
    │   ├── 'print'
    │   ├── num
    │   │   └── INT "1"
    │   └── error
    ├── print
    │   ├── 'print'
    │   ├── num
    │   │   └── INT "2"
    │   └── error
    └── print
        ├── 'print'
        ├── num
        │   └── INT "3"
        └── ';'
    1:9: expected ';' but found 'print'
    1:17: expected ';' but found 'print'
    """)

block recovery_loop_skips_tokens:
  # a loop skips tokens that can neither continue nor follow it
  expectRecovered("a = 1; ) ) print 2;", """
    prog
    ├── assign
    │   ├── ID "a"
    │   ├── '='
    │   ├── num
    │   │   └── INT "1"
    │   └── ';'
    ├── error
    │   ├── ')'
    │   └── ')'
    └── print
        ├── 'print'
        ├── num
        │   └── INT "2"
        └── ';'
    1:8: expected 'print', ID or end of input but found ')'
    """)

block recovery_end_of_input:
  expectRecovered("a = 1", """
    prog
    └── assign
        ├── ID "a"
        ├── '='
        ├── num
        │   └── INT "1"
        └── error
    1:6: expected ';' but found end of input
    """)

block recovery_no_cascade:
  # errors before the parser takes a token again are not reported
  let got = recovered(grammar, "a = ( ( + ; print 1;")
  doAssert got.count("expected") == 1, got

block recovery_lexer_errors_continue:
  # characters that start no token are skipped, and parsing goes on
  let got = recovered(grammar, "a = 1 $; print 2 &;")
  doAssert got.endsWith("1:7: unexpected character '$'\n1:18: unexpected character '&'\n"), got
  doAssert "\n└── print" in got, got
