import std/[assertions, strutils]
import ./parsehelpers

const lexer = """
ID : [a-z]+ ;
INT : [0-9]+ ;
WS : [ \n]+ -> skip ;
"""

proc g(rules: string): string = "grammar G;\n" & rules & "\n" & lexer

proc expectTree(rules, input, expected: string, rule = "") =
  let got = tree(g(rules), input, rule)
  doAssert got == expected.dedent, "\n" & got

proc expectError(rules, input, expected: string, rule = "") =
  let got = tree(g(rules), input, rule)
  doAssert got == expected, got

proc expectProblem(rules, expected: string) =
  let got = problems(g(rules))
  var found = false
  for m in got:
    if expected in m: found = true
  doAssert found, $got

block parsegen_sequence_and_labels:
  expectTree("s : 'let' name=ID '=' value=INT ;", "let x = 1", """
    s
    ├── 'let'
    ├── name: ID "x"
    ├── '='
    └── value: INT "1"
    """)

block parsegen_rule_refs_and_alt_labels:
  expectTree("s : a a ;\na : ID # name | INT # int ;", "x 1", """
    s
    ├── name
    │   └── ID "x"
    └── int
        └── INT "1"
    """)

block parsegen_ebnf:
  let rules = "s : 'a'? ID* ('b' INT)+ ;"
  expectTree(rules, "b 1", """
    s
    ├── 'b'
    └── INT "1"
    """)
  expectTree(rules, "a x y b 1 b 2", """
    s
    ├── 'a'
    ├── ID "x"
    ├── ID "y"
    ├── 'b'
    ├── INT "1"
    ├── 'b'
    └── INT "2"
    """)
  expectError(rules, "a x", "1:4: expected 'b' but found end of input")

block parsegen_nested_alternatives:
  let rules = "s : ('a' ID | 'b' INT | ) ';' ;"
  expectTree(rules, "b 2;", """
    s
    ├── 'b'
    ├── INT "2"
    └── ';'
    """)
  expectTree(rules, ";", """
    s
    └── ';'
    """)
  expectError(rules, "x", "1:1: expected 'a', 'b' or ';' but found ID")

block parsegen_token_sets:
  expectTree("s : op=('+' | '-') ~';' . ';' ;", "+ x 1;", """
    s
    ├── op: '+'
    ├── ID "x"
    ├── INT "1"
    └── ';'
    """)
  expectError("s : op=('+' | '-') ;", "x", "1:1: expected '+' or '-' but found ID")
  expectError("s : ~ID ;", "x", "1:1: expected INT but found ID")

block parsegen_list_labels:
  expectTree("s : xs=ID (',' xs=ID)* ;", "a, b", """
    s
    ├── xs: ID "a"
    ├── ','
    └── xs: ID "b"
    """)

proc listLabels(rules: string): seq[string] =
  let (a, _, _) = analyzed(g(rules))
  for k, name in a.labels:
    if a.labelIsList[k]: result.add name

block parsegen_list_labels_are_inferred:
  doAssert listLabels("s : x=ID y=INT? ;") == @[]
  doAssert listLabels("s : x=ID | x=INT ;") == @[]
  doAssert listLabels("s : (x=ID | x=INT) ';' ;") == @[]
  doAssert listLabels("s : x=ID x=INT ;") == @["x"]
  doAssert listLabels("s : x=ID (',' y=ID)* ;") == @["y"]
  doAssert listLabels("s : (x=ID)+ ;") == @["x"]
  doAssert listLabels("s : x=(ID INT) y=(ID | INT) ;") == @["x"]
  doAssert listLabels("s : x=ID? x=INT? ;") == @["x"]
  # one accessor per name, so a list in one rule is a list in all
  doAssert listLabels("s : x=ID t ;\nt : x=INT* ;") == @["x"]
  # a label inside a labelled block takes precedence
  doAssert listLabels("s : x=(y=ID INT) ;") == @[]

block parsegen_label_on_block:
  expectTree("s : x=(ID | INT) y=(ID INT) ;", "1 a 2", """
    s
    ├── x: INT "1"
    ├── y: ID "a"
    └── y: INT "2"
    """)

block parsegen_empty_rule:
  expectTree("s : 'a' e 'b' ;\ne : ;", "a b", """
    s
    ├── 'a'
    ├── e
    └── 'b'
    """)

block parsegen_nullable_alternative_uses_follow:
  # `e` can be empty, so 'b' after it selects the empty alternative
  expectTree("s : e 'b' ;\ne : 'a' | ;", "b", """
    s
    ├── e
    └── 'b'
    """)

block parsegen_eof:
  expectTree("s : ID EOF ;", "x", """
    s
    └── ID "x"
    """)
  expectError("s : ID ;", "x y", "1:3: expected end of input but found ID")
  expectError("s : ID ID ;", "x", "1:2: expected ID but found end of input")

block parsegen_any_rule_is_a_start_rule:
  let rules = "s : 'let' e ;\ne : ID | INT ;"
  expectTree(rules, "42", """
    e
    └── INT "42"
    """, rule = "e")
  expectError(rules, "42", "1:1: expected 'let' but found INT")

block parsegen_lexer_error:
  expectError("s : ID ;", "x$", "1:2: unexpected character '$'")

block parsegen_hidden_tokens_are_ignored:
  let src = "grammar G;\ns : ID ID ;\nID : [a-z]+ ;\nC : '#' [a-z]* -> channel(HIDDEN) ;\nWS : ' '+ -> skip ;\n"
  doAssert tree(src, "a #c b") == "s\n├── ID \"a\"\n└── ID \"b\"\n", tree(src, "a #c b")

block parsegen_tree_text_escapes:
  let src = "grammar G;\ns : S ;\nS : '\"' ~'\"'* '\"' ;\n"
  doAssert tree(src, "\"a\nb\"") == "s\n└── S \"\\\"a\\nb\\\"\"\n"

block parsegen_conflicts:
  expectProblem("s : ID INT | ID ID ;",
    "2:14: error: rule 's' is not LL(1): alternatives 1 and 2 can both start with ID")
  expectProblem("s : ('a' | 'a' ID) ;",
    "alternatives 1 and 2 of this block can both start with 'a'")
  expectProblem("s : e 'a' ;\ne : 'a' | ;",
    "rule 'e' is not LL(1): alternatives 1 and 2 can both start with 'a'")
  expectProblem("s : (',' ID)* ','? ;",
    "2:5: error: rule 's' is not LL(1): ',' can start another iteration of the loop or follow it")
  expectProblem("s : ID? ID ;",
    "rule 's' is not LL(1): ID can start the optional element or follow it")
  expectProblem("s : (ID | INT)? (ID | INT) ;",
    "ID and INT can each start the optional element or follow it")
  doAssert problems(g("s : ID (',' ID)* ';'? ;")).len == 0

block parsegen_left_recursion:
  expectProblem("e : e '+' INT | INT ;", "2:1: error: rule 'e' is left-recursive: e -> e")
  expectProblem("a : b ID ;\nb : c? a | INT ;\nc : '-' ;",
    "rule 'a' is left-recursive: a -> b -> a")
  expectProblem("a : b ID ;\nb : c? a | INT ;\nc : '-' ;",
    "rule 'b' is left-recursive: b -> a -> b")
  doAssert problems(g("a : '(' a ')' | ID ;")).len == 0

block parsegen_reserved_labels:
  expectProblem("s : text=ID ;", "label 'text' clashes with the parse tree API")

block parsegen_node_kinds:
  let (a, _, _) = analyzed(g("s : x # if | y # token ;\nx : ID ;\ny : t=INT ;\ntoken : ID ;"))
  # a label shares the node kind of a rule with the same name
  doAssert a.kinds == @["token", "if", "token", "x", "y"], $a.kinds
  doAssert a.kindIdents == @["nkToken", "nkIf", "nkToken2", "nkX", "nkY"], $a.kindIdents
  doAssert a.labels == @["", "t"]
  doAssert a.labelIdents == @["lbNone", "lbT"]
