---
id: 14
title: Syntax errors as data, with a formatter hook
status: open
labels: [diagnostics]
---

A syntax error is reported as a finished string: `expected NL but found ID`.
It names tokens by their rule name (`NL`, `ID`) or literal (`'byte'`), and
the found token only by its kind, so a pattern token doesn't say which text
it was. Rule names are written for the grammar, not for the user of the
language. Deflower's hand-written `.flo` parser says `expected a label,
export, '{' or the end of the line, found 'bar'`, and should not get worse by
moving to a generated one.

ANTLR has no way to name tokens in the grammar either. The program that uses
the parser rewrites the messages: an error listener (`syntaxError`) gets the
offending token, the expected token set and the default message, and an
error strategy can override `getTokenErrorDisplay`. lindeboom follows that:
the grammar stays plain ANTLR, and the messages are the user's code.

Want:
- each syntax error is kept as data: the found token (kind, text, position),
  the expected token kinds, and the rule being parsed;
- the parse function takes an optional formatter that turns that data into
  the message; without one, the default message is built from it as now;
- the default message shows the text of a found token that has a pattern,
  `found ID 'bar'` (literals, `EOF` and tokens without useful text, like a
  newline or an indent, keep their name; control characters are escaped and
  long texts shortened). This was issue 15.

A user's formatter maps the token kinds to its own names, e.g. `tkNL` to `the
end of the line`, and words the message as it likes.

## To decide

- **The hook's shape.** A proc parameter of `parseX` (`formatter: proc (e:
  SyntaxErrorInfo): string`), a field on the parser state, or no hook: the
  diagnostics keep the data and the user formats them afterwards.
- **What the data holds.** Whether the rule stack (not only the innermost
  rule) and the kind of failure (mismatch, missing token, no viable
  alternative) are part of it, as ANTLR's exceptions tell them apart.
- **Lexer errors.** Whether `unexpected character '@'` goes through the same
  hook, with the character as data.

- [ ] Error data type in the runtime, kept in `Diagnostics` or alongside it
- [ ] The hook in the interpreter and the generated parsers; regenerate the
      examples and the ldb front end
- [ ] Default message with the found token's text
- [ ] Tests in `tparsegen` (default message and a custom formatter); the
      golden outputs updated; documented in `docs/DESIGN.md`

Depends on issue 13 for complete expected sets: a formatter can only list
what the parser recorded.
