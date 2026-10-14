---
id: 4
title: LL(1) parser generation and parse trees
status: open
labels: [milestone, parser]
milestone: 4
---

One proc per rule, choosing alternatives by one-token lookahead, building a
generic parse tree.

## Generated API

```nim
import miniPy_parser

let res = parseFile(src, filename = "x.py")
for d in res.diagnostics: echo d    # x.py:3:9: error: expected ':' but found NL
echo res.tree.treeRepr()
```

Every rule can be used as a start rule (`parseExpr(src)`).

## Tree

Same shape as the Nim compiler's `PNode` and `std/macros`' `NimNode`: one
node type, a `kind` per rule or alternative label, and a list of children.

```nim
type
  NodeKind* = enum
    nkToken, nkError, nkFile, nkIf, nkExprStmt, nkMul, nkAdd, nkName, nkInt, nkParen
  Node* = ref object
    kind*: NodeKind
    tok*: Token          # when kind == nkToken
    sons*: seq[Node]

proc `[]`*(n: Node, i: int): Node
proc len*(n: Node): int
iterator items*(n: Node): Node
proc treeRepr*(n: Node): string
```

Element labels become inline accessors (`proc cond*(n: Node): Node`); absent
optional elements are `nil`. `n.text` returns the source text of a node.
Users process the tree with `case n.kind`:

```nim
proc eval(n: Node): int =
  case n.kind
  of nkInt: parseInt(n.text)
  of nkAdd: eval(n.left) + eval(n.right)
  of nkMul: eval(n.left) * eval(n.right)
  of nkParen: eval(n[1])
  else: raiseAssert $n.kind
```

## ASCII art tree

`treeRepr` and `lindeboom parse --tree` print the tree like this, for
`if x: y + 1`:

```
file
└── if
    ├── 'if'
    ├── cond: name
    │   └── ID "x"
    ├── ':'
    └── body: block
        ├── add
        │   ├── left: name
        │   │   └── ID "y"
        │   ├── op: '+'
        │   └── right: int
        │       └── INT "1"
        └── NL
```

## Tasks

- [ ] Nullable, FIRST and FOLLOW sets
- [ ] LL(1) conflict detection
- [ ] Codegen for rules, alternatives and EBNF operators
- [ ] `Node` / `NodeKind`, `[]`, `len`, `items`, `treeRepr`, `text`
- [ ] Label accessors; absent optionals are `nil`
- [ ] `ParseResult` with diagnostics; a parse proc per rule
- [ ] Stop at the first syntax error with a clear message (no recovery in v1)
- [ ] `lindeboom gen [-o dir]`, writing `<name>_lexer.nim` and `<name>_parser.nim`
- [ ] `--standalone`: copy the runtime into the output, no dependency on lindeboom
- [ ] `lindeboom parse`: interpret the grammar without codegen
- [ ] `lindeboom parse --tree`: print the parse tree as ASCII art
- [ ] Golden-file tests for generated code
- [ ] Calculator and JSON examples
