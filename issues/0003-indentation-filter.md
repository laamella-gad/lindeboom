---
id: 3
title: Indentation filter
status: done
labels: [milestone, indentation]
milestone: 3
---

Token filter between lexer and parser that emits NEWLINE / INDENT / DEDENT.
Enabled by the grammar's `indentation` block:

```antlr
tokens { INDENT, DEDENT }

indentation {
  newline  = NL;
  indent   = INDENT;
  dedent   = DEDENT;
  brackets = '(' ')', '[' ']';
  tabs     = expand;            // expand | strict | error; tabWidth defaults to 8
}

CONT : '\\' '\r'? '\n' -> skip ;   // line continuation, no special support needed
```

## Algorithm

State: a stack of indent widths (starts `[0]`), bracket depth, and
`atLineStart` (true at file start and after an emitted newline).

1. Newline token: drop it if inside brackets or `atLineStart` (blank or
   comment-only line); otherwise emit it and set `atLineStart`.
2. First other token while `atLineStart`: compare its column `w` to the stack
   top. Greater: push, emit `INDENT`. Smaller: pop and emit `DEDENT` until
   equal; no match is an error. Then emit the token.
3. Bracket tokens adjust depth.
4. At EOF: emit a final newline if needed, then one `DEDENT` per open level.

Indentation is only measured after a newline the filter *emitted*, so
`\`-continuations (skipped by the lexer) and line breaks inside brackets need
no special cases.

## Tasks

- [x] `indentation` block in the grammar front end
- [x] Indent stack, bracket depth, `atLineStart`
- [x] Blank and comment-only lines dropped
- [x] Line joining inside brackets and after `\` continuation
- [x] Final NEWLINE and DEDENTs at EOF
- [x] Error on dedent to unknown level
- [x] `tabs = expand | strict | error`, `tabWidth` option
- [x] Table-driven tests checked against CPython's `tokenize`

Notes:

- The filter lives in the lexer runtime (`filterIndentation`) and runs inside
  `tokenize` when `LexerTables.indentation` is enabled, so generated lexers,
  `lindeboom parse` and the interpreter all use it. Generated lexers without
  an `indentation` block are unchanged.
- Hidden-channel tokens pass through and do not count as tokens on a line.
- Indent and dedent tokens are empty and sit at the position of the token
  that follows; the final newline and dedents sit at end of file.
- Indentation is the code points between the start of the line and its first
  token, with tabs expanded to `tabWidth`. `strict` also measures with tabs as
  one column and requires the same comparison, as CPython does with 8 and 1.
  `error` rejects tabs in indentation; default is `expand`.
- Error messages follow CPython: "unindent does not match any outer
  indentation level", "inconsistent use of tabs and spaces in indentation".
- A bracket literal that no parser rule uses is a grammar error. Closing
  brackets never take the depth below zero; mismatched pairs are left to the
  parser.
- `tests/tindent.nim`: the `strict` cases were checked against CPython 3.12
  `tokenize` (NL and COMMENT dropped, ENDMARKER as EOF).
