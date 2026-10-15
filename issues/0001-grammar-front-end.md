---
id: 1
title: Grammar front end and checks
status: done
labels: [milestone, grammar]
milestone: 1
---

Hand-written lexer and recursive-descent parser for `.ldb` files, producing a
grammar AST.

Syntax borrowed from ANTLR 4: lowercase parser rules / Uppercase lexer rules,
`'literals'`, `[sets]`, `~`, `.`, `? * +`, alternative labels (`# name`),
element labels (`x=`), `fragment`, `-> skip` / `channel(HIDDEN)`,
`tokens {}`, `options {}`, `<assoc=right>`. New: the `indentation` block
(see #3).

- [x] Grammar AST types
- [x] `.ldb` lexer and parser for the constructs above
- [x] Checks: undefined/duplicate rules, unused rules (warning), empty loops
- [x] `lindeboom check` command
