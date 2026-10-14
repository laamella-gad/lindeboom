---
id: 10
title: "Example: Lua 5.4 parser"
status: open
labels: [example]
depends: [4, 5, 6]
---

Full Lua 5.4 syntax in `examples/lua/lua.ldb`, following §9 of the
[Lua 5.4 manual](https://www.lua.org/manual/5.4/manual.html#9).
A large real-world grammar that is not indentation-based.

- [ ] Lexer
  - [ ] Names, keywords, all operators
  - [ ] Numerals: decimal and hex integers and floats, exponents,
        hex floats (`0x1p4`)
  - [ ] Short strings with all escapes (`\z`, `\x`, `\u{...}`, `\ddd`)
  - [ ] Long brackets `[[...]]`, `[==[...]==]` and long comments
        `--[[...]]`
  - [ ] Shebang line at file start
- [ ] Statements: assignment, local (with `<const>` / `<close>`),
      calls, `do`, `while`, `repeat`, `if`/`elseif`/`else`, numeric and
      generic `for`, `function`, `local function`, `return`, `break`,
      `goto`, labels `::name::`, `;`
- [ ] Expressions with Lua's 12 precedence levels; `..` and `^`
      right-associative; unary operators bind tighter than everything
      except `^` (`-x^2` is `-(x^2)`)
- [ ] `prefixexp` / `var` / `functioncall` chains: `a.b[c]:m(x){t}"s"`
- [ ] Table constructors, varargs, method definitions `function a.b:c()`
- [ ] Parse all files of the official Lua 5.4 test suite without errors
- [ ] `treeRepr` golden tests for a few sample files

Design gaps to resolve:

- Long brackets need the closing `]=*]` to have as many `=` as the
  opening one. A DFA cannot count, so either generate one rule per level
  up to a fixed limit, or add a lexer hook for such tokens.
- Assignment versus call statement both start with `prefixexp`; needs
  speculation (#6) or a grammar written as "parse suffixed expression,
  then check".
