---
id: 13
title: Skipped optional elements missing from "expected" in syntax errors
status: done
labels: [diagnostics]
---

When a rule skips optional elements (`x?`, `x*`, an optional block) and then
fails on the next required token, the error lists only that token, not the
optional ones that could also have come there. A grammar for one-line
statements with several optional parts at the end (Deflower's `.flo` format)
shows it:

```antlr
statement  : annotation NL ;
annotation : at=place type=dataType? name=ID? parameters? ('export' file=ID)? open='{'? ;
dataType   : typeName ('[' size? ']')? ;
```

```
$c000 byte byte
```

gives `expected NL but found 'byte'`, where it should say `expected '[', ID,
'(', 'export', '{' or NL but found 'byte'`: everything that could have gone
on after `byte`.

This is issue 12's problem for optional elements instead of operators: the
check `p.peek in first(x)` that decides to skip `x` doesn't record
`first(x)` as expected, so when parsing fails at that same token the skipped
alternatives are not in the message. The runtime's `expect` already merges
expected sets at the farthest token, so recording them is enough.

- [x] Record the first set of every optional element, `*`/`+` loop
      continuation and optional block as expected when it is skipped at the
      current token
- [x] Same in the interpreter (`lindeboom parse`) and generated parsers;
      regenerate the examples and the ldb front end
- [x] Tests in `tparsegen`, including a skipped optional inside a nested
      rule (`dataType`'s `[` above, after the rule has returned)

Notes:

- Recorded only when an element is skipped, so the hot path (the element
  is there) costs nothing extra:
  - `x?`: an `else: p.expect(first(x))` in generated code, the same in the
    interpreter.
  - `*`/`+` loops: the runtime's `more` expects `first` whenever the loop
    ends.
  - Decisions with an empty alternative (`(a | b | )`, rule alternatives):
    a token that only follows the alternatives expects the union of their
    FIRST sets. Generated `case` statements split such tokens into their own
    `of` branch with a `p.expect(...)`.
- Messages now list every token that could have gone on, as ANTLR does, so
  some are long: after an element in an `.ldb` rule they include `'?'`,
  `'*'`, `'+'`, `'='` (a label) and `'..'` (a range). `tparser` changed
  accordingly.
- `$c000 byte byte` in the `.flo` grammar now gives `expected 'noreturn',
  'export', '{', '[', '(', ID or NL but found 'byte'`. Tokens are listed by
  kind (literals in order of appearance, then named tokens), not in grammar
  order.
- `examples/flo` is a `tfuzz` seed now, so its many optionals are checked to
  give the same messages in generated parsers as in the interpreter.
- Only `json_parser.nim` and `ldb_parser.nim` changed on regeneration; calc
  and calc_var have no `?` or empty alternatives.
