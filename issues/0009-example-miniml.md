---
id: 9
title: "Example: MiniML"
status: open
labels: [example]
depends: [4, 5, 6]
---

Reimplement plzoo's
[miniml](https://github.com/andrejbauer/plzoo/tree/master/src/miniml)
in `examples/miniml/`: an eager, statically typed functional language
with integers, booleans, recursive functions and top-level `let`.

```ocaml
let fact =
  fun f (n : int) : int is
    if n = 0 then 1 else n * f (n-1) ;;

fact 10 ;;
```

- [ ] `miniml.ldb`, ported from `lexer.mll` and `parser.mly`
  - [ ] Keywords: `int bool true false fun is if then else let`
  - [ ] File: `;;`-separated expressions and `let` definitions
  - [ ] Operators: `+ -` left, `*` left and tighter; `= <` non-associative
  - [ ] `if ... then ... else e` and `fun ... is e` extend as far right
        as possible
  - [ ] Application by juxtaposition, left-associative, tighter than
        all operators: `f (n-1)`
  - [ ] `- INT` as a negative literal (no general unary minus)
  - [ ] Types: `int`, `bool`, `t -> t` right-associative, parentheses
- [ ] Type checker
- [ ] Evaluator
- [ ] Optional: compiler to plzoo's abstract machine (`compile.ml`,
      `machine.ml`)
- [ ] REPL plus loading files; test with plzoo's `example.miniml`

Design gaps to resolve:

- lindeboom has no non-associative operators. Either add `<assoc=none>`
  (error on `a = b = c`) or accept left associativity.
- Application is a left-recursive alternative with an expression, not a
  token, after the left operand (`expr : expr simpleExpr`). Check the
  precedence-climbing rewrite (#5) handles it, using FIRST(simpleExpr) as
  the loop condition.
