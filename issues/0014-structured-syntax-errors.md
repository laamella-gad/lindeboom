---
id: 14
title: Syntax errors as data, with a formatter hook
status: done
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

## Decided

- **The hook's shape:** each diagnostic keeps the error data, and the parse
  function takes an optional formatter (`formatter: proc (e:
  SyntaxErrorInfo): string`). Without one, the default message is built from
  the data.
- **What the data holds:** the found token (kind, text, position), the
  expected token kinds and the whole rule stack, outermost first. Not the
  kind of failure.
- **Lexer errors:** as in ANTLR 4, where the lexer reports to the same
  `syntaxError` listener with no offending token: they go through the same
  hook, with the character and position as data and no found token.

- [x] Error data type in the runtime, kept in `Diagnostics` or alongside it
- [x] The hook in the interpreter and the generated parsers; regenerate the
      examples and the ldb front end
- [x] Default message with the found token's text
- [x] Tests in `tparsegen` (default message and a custom formatter); the
      golden outputs updated; documented in `docs/DESIGN.md`

Depends on issue 13 for complete expected sets: a formatter can only list
what the parser recorded.

Notes:

- `SyntaxErrorInfo` is in `runtime/diagnostics.nim`, since the lexer
  reports with it too: `pos`, `msg` (the default message), `hasToken`,
  `found` (token kind ordinal), `text`, `expected` (kind ordinals, EOF last)
  and `rules` (rule names, outermost first). `Diagnostic.syntax` is a `ref`
  to it, nil for other diagnostics.
- The rule stack is the one when the error is reported, which can be
  shallower than where the farthest failure was recorded (issue 13's
  `dataType` case), as in ANTLR. An error found by `finish` after the start
  rule returned has an empty stack.
- The formatter (`SyntaxErrorFormatter = proc (e: SyntaxErrorInfo):
  string`) is applied after parsing, rewording every diagnostic that has
  syntax data, so lexer and indentation errors go through it too. A lexer
  error's `text` is the character that starts no token; indentation errors
  have no text.
- Generated parsers: `parseX(src, filename = "input", formatter = nil)`, and
  `foundKind(e)` / `expectedKinds(e)` give the kinds as `TokenKind`. The
  interpreter's `interpret` takes the same optional formatter.
- Default message: `found ID 'bar'`. Literals and EOF keep their name, as do
  tokens whose text is only white space (a newline, an indent). The text is
  escaped like the lexer's "unexpected character" (control characters,
  quotes, backslashes, invalid UTF-8 as `\xHH`) and cut to 20 characters
  with `...`. `describeFound` and `quoteText` are exported for formatters
  that want the same.
- Tests: `tparsegen` (default text, the data, a formatter on lexer and
  parser errors), `tparsecodegen` (a formatter on a generated parser using
  `TokenKind`s); golden outputs updated.
