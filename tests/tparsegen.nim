import std/[assertions, strutils]
import lindeboom/[grammar, lexgen, parsegen]
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

block parsegen_conflicts_are_warnings:
  expectProblem("s : ID INT | ID ID ;",
    "2:14: warning: rule 's' is not LL(1): alternatives 1 and 2 can both start with ID; " &
    "trying them in order")
  expectProblem("s : ('a' | 'a' ID) ;",
    "alternatives 1 and 2 of this block can both start with 'a'; trying them in order")
  expectProblem("s : e 'a' ;\ne : 'a' | ;",
    "rule 'e' is not LL(1): alternatives 1 and 2 can both start with 'a'")
  expectProblem("s : (',' ID)* ','? ;",
    "2:5: warning: rule 's' is not LL(1): ',' can start another iteration of the loop " &
    "or follow it; trying another iteration of the loop first")
  expectProblem("s : ID? ID ;",
    "rule 's' is not LL(1): ID can start the optional element or follow it; " &
    "trying the optional element first")
  expectProblem("s : (ID | INT)? (ID | INT) ;",
    "ID and INT can each start the optional element or follow it")
  doAssert problems(g("s : ID (',' ID)* ';'? ;")).len == 0

block parsegen_backtracking_alternatives:
  let rules = "s : x=ID '=' INT # assign | ID # name | ID ID # pair ;"
  expectTree(rules, "a = 1", """
    assign
    ├── x: ID "a"
    ├── '='
    └── INT "1"
    """)
  expectTree(rules, "a", """
    name
    └── ID "a"
    """)
  # the first alternative that matches wins, even if the rule then fails
  expectError(rules, "a b", "1:3: expected '=' or end of input but found ID")
  # nested blocks, and sons of the failed attempt are dropped
  expectTree("s : 'a' (ID INT | ID ID) ;", "a x y", """
    s
    ├── 'a'
    ├── ID "x"
    └── ID "y"
    """)

block parsegen_backtracking_loops:
  let rules = "s : ID (',' ID)* ','? ;"
  expectTree(rules, "a, b,", """
    s
    ├── ID "a"
    ├── ','
    ├── ID "b"
    └── ','
    """)
  expectTree("s : ('a' ID)? 'a' INT ;", "a 1", """
    s
    ├── 'a'
    └── INT "1"
    """)
  expectTree("s : (ID ',')+ ID ;", "a, b", """
    s
    ├── ID "a"
    ├── ','
    └── ID "b"
    """)

block parsegen_backtracking_operators:
  let rules = "e : e '[' e ']' # index | e '[' e ':' e ']' # slice | ID # name ;"
  expectTree(rules, "a[b:c]", """
    slice
    ├── name
    │   └── ID "a"
    ├── '['
    ├── name
    │   └── ID "b"
    ├── ':'
    ├── name
    │   └── ID "c"
    └── ']'
    """)
  expectProblem(rules, "alternatives 1 and 2 can both continue 'e' with '['; trying them in order")

block parsegen_farthest_error:
  # the error is where parsing got farthest, not where the last attempt failed
  let rules = "s : x=ID '=' ID ';' # assign | ID ';' # name ;"
  expectError(rules, "a = ;", "1:5: expected ID but found ';'")
  expectError(rules, "a b", "1:3: expected '=' or ';' but found ID")

const exprRule = """
e : e '(' ')'                       # call
  | <assoc=right> left=e '^' right=e  # pow
  | '-' e                           # neg
  | left=e op=('*' | '/') right=e   # mul
  | left=e op=('+' | '-') right=e   # add
  | ID                              # name
  | '(' e ')'                       # paren
  ;
"""

proc shape(input: string): string =
  ## The tree of `input` with `exprRule`, as a parenthesized expression.
  let (a, t, _) = analyzed(g(exprRule))
  var d: Diagnostics
  let n = a.interpret(tokenize[int](t, input, d), input, 0, d)
  doAssert not d.hasErrors, $d.items
  proc show(n: Node): string =
    let kind = a.kinds[n.kind]
    case kind
    of "name": n.text
    of "paren": show(n[1])
    of "neg": "(-" & show(n[1]) & ")"
    of "call": show(n[0]) & "()"
    else: "(" & show(n[0]) & " " & n[1].text & " " & show(n[2]) & ")"
  show(n)

block parsegen_precedence:
  doAssert shape("a + b * c") == "(a + (b * c))"
  doAssert shape("a * b + c") == "((a * b) + c)"
  doAssert shape("a - b - c") == "((a - b) - c)"
  doAssert shape("a ^ b ^ c") == "(a ^ (b ^ c))"
  doAssert shape("a * b ^ c") == "(a * (b ^ c))"
  # prefix operands take the operators that bind tighter than the prefix
  doAssert shape("-a ^ b") == "(-(a ^ b))"
  doAssert shape("-a * b") == "((-a) * b)"
  doAssert shape("-a()") == "(-a())"
  doAssert shape("a()() + (b - c)") == "(a()() + (b - c))"

block parsegen_precedence_tree:
  expectTree(exprRule, "a * b()", """
    mul
    ├── left: name
    │   └── ID "a"
    ├── op: '*'
    └── right: call
        ├── name
        │   └── ID "b"
        ├── '('
        └── ')'
    """)
  # an unlabelled rule makes a node of the rule's kind per operator
  expectTree("e : e '+' e | INT ;", "1 + 2", """
    e
    ├── e
    │   └── INT "1"
    ├── '+'
    └── e
        └── INT "2"
    """)
  expectError(exprRule, "a +", "1:4: expected '(', '-' or ID but found end of input")
  expectError(exprRule, "a b", "1:3: expected end of input but found ID")

block parsegen_precedence_errors:
  expectProblem("e : e '+' e ;", "rule 'e' needs an alternative that does not start with 'e'")
  expectProblem("e : e '+' INT | ;", "left-recursive rule 'e' can match empty input")
  expectProblem("e : e '+'? | INT ;",
    "rule 'e': alternative 1 can match empty input after the leading 'e'")
  expectProblem("e : e '+' INT | e '+' ID | INT ;",
    "warning: rule 'e' is not LL(1): alternatives 1 and 2 can both continue 'e' with '+'")
  expectProblem("e : e '+' INT | ID | ID INT ;",
    "rule 'e' is not LL(1): alternatives 2 and 3 can both start with ID")

block parsegen_left_recursion:
  # left recursion through another rule, or not at the start of an
  # alternative, is not rewritten
  expectProblem("e : (e) '+' INT | INT ;", "2:1: error: rule 'e' is left-recursive: e -> e")
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
  doAssert a.kinds == @["token", "error", "if", "token", "x", "y"], $a.kinds
  doAssert a.kindIdents == @["nkToken", "nkError", "nkIf", "nkToken2", "nkX", "nkY"],
    $a.kindIdents
  doAssert a.labels == @["", "t"]
  doAssert a.labelIdents == @["lbNone", "lbT"]
