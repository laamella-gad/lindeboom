---
id: 5
title: Left recursion and precedence
status: done
labels: [parser]
---

Rewrite direct left recursion to precedence climbing.

- [x] Classify alternatives: binary, prefix, suffix, primary
- [x] Earlier alternatives bind tighter; `<assoc=right>`
- [x] Tree keeps one node per labelled alternative
- [x] Report indirect left recursion with the cycle

Notes:

- Follows ANTLR 4: a rule is a precedence rule when an alternative starts
  with a reference to the rule itself. Alternatives that start with it are
  binary (`e op e`) or suffix (`e '(' args ')'`); the others are prefix
  (`'-' e`) or primary. Alternative k of n has precedence n - k.
- The trailing operand of a binary alternative is parsed at precedence + 1,
  or at its own precedence with `<assoc=right>`; a prefix operand at its own
  precedence, so `-a ^ b` is `-(a ^ b)` when `^` comes first. Other
  references to the rule, including from inside it (`'(' e ')'`), start at 0.
- Generated code: `proc ruleE(p: var Parser, prec: int)` with a `case` over
  the primary and prefix alternatives, then a `while` loop over the binary
  and suffix alternatives that checks the precedence and makes the
  expression so far the first son of a new node (`p.wrap`). The label of the
  leading element (`left=e`) goes on that son. `<assoc>` is ignored on other
  alternatives.
- Errors: a precedence rule without a primary or prefix alternative, one
  that can match empty input, and a binary or suffix alternative that can
  match empty input after its leading reference. Conflicts between binary
  and suffix alternatives are reported as "can both continue 'e' with X".
  Where an operator could also follow the expression, the loop takes it
  (greedy), as in ANTLR.
- Left recursion that is indirect or not at the start of an alternative
  (`(e) '+' INT`) is still reported with its cycle.
