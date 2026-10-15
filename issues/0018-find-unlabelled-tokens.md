---
id: 18
title: Find unlabelled tokens in a node by kind
status: done
labels: [usability]
---

Only elements with a label get an accessor on the parse tree, so a flag
keyword (`'virtual'? name=ID`) needs a label (`virtual='virtual'?`) or a
search through `n.sons` for the token kind. Deflower's `.flo` grammar has
several such flags (`virtual=`, `banked=`, `selfmod=`, `noreturn=`,
`opensBlock=`).

Giving a lone keyword literal a default label was rejected: keywords make
poor accessor names (Nim keywords such as `if`, `type` and `export`,
reserved names such as `text`), whether a literal gets one would depend on
context the grammar doesn't show, and ANTLR has no implicit labels either.
Instead, as ANTLR's per-token accessors (`ctx.VIRTUAL()`), the runtime finds
tokens by kind:

```nim
func token*(n: Node, kind: TokenKind): Node  # first son that is that token, or nil
func has*(n: Node, kind: TokenKind): bool
```

- [x] `token` and `has` in the runtime
- [x] Tests in `tparsegen` (interpreter) and `tparsecodegen` (generated
      `TokenKind`, with a `token=` label next to it)

Notes:

- Both look at the sons of `n` only, not deeper.
- They are not reserved label names: they take two arguments and a label
  accessor takes one, so a `token=` or `has=` label is just an overload.
