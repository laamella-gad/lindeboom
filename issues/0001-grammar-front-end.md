---
id: 1
title: Grammar front end and checks
status: open
labels: [milestone, grammar]
milestone: 1
---

Hand-written lexer and recursive-descent parser for `.ldb` files, producing a
grammar AST.

Syntax borrowed from ANTLR 4: lowercase parser rules / Uppercase lexer rules,
`'literals'`, `[sets]`, `~`, `.`, `? * +`, alternative labels (`# name`),
element labels (`x=`, `xs+=`), `fragment`, `-> skip` / `channel(HIDDEN)`,
`tokens {}`, `options {}`, `<assoc=right>`. New: the `indentation` block
(see #3).

- [ ] Grammar AST types
- [ ] `.ldb` lexer and parser for the constructs above
- [ ] Clear "not supported" errors for actions, predicates, modes, imports
- [ ] Checks: undefined/duplicate rules, unused rules (warning), empty loops
- [ ] `lindeboom check` command
