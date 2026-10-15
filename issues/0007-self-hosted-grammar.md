---
id: 7
title: Self-hosted grammar
status: done
labels: [milestone]
milestone: 7
---

- [x] Write the `.ldb` grammar in `.ldb`; regenerate the front end from it

Notes:

- `src/lindeboom/grammar/ldb.ldb` is LL(1) and checks without warnings.
  `ldb_lexer.nim` and `ldb_parser.nim` are generated from it and checked in;
  `tgolden` checks that the current generator, using that front end,
  reproduces them (a fixpoint). The hand-written scanner is gone;
  `grammar/parser.nim` now turns the parse tree into the `Grammar` AST.
- Literal decoding, `<assoc=...>`, lexer commands and indentation settings
  are plain identifiers in the grammar and checked in `parser.nim`, keeping
  their messages. `grammar` and `fragment` are now keywords and can no longer
  name rules.
- So that a grammar still reports every broken rule, generated (and
  interpreted) parsers now recover from syntax errors, ANTLR style (error
  recovery was dropped from the v1 non-goals):
  - A failing rule reports the error, skips tokens until one that can follow
    a rule on the call stack, and returns its partial node with an error node
    (kind 1, `nkError`, holding the skipped tokens) added. A `*`/`+` loop
    that finds a token which can neither continue nor follow it reports and
    skips to one that can.
  - Errors are not reported again until a token has been taken, so one
    mistake gives one message. Speculative attempts never report or recover.
  - Messages list FOLLOW tokens without the end-of-input marker every rule
    gets, so "expected ... or end of input" appears only where it is meant.
  - `ParseResult.tree` is always a tree; it has error nodes if there were
    syntax errors. `lindeboom parse --tree` prints it even then.
  - The lexer skips characters that cannot start a token (one error per run
    of them), and the indentation filter goes on after an error, so parsing
    always runs.
- Syntax errors use generated wording ("expected 'grammar' but found ID");
  labels or `->` inside parentheses are plain syntax errors. Unterminated
  strings and comments report the unexpected character. After a syntax error
  `parseGrammar` builds no `Grammar`.
- A root `config.nims` (replacing `tests/config.nims`) puts `src` on the
  path for every file in the project, so the generated front end and the
  examples import `lindeboom/runtime/...` like every generated parser, and
  `nim check` works on any file.
- `trecovery` checks recovered trees and messages; `tfuzz` checks that
  generated parsers recover exactly as the interpreter does.
- `tfuzz` also fuzzes `.ldb` input against the generated front end, and runs
  1000 mutated grammars through every stage that accepts them.
