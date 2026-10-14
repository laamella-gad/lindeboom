---
id: 6
title: Conflict fallback
status: open
labels: [milestone, parser]
milestone: 6
---

Where a decision is not LL(1), try the conflicting alternatives in order and
warn at generation time. No error recovery (non-goal for v1).

- [ ] Ordered speculative parsing for non-LL(1) decisions
- [ ] Generation-time warning naming the rule and the overlapping tokens
- [ ] Optional memoization
- [ ] Fuzz generated parsers: random input must never crash or hang
- [ ] MiniPy example works end to end
