---
id: 17
title: ALL(*) prediction for non-LL(1) decisions
status: open
labels: [parser]
depends: [6]
---

Replace the ordered backtracking of issue 6 with Adaptive LL(*) prediction,
as in ANTLR 4: Parr, Harwell and Fisher, "Adaptive LL(*) Parsing: The Power
of Dynamic Analysis", OOPSLA 2014 (`docs/allstar.pdf`).

Today a decision that one token cannot settle tries its alternatives in
order (`p.mark` / `p.reset` around a `try`) and takes the first that parses,
PEG style. That has the problems the paper lists:

- Ordered choice commits to the first alternative that parses, even when
  its caller then fails. With `s : a 'z' ; a : 'x' | 'x' 'y' ;` the input
  `x y z` gives "expected 'z' but found 'y'".
- Nested ambiguous decisions can take exponential time (issue 6 skipped
  memoization).
- A real ambiguity (`α | α`) is silently resolved; it cannot be reported.

ALL(*) predicts instead of parsing speculatively. At a decision,
`adaptivePredict` runs one subparser per alternative over an augmented
transition network (ATN) of the grammar, in lockstep over the remaining
input, until only one alternative survives; then the parser runs that
alternative once, for real. It handles every non-left-recursive grammar
(direct left recursion is already rewritten by issue 5), with ambiguities
resolved in favour of the lowest alternative, as now.

Outline from the paper (section 3 and 5):

- **ATN:** one submachine per parser rule, edges for tokens, rule calls and
  ε; built from the analysed grammar.
- **SLL prediction with a DFA cache:** each decision gets a lookahead DFA
  whose states are sets of ATN configurations (state, alternative, call
  stack), built on demand by subset construction over the ATN and reused for
  later predictions, so most decisions become a DFA walk.
- **Full LL fallback:** when SLL prediction finds a conflict, retry the
  decision with the real parser call stack (`p.rules` already has it); stop
  when one alternative is left, or report an ambiguity and pick the lowest.
- **Precedence rules:** binary and suffix alternatives of a precedence rule
  that continue with the same token need the precedence as a predicate in
  prediction (ANTLR's precedence predicates), so the climbing loop keeps its
  meaning.

Generated parsers stay readable: LL(1) decisions keep their `case p.peek`,
and only the other decisions call `p.predict(decision)`. The ATN is emitted
as data in the generated module; prediction lives in the runtime, shared by
the interpreter and generated parsers.

## Decided

- **Replace:** ALL(*) for every non-LL(1) decision; the backtracking code
  (`mark` / `reset` / `commit` speculation) goes.
- **Warnings:** the "is not LL(1) ... trying them in order" warnings are
  removed, as ANTLR 4 does not warn about non-LL(1) decisions. No ambiguity
  reporting mode for now.
- **Prediction mode:** as ANTLR 4's default (`PredictionMode.LL`): SLL
  prediction per decision, falling back to full LL with the call stack when
  SLL finds a conflict. No built-in two-stage parse; in ANTLR that is a
  pattern the user sets up (SLL with a bail-out strategy, then a re-parse).
- **DFA cache:** shared, in a module-level variable of the generated parser
  (one per interpreter `Analysis`), kept across parses, as ANTLR 4. Not
  thread-safe; parsing from several threads needs a lock.

## Tasks

- [ ] ATN construction from the analysed grammar
- [ ] `adaptivePredict` in the runtime: SLL with DFA cache, LL fallback,
      conflict and ambiguity detection, precedence predicates
- [ ] Interpreter and code generator use it for non-LL(1) decisions;
      regenerate the examples and the ldb front end
- [ ] Remove the backtracking code and the "is not LL(1)" warnings, and the
      tests that expect them (`tparsegen`, `tcli`)
- [ ] Syntax errors from prediction (no viable alternative) report the
      farthest token reached with the tokens expected there, and recovery
      (issue 7) keeps working
- [ ] Tests: the paper's `stat` grammar (figure 1), its stack-sensitive
      `S → xB | yC, B → Aa, C → Aba, A → b | ε`, the `x y z` case above,
      `tests/grammars/ambiguous.ldb`, MiniPy; a nested ambiguous grammar
      that is exponential with backtracking runs in linear time; `tfuzz`
      keeps interpreter and generated parsers in agreement
- [ ] `docs/DESIGN.md` updated (the parser bullet in section 4)
