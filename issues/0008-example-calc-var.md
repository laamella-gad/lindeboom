---
id: 8
title: "Example: calc_var"
status: open
labels: [example]
depends: [4, 5, 6]
---

Reimplement plzoo's
[calc_var](https://github.com/andrejbauer/plzoo/tree/master/src/calc_var)
in `examples/calc_var/`: an integer calculator with variables and an
interactive shell.

```
calc_var> x=10
calc_var> 3 * x + 7
37
calc_var> x / 0
Error: division by zero
```

- [ ] `calc_var.ldb`: `toplevel : VARIABLE '=' expression EOF | expression EOF`
- [ ] `+ - * /` left-associative, `*`/`/` above `+`/`-`
- [ ] Unary minus binds tighter than `*` (original uses `%prec UMINUS`);
      in lindeboom, order the `neg` alternative before `mul`
- [ ] Evaluator over the parse tree; errors for unknown variables and
      division by zero
- [ ] REPL reading one line per command
- [ ] Tests from the session in plzoo's `example.calc_var`

Exercises: precedence climbing (#5) and the LL(1) conflict between
`x = e` and an expression starting with a variable (#6).
