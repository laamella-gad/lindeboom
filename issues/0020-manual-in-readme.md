---
id: 20
title: Manual in README.md
status: done
labels: [docs]
---

The project has no `README.md`, so users learn lindeboom from the examples
and the tests. Write the user manual as the top-level `README.md`, and make
it the only documentation: `docs/DESIGN.md` goes, with what is still worth
keeping (goals and non-goals, the architecture, the key decisions) moved
into the manual.

- [x] What lindeboom is, in a few lines, and a short example: a grammar,
      `lindeboom gen`, and a program that parses with it and walks the tree
- [x] Installing and building (`nimble build`, `bin/lindeboom`), Nim
      version
- [x] CLI: `check`, `gen` (`-o`, `--standalone`), `parse` (`-r`, `--tree`,
      `--tokens`)
- [x] Grammar format, as differences from ANTLR 4 where possible:
  - [x] `grammar`, `options` (`tabWidth`), `tokens { ... }`
  - [x] Lexer rules: literals, sets, `~`, `.`, repetition, `-> skip`,
        `-> channel(HIDDEN)`; longest match, then first rule
  - [x] Parser rules: sequences, `|`, `?` `*` `+`, `~`, `.`, empty
        alternatives, `EOF`
  - [x] Labels (`name=`), labels on blocks (`op=('+' | '-')`), repeated
        labels, alternative names (`# let`), reserved label names
  - [x] Left-recursive expression rules: precedence by order,
        `<assoc=right>`
  - [x] The `indentation` block: `newline`, `indent`, `dedent`,
        `brackets`, `tabs` (`expand` / `strict` / `error`)
  - [x] What is not supported (actions, predicates, modes, imports,
        indirect left recursion)
- [x] Prediction: one-token lookahead, trying alternatives in order where
      that is not enough, and the warning for it
- [x] Generated code: `<name>_lexer.nim` and `<name>_parser.nim`,
      `parseX` per rule, `--standalone`
- [x] The parse tree: `Node`, `kind` (`nk...`), `sons`, `edge`, `text`,
      `pos`, label accessors, `has` / `token`, `treeRepr`, error nodes
- [x] Diagnostics: grammar problems, syntax errors and recovery,
      `SyntaxErrorInfo`, the `formatter` hook
- [x] Pointers to the examples (calc, calc_var, json, minipy, flo) and to
      `issues/`
- [x] Delete `docs/DESIGN.md`; point open issues that update it (17) at
      `README.md` instead
- [x] Check every snippet in the manual against the current code

Notes:

- The quick start, the grammar snippets, the keyword label, `type()`, the
  formatter and `--standalone` were tried with the current build.
- The parts of `docs/DESIGN.md` still worth keeping are the "Design"
  section at the end of the manual. `docs/allstar.pdf` stays, for issue 17.
- Not covered on purpose: the runtime procs the generated parsers use
  (`mark`, `match`, `recover`, ...) and the library API used by the CLI
  (`loadGrammar`, `analyze`, ...); they are internal.
