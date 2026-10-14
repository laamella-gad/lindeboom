---
id: 3
title: Indentation filter
status: open
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

- [ ] `indentation` block in the grammar front end
- [ ] Indent stack, bracket depth, `atLineStart`
- [ ] Blank and comment-only lines dropped
- [ ] Line joining inside brackets and after `\` continuation
- [ ] Final NEWLINE and DEDENTs at EOF
- [ ] Error on dedent to unknown level
- [ ] `tabs = expand | strict | error`, `tabWidth` option
- [ ] Table-driven tests checked against CPython's `tokenize`
