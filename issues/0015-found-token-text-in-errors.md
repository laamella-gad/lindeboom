---
id: 15
title: Show the text of the found token in syntax errors
status: wontfix
labels: [diagnostics]
---

A syntax error names the token it found by its kind: `expected NL but found
ID`. For a literal token the kind is the text (`found 'byte'`), but for a
token with a pattern (an identifier, a number) the message doesn't say which
one, so the user has to count columns to find it. With a line holding
`$c000 byte foo bar`, Deflower's own parser says `found 'bar'`.

Want: the found part shows the token's text, `found 'bar'`, perhaps with its
kind (`found ID 'bar'`). Literals, `EOF` and tokens without useful text (a
newline, an indent or dedent from the indentation filter) keep their name;
long texts are shortened.

## To decide

- **Format.** `found 'bar'`, `found ID 'bar'`, or the display name with the
  text (`found a label 'bar'`) once issue 14 is done.
- **Which tokens show text.** All with a pattern, or a per-token choice.

- [ ] `report` in the runtime formats the found token from its text
- [ ] Escape control characters and shorten long texts
- [ ] Tests in `tparsegen`, and the golden outputs updated

## Closing note

Folded into issue 14 (syntax errors as data, with a formatter hook), whose default message shows the found token's text, and whose formatter lets a user word it differently.
