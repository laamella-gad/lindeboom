---
id: 20
title: Manual in README.md
status: open
labels: [docs]
---

The project has no `README.md`, so users learn lindeboom from the examples
and the tests. Write the user manual as the top-level `README.md`, and make
it the only documentation: `docs/DESIGN.md` goes, with what is still worth
keeping (goals and non-goals, the architecture, the key decisions) moved
into the manual.

- [ ] What lindeboom is, in a few lines, and a short example: a grammar,
      `lindeboom gen`, and a program that parses with it and walks the tree
- [ ] Installing and building (`nimble build`, `bin/lindeboom`), Nim
      version
- [ ] CLI: `check`, `gen` (`-o`, `--standalone`), `parse` (`-r`, `--tree`,
      `--tokens`)
- [ ] Grammar format, as differences from ANTLR 4 where possible:
  - [ ] `grammar`, `options` (`tabWidth`), `tokens { ... }`
  - [ ] Lexer rules: literals, sets, `~`, `.`, repetition, `-> skip`,
        `-> channel(HIDDEN)`; longest match, then first rule
  - [ ] Parser rules: sequences, `|`, `?` `*` `+`, `~`, `.`, empty
        alternatives, `EOF`
  - [ ] Labels (`name=`), labels on blocks (`op=('+' | '-')`), repeated
        labels, alternative names (`# let`), reserved label names
  - [ ] Left-recursive expression rules: precedence by order,
        `<assoc=right>`
  - [ ] The `indentation` block: `newline`, `indent`, `dedent`,
        `brackets`, `tabs` (`expand` / `strict` / `error`)
  - [ ] What is not supported (actions, predicates, modes, imports,
        indirect left recursion)
- [ ] Prediction: one-token lookahead, trying alternatives in order where
      that is not enough, and the warning for it
- [ ] Generated code: `<name>_lexer.nim` and `<name>_parser.nim`,
      `parseX` per rule, `--standalone`
- [ ] The parse tree: `Node`, `kind` (`nk...`), `sons`, `edge`, `text`,
      `pos`, label accessors, `has` / `token`, `treeRepr`, error nodes
- [ ] Diagnostics: grammar problems, syntax errors and recovery,
      `SyntaxErrorInfo`, the `formatter` hook
- [ ] Pointers to the examples (calc, calc_var, json, minipy, flo) and to
      `issues/`
- [ ] Delete `docs/DESIGN.md`; point open issues that update it (17) at
      `README.md` instead
- [ ] Check every snippet in the manual against the current code
