---
id: 12
title: Operators missing from "expected" in syntax errors
status: done
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

- [x] Record the continuation tokens of every binary/suffix alternative as
      expected when the loop finds no operator (an operator that binds too
      loosely for `prec` is taken by the enclosing level)
- [x] Same in the interpreter and generated parsers; regenerate the examples
      and the ldb front end
- [x] Tests in `tparsegen` (and the calc_var session in `tgolden`)

Notes:

- The runtime's `expect` is now exported. When the operator loop of a
  precedence rule finds no binary or suffix alternative for the current
  token, it calls `p.expect(...)` with `loopContinuation(r)`, the union of
  all their continuations. Nothing is recorded when an operator is there
  but binds too loosely for `prec`: the enclosing level handles that token.
- Only `calc_var` among the generated parsers has a precedence rule, so it
  is the only regenerated module that changed.
