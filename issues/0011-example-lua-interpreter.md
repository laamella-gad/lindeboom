---
id: 11
title: "Example: Lua interpreter (core subset)"
status: open
labels: [example]
depends: [10]
---

Tree-walking interpreter over the parse tree from #10, to show that the
generated tree is usable for a real language.

- [ ] Values: nil, boolean, integer, float, string, table, function
- [ ] Lexical scoping, closures, upvalues
- [ ] All statements and operators, including integer/float rules
- [ ] Multiple returns and varargs
- [ ] Metatables: `__index`, `__newindex`, `__call`, arithmetic metamethods
- [ ] Minimal stdlib: `print`, `type`, `tostring`, `tonumber`, `pairs`,
      `ipairs`, `select`, `error`, `pcall`, `setmetatable`,
      `getmetatable`, parts of `string` and `table`
- [ ] Error messages with line numbers

Out of scope: coroutines, `goto` execution, garbage-collection
metamethods (`__gc`, `__close`), the full stdlib, C API.
