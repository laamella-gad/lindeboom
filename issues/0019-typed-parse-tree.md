---
id: 19
title: Typed parse tree, one node type per rule
status: wontfix
labels: [codegen, usability]
depends: [18]
---

Requested from Deflower's session. Every rule makes the same `Node`, so the
tree API is not type-safe:

- label accessors exist for every label in the grammar and compile on any
  node: `n.at`, `n.label` and `n.file` are accepted on a `number` node and
  return nil;
- `n.has(tkVirtual)` (issue 18) compiles with any node and any token kind;
  a mistake shows only at run time, as `false`.

ANTLR 4 is type-safe here: one context class per rule (`AnnotationContext`)
and per labelled alternative, with accessors only for what that rule
references, each typed: `ctx.at` is a `PlaceContext`, `ctx.VIRTUAL()` a
terminal node, `ctx.parameter()` a list. It also has accessors for
unlabelled rule references and named tokens, not only for labels.

Want: the generated parser gives each rule (and each labelled alternative)
a node type of its own, with accessors only on the types whose rule has the
element:

- labels typed by what they hold: `func at(n: AnnotationNode): PlaceNode`,
  a token for a token label (`label=ID`), a `seq` for a label that repeats
  (`op` in `size`'s `count`);
- an unlabelled optional keyword as a `bool`, so `'virtual'?` needs no
  `virtual=` label: `n.virtual`;
- a rule with labelled alternatives reached through `case` on its kind,
  each alternative's accessors only on its own type (`until` /
  `lengthByte` / `count` for `size`).

Then asking a `number` node for `virtual` is a compile error. The generic
`ParseNode` stays underneath for tools (`treeRepr`, `text`, `pos`, error
nodes, the interpreter).

Try it on Deflower's grammar (`deflower/src/deflower/flo/flo.ldb`: the
`annotation` rule has five flag keywords, one of them `'{'?`) and its tree
walk (`build` in `deflower/src/deflower/flo_reader.nim`).

## To decide

- **Representation.** `distinct Node` per rule: no cost, and the generic
  tree stays as it is, with converters back to `Node`. Or object types
  wrapping a `Node`. Nim object variants are no help for the alternatives:
  a wrong branch is a run-time `FieldDefect`, not a compile error.
- **Alternatives.** Going from `SizeNode` to `UntilNode` after `case
  n.kind` is a checked conversion (`n.asUntil`, asserting the kind), as
  ANTLR's cast to `UntilContext` is. Compile-time safety ends at the `case`;
  is that enough?
- **Names for flag tokens.** A keyword's text can be a Nim keyword
  (`'type'`, `'export'`), a reserved name (`'text'`), collide with a label
  or rule name, or not be an identifier at all (`'{'`). Options: backticks,
  a scheme such as `hasVirtual`, the token's identifier (`hasLBrace`), or
  only tokens with a lexer rule name, as ANTLR (`VIRTUAL : 'virtual' ;`).
- **What gets accessors.** Labels only, or also unlabelled rule references
  (`n.parameter`) and named tokens, as ANTLR, which raises the same
  naming questions.
- **Ambiguous types.** A label on different things in different places
  (`x=a | x=b`, or a block `op=('+' | '-')` against `op=expr`), and
  elements in precedence rules, whose node can be wrapped by an operator
  alternative: fall back to `Node`, or an error?
- **After errors.** A recovered node can miss any element, so accessors
  still return nil (or `false`) for those; say so.
- **Compatibility.** Keep the untyped `Node` accessors next to the typed
  ones, or replace them (which breaks the examples and `grammar/parser.nim`).
- **Issue 17.** ALL(*) changes how decisions are made, not the tree;
  check that nothing here depends on the order.

## Tasks

- [ ] Decide the points above
- [ ] Node types and typed accessors in the code generator; regenerate the
      examples and the ldb front end
- [ ] Port an example (calc_var or json) and `grammar/parser.nim` to the
      typed API, if the untyped one goes
- [ ] Tests: accessors on the wrong node type do not compile (`compiles`
      / `not compiles`), flags, repeated labels, alternatives, recovered
      trees; `docs/DESIGN.md`

## Closing note

Not done. An untyped tree walked with `case n.kind` is the usual Nim style
(the compiler's `PNode`, `NimNode`, `JsonNode`), and Nim has no flow typing,
so typed nodes would stay type-safe only up to each `case` and then need a
checked conversion. The gain does not pay for one type and a set of
accessors per alternative. Issue 18's `has` and `token` remain the way to
find unlabelled tokens.
