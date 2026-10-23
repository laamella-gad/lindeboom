---
id: 10
title: "Example: Lua 5.4 parser"
status: done
labels: [example]
depends: [4, 5, 6]
---

Full Lua 5.4 syntax in `examples/lua/lua.ldb`, following §9 of the
[Lua 5.4 manual](https://www.lua.org/manual/5.4/manual.html#9).
A large real-world grammar that is not indentation-based.

- [x] Lexer
  - [x] Names, keywords, all operators
  - [x] Numerals: decimal and hex integers and floats, exponents,
        hex floats (`0x1p4`)
  - [x] Short strings with all escapes (`\z`, `\x`, `\u{...}`, `\ddd`)
  - [x] Long brackets `[[...]]`, `[==[...]==]` and long comments
        `--[[...]]`
  - [x] Shebang line at file start
- [x] Statements: assignment, local (with `<const>` / `<close>`),
      calls, `do`, `while`, `repeat`, `if`/`elseif`/`else`, numeric and
      generic `for`, `function`, `local function`, `return`, `break`,
      `goto`, labels `::name::`, `;`
- [x] Expressions with Lua's 12 precedence levels; `..` and `^`
      right-associative; unary operators bind tighter than everything
      except `^` (`-x^2` is `-(x^2)`)
- [x] `prefixexp` / `var` / `functioncall` chains: `a.b[c]:m(x){t}"s"`
- [x] Table constructors, varargs, method definitions `function a.b:c()`
- [x] Parse all files of the official Lua 5.4 test suite without errors
- [x] `treeRepr` golden tests for a few sample files

Resolved design gaps:

- **Long brackets.** A DFA cannot count the opening `=` run and require
  the same in the closing bracket, so the grammar has one rule per level
  up to six `=` signs (`LONG0`..`LONG6`, and the matching comment
  alternatives). Longer runs need a lexer hook or modes (#21). The body
  `( ~[\]] | ']' '='* )*?` is non-greedy: it stops at the first
  reachable close, including when the body ends in `]=`.
- **Assignment versus call.** No speculation is needed: `varlist`
  parses a `var` and the ALL(*) prediction backs out to `functioncall`
  when there is no `=`.
- **Raw bytes.** Lua strings are byte sequences and the official suite
  contains Latin-1 bytes. A negated set that excludes only ASCII now
  also accepts a single raw non-ASCII byte (`lexgen/nfa.nim`), so such
  input lexes while Unicode-aware negated sets keep their exact
  code-point semantics.
- **Shebang.** Without lexer modes the skip rule cannot be tied to the
  first line; `#!...` and `# ...` are skipped anywhere. The common case
  (first line) is correct and the compromise is noted in the grammar.

Tested against `/tmp/lua-5.4.6-tests/*.lua` (33 files, all parse).
Golden trees are in `tests/grammars/lua/`, checked by `tests/tlua.nim`;
the syntax sample is `examples/lua/sample.lua`.
