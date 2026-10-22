## Prediction tests ported from the descriptors of ANTLR 4's runtime test
## suite (runtime-testsuite/resources/org/antlr/v4/test/runtime/descriptors).
## Actions and diagnostics are replaced by parse tree expectations. Each
## grammar runs in the interpreter and as a generated parser.

import std/[assertions, os, strutils]
import lindeboom/[grammar, lexgen, parsegen]
import ./[codegenhelpers, parsehelpers]

type Descriptor = object
  name, grammar: string
  inputs: seq[(string, string)] ## input and the expected tree

const
  idWs = "ID : [a-z]+ ;\nWS : [ \\t\\n]+ -> skip ;\n"
  idIntWs = "ID : [a-z]+ ;\nINT : [0-9]+ ;\n" &
    "WS : [ \\t\\n]+ -> skip ;\n"

let descriptors = [
  Descriptor(name: "FullContextParsing_AmbiguityNoLoop", grammar: """
grammar T;
prog : expr expr | expr ;
expr : '@' | ID '@' | ID ;
ID : [a-z]+ ;
WS : [ \r\n\t]+ -> skip ;
""", inputs: @[("a@", """
prog
├── expr
│   └── ID "a"
└── expr
    └── '@'
""")]),
  Descriptor(name: "FullContextParsing_CtxSensitiveDFA", grammar: """
grammar T;
s : '$' a | '@' b ;
a : e ID ;
b : e INT ID ;
e : INT | ;
""" & idIntWs, inputs: @[("$ 34 abc", """
s
├── '$'
└── a
    ├── e
    │   └── INT "34"
    └── ID "abc"
"""), ("@ 34 abc", """
s
├── '@'
└── b
    ├── e
    ├── INT "34"
    └── ID "abc"
""")]),
  Descriptor(name: "FullContextParsing_SLLSeesEOFInLLGrammar", grammar: """
grammar T;
s : a ;
a : e ID ;
b : e INT ID ;
e : INT | ;
""" & idIntWs, inputs: @[("34 abc", """
s
└── a
    ├── e
    │   └── INT "34"
    └── ID "abc"
""")]),
  Descriptor(name: "FullContextParsing_IfThenElse", grammar: """
grammar T;
s : '{' stat* '}' ;
stat : 'if' ID 'then' stat ('else' ID)? | 'return' ;
""" & idWs, inputs: @[("{ if x then return }", """
s
├── '{'
├── stat
│   ├── 'if'
│   ├── ID "x"
│   ├── 'then'
│   └── stat
│       └── 'return'
└── '}'
"""), ("{ if x then return else foo }", """
s
├── '{'
├── stat
│   ├── 'if'
│   ├── ID "x"
│   ├── 'then'
│   ├── stat
│   │   └── 'return'
│   ├── 'else'
│   └── ID "foo"
└── '}'
"""), ("{ if x then if y then return else foo }", """
s
├── '{'
├── stat
│   ├── 'if'
│   ├── ID "x"
│   ├── 'then'
│   └── stat
│       ├── 'if'
│       ├── ID "y"
│       ├── 'then'
│       ├── stat
│       │   └── 'return'
│       ├── 'else'
│       └── ID "foo"
└── '}'
""")]),
  Descriptor(name: "FullContextParsing_LoopsSimulateTailRecursion", grammar: """
grammar T;
prog : expr_or_assign* ;
expr_or_assign : expr '++' | expr ;
expr : expr_primary ('<-' ID)? ;
expr_primary : '(' ID ')' | ID '(' ID ')' | ID ;
ID : [a-z]+ ;
""", inputs: @[("a(i)<-x", """
prog
└── expr_or_assign
    └── expr
        ├── expr_primary
        │   ├── ID "a"
        │   ├── '('
        │   ├── ID "i"
        │   └── ')'
        ├── '<-'
        └── ID "x"
""")]),
  Descriptor(name: "LeftRecursion_PrecedenceFilterConsidersContext", grammar: """
grammar T;
prog : statement* EOF ;
statement : letterA | statement letterA 'b' ;
letterA : 'a' ;
""", inputs: @[("aa", """
prog
├── statement
│   └── letterA
│       └── 'a'
└── statement
    └── letterA
        └── 'a'
""")]),
  Descriptor(name: "ParserExec_PredictionIssue334", grammar: """
grammar T;
file_ : item (SEMICOLON item)* SEMICOLON? EOF ;
item : A B? ;
SEMICOLON : ';' ;
A : 'a' | 'A' ;
B : 'b' | 'B' ;
WS : [ \r\t\n]+ -> skip ;
""", inputs: @[("a", """
file_
└── item
    └── A "a"
"""), ("a;b", """
input:1:3: error: expected A or end of input but found B 'b'
file_
├── item
│   └── A "a"
└── error
    ├── SEMICOLON ";"
    └── B "b"
""")]),
  Descriptor(name: "ParserExec_AorAPlus", grammar: "grammar T;\na : (ID|ID)+ ;\n" &
    idWs, inputs: @[("a b c", """
a
├── ID "a"
├── ID "b"
└── ID "c"
""")]),
  Descriptor(name: "ParserExec_IfIfElseGreedyBinding", grammar: """
grammar T;
start : statement+ ;
statement : 'x' | ifStatement ;
ifStatement : 'if' 'y' statement ('else' statement|) ;
""" & "WS : [ \\t\\n]+ -> skip ;\n", inputs: @[("if y if y x else x", """
start
└── statement
    └── ifStatement
        ├── 'if'
        ├── 'y'
        └── statement
            └── ifStatement
                ├── 'if'
                ├── 'y'
                ├── statement
                │   └── 'x'
                ├── 'else'
                └── statement
                    └── 'x'
""")])]

proc interpretedTree(d: Descriptor, input: string): string =
  let (a, t, diag) = analyzed(d.grammar)
  doAssert not diag.hasErrors, d.name & ": " & $diag.items
  interpreted(a, t, input)

let tmp = getTempDir() / "lindeboom_tantlr"

for d in descriptors:
  block interpreter:
    for (input, expected) in d.inputs:
      let got = interpretedTree(d, input)
      doAssert got == expected, d.name & " " & input.escape & ":\n" & got

block generated_parsers_match:
  for d in descriptors:
    let dir = tmp / d.name
    createDir(dir)
    let grammarFile = dir / "t.ldb"
    writeFile(grammarFile, d.grammar)
    var inputs: seq[string]
    for (input, _) in d.inputs: inputs.add input
    let c = Case(grammarFile: grammarFile, inputs: inputs)
    discard generate(c, dir, standalone = false)
    let got = runDriver(compile(dir, standalone = false), dir, inputs)
    for i, (input, expected) in d.inputs:
      doAssert got[i] == expected, d.name & " " & input.escape & ":\n" & got[i]
