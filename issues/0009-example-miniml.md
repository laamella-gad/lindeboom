---
id: 9
title: "Example: MiniML"
status: done
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

- [x] `miniml.ldb`, ported from `lexer.mll` and `parser.mly`
  - [x] Keywords: `int bool true false fun is if then else let`
  - [x] File: `;;`-separated expressions and `let` definitions
  - [x] Operators: `+ -` left, `*` left and tighter; `= <` non-associative
  - [x] `if ... then ... else e` and `fun ... is e` extend as far right
        as possible
  - [x] Application by juxtaposition, left-associative, tighter than
        all operators: `f (n-1)`
  - [x] `- INT` as a negative literal (no general unary minus)
  - [x] Types: `int`, `bool`, `t -> t` right-associative, parentheses
- [x] Type checker
- [x] Evaluator
- [ ] Optional: compiler to plzoo's abstract machine (`compile.ml`,
      `machine.ml`)
- [x] REPL plus loading files; test with plzoo's `example.miniml`

Design gaps to resolve:

- lindeboom has no non-associative operators. Either add `<assoc=none>`
  (error on `a = b = c`) or accept left associativity.
- Application is a left-recursive alternative with an expression, not a
  token, after the left operand (`expr : expr simpleExpr`). Check the
  precedence-climbing rewrite (#5) handles it, using FIRST(simpleExpr) as
  the loop condition.
