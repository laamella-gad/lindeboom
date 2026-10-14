---
id: 2
title: Lexer generator
status: open
labels: [milestone, lexer]
milestone: 2
---

Compile lexer rules to a minimized DFA over UTF-8 bytes.

- [ ] Character sets and UTF-8 range splitting
- [ ] Thompson NFA construction, fragments inlined
- [ ] Subset construction and DFA minimization
- [ ] Longest match; literal tokens before lexer rules; file-order ties
- [ ] `-> skip`, `-> channel(HIDDEN)`
- [ ] Emit DFA as `const` tables
- [ ] `lindeboom parse --tokens`
