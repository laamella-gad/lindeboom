---
id: 8
title: "Example: calc_var"
status: done
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

- [x] `calc_var.ldb`: `toplevel : VARIABLE '=' expression EOF | expression EOF`
- [x] `+ - * /` left-associative, `*`/`/` above `+`/`-`
- [x] Unary minus binds tighter than `*` (original uses `%prec UMINUS`);
      in lindeboom, order the `neg` alternative before `mul`
- [x] Evaluator over the parse tree; errors for unknown variables and
      division by zero
- [x] REPL reading one line per command
- [x] Tests from the session in plzoo's `example.calc_var`

Exercises: precedence climbing (#5) and the LL(1) conflict between
`x = e` and an expression starting with a variable (#6).

Notes:

- The grammar is `grammar CalcVar`, so the generated modules are
  `calcVar_lexer.nim` and `calcVar_parser.nim`; the program is
  `calc_var.nim`. The two `toplevel` alternatives are labelled
  `definition` and `evaluation`; `lindeboom check` warns that they conflict
  on VARIABLE, and the definition is tried first.
- Arithmetic wraps around on overflow and division truncates, like OCaml's
  `int`; a numeral too large for an `int` is an error rather than a crash.
- The banner and prompt are shown only when stdin is a terminal, so piped
  sessions print just the results. Syntax errors print as
  `Error: column N: ...`.
- `tgolden` checks the generated modules and runs plzoo's session plus
  precedence, associativity and error cases; `tfuzz` fuzzes the grammar.
