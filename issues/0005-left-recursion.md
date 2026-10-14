---
id: 5
title: Left recursion and precedence
status: open
labels: [milestone, parser]
milestone: 5
---

Rewrite direct left recursion to precedence climbing.

- [ ] Classify alternatives: binary, prefix, suffix, primary
- [ ] Earlier alternatives bind tighter; `<assoc=right>`
- [ ] Tree keeps one node per labelled alternative
- [ ] Report indirect left recursion with the cycle
