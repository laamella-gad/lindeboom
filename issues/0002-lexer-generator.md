---
id: 2
title: Lexer generator
status: done
labels: [lexer]
---

Compile lexer rules to a minimized DFA over UTF-8 bytes.

- [x] Character sets and UTF-8 range splitting
- [x] Thompson NFA construction, fragments inlined
- [x] Subset construction and DFA minimization
- [x] Longest match; literal tokens before lexer rules; file-order ties
- [x] `-> skip`, `-> channel(HIDDEN)`
- [x] Emit DFA as `const` tables
- [x] `lindeboom parse --tokens`

Notes:

- Non-greedy loops follow ANTLR: once a token's thread reaches its accept
  state, lower-priority threads of that token that went through a non-greedy
  decision are dropped (`'/*' .*? '*/'` stops at the first `*/`).
- Lexer rules cannot be recursive, since rule references are inlined.
- A token that can never win gets a warning naming the token that beats it.
