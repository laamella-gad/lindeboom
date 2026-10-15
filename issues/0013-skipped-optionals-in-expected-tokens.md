---
id: 13
title: Skipped optional elements missing from "expected" in syntax errors
status: open
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

- [ ] Record the first set of every optional element, `*`/`+` loop
      continuation and optional block as expected when it is skipped at the
      current token
- [ ] Same in the interpreter (`lindeboom parse`) and generated parsers;
      regenerate the examples and the ldb front end
- [ ] Tests in `tparsegen`, including a skipped optional inside a nested
      rule (`dataType`'s `[` above, after the rule has returned)
