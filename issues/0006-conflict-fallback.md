---
id: 6
title: Conflict fallback
status: in-progress
labels: [milestone, parser]
milestone: 6
---

Where a decision is not LL(1), try the conflicting alternatives in order and
warn at generation time. No error recovery (non-goal for v1).

- [x] Ordered speculative parsing for non-LL(1) decisions
- [x] Generation-time warning naming the rule and the overlapping tokens
- [ ] Optional memoization
- [x] Fuzz generated parsers: random input must never crash or hang
- [ ] MiniPy example works end to end

Notes:

- PEG-style ordered choice: where a token can start several alternatives,
  all but the last candidate are tried speculatively (`p.mark` / `p.reset`
  around a `try`), the last runs directly. The same goes for an optional
  element or loop iteration whose start token can also follow it (tried
  first, so greedy), and for binary and suffix alternatives of a precedence
  rule that continue with the same token. LL(1) decisions generate the same
  code as before; the calc and JSON golden files are unchanged.
- Conflicts are warnings now, e.g. "rule 'alt' is not LL(1): alternatives 1
  and 2 can both start with ID; trying them in order" or "...; trying the
  optional element first".
- Syntax errors report the farthest failure over all attempts, with the
  tokens expected there merged: "expected ']' or ':' but found ID".
- Memoization skipped (optional). Backtracking can take exponential time on
  nested ambiguous decisions; no grammar here comes close.
- Loops cannot spin on empty iterations: loop bodies that can match empty
  input are already a grammar error.
- `tests/tfuzz.nim`: 300 seeded random token soups and mutated inputs per
  grammar (features, ambiguous, calc, JSON, MiniPy); the generated parser
  must exit cleanly and agree with the interpreter. Very deep nesting can
  still overflow the stack; there is no depth limit.
- MiniPy end to end waits for the indentation filter (issue 3). Its check
  passes with two warnings and single-line statements parse.
