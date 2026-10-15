---
id: 4
title: LL(1) parser generation and parse trees
status: done
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
    nkToken, nkFile, nkIf, nkExprStmt, nkMul, nkAdd, nkName, nkInt, nkParen
  Node* = ref object
    kind*: NodeKind
    label*: NodeLabel    # element label in the parent, lbNone if none
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
        └── NL "\n"
```

## Tasks

- [x] Nullable, FIRST and FOLLOW sets
- [x] LL(1) conflict detection
- [x] Codegen for rules, alternatives and EBNF operators
- [x] `Node` / `NodeKind`, `[]`, `len`, `items`, `treeRepr`, `text`
- [x] Label accessors; absent optionals are `nil`
- [x] `ParseResult` with diagnostics; a parse proc per rule
- [x] Stop at the first syntax error with a clear message (no recovery in v1)
- [x] `lindeboom gen [-o dir]`, writing `<name>_lexer.nim` and `<name>_parser.nim`
- [x] `--standalone`: copy the runtime into the output, no dependency on lindeboom
- [x] `lindeboom parse`: interpret the grammar without codegen
- [x] `lindeboom parse --tree`: print the parse tree as ASCII art
- [x] Golden-file tests for generated code
- [x] Calculator and JSON examples

Notes:

- LL(1) conflicts are errors until fallback parsing (issue 6); left
  recursion is reported with its cycle (`e -> e`) until issue 5. Until then
  `lindeboom check` fails on `examples/minipy`.
- No `nkError`: without recovery a failed parse has no tree (`res.tree` is
  nil) and the error is in `res.diagnostics`.
- `Node` is `ParseNode[NodeKind, NodeLabel, TokenKind]` from the runtime;
  each node stores its label, so `treeRepr` can print `label: ` prefixes.
- Tokens print as their name plus quoted text (`ID "x"`); literal tokens
  print their name only. EOF is never in the tree.
- Expected-token sets in errors are those of the failing decision only,
  e.g. `expected 'b'` after an optional `ID*` loop, as in plain LL parsers.
- Module names start with a lowercase letter (`MiniPy` -> `miniPy_parser`).
  `gen` writes next to the grammar unless `-o` is given; `--standalone`
  writes the runtime to `lindeboom_runtime/` beside the generated modules.
- No `+=`: a label is a list (accessor returns `seq[Node]`) when it can
  label more than one son of a node, i.e. inside `*`/`+` or more than once
  in a sequence. One accessor per name, so a list in one rule is a list in
  all of them.
- `lindeboom parse -r <rule>` picks the start rule (default: the first).
- Generated code under `examples/calc` and `examples/json` is checked in and
  compared by `tests/tgolden.nim`.
