---
id: 12
title: Operators missing from "expected" in syntax errors
status: open
labels: [diagnostics]
depends: [5]
---

After an operand of a left-recursive (precedence) rule, a syntax error does
not list the operators that could continue the expression. With
`examples/calc_var`:

```
calc_var> x y
Error: column 3: expected '=' or end of input but found VARIABLE
```

should say `expected '=', '*', '/', '+', '-' or end of input`.

The loop that extends an expression with binary and suffix alternatives
checks `p.peek in continuation(...)` but never records those sets as
expected, so when parsing later fails at the same token they are not in the
message. Both the interpreter (`runRuleBody`) and generated code
(`genRule`'s precedence loop) have the problem.

- [ ] Record the continuation tokens of every binary/suffix alternative as
      expected when the loop stops (including those rejected by `prec`)
- [ ] Same in the interpreter and generated parsers; regenerate the examples
      and the ldb front end
- [ ] Tests in `tparsegen` (and the calc_var session in `tgolden`)
