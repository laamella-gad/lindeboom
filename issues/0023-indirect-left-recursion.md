---
id: 23
title: Indirect left recursion
status: open
labels: [grammar, parser]
depends: [5]
---

Support mutually left-recursive rules. Direct left recursion is handled by
precedence climbing; indirect cycles are currently reported as errors:

```antlr
a : b 'x' | 'z' ;
b : a 'y' | 'w' ;
```

ANTLR 4 also rejects indirect left recursion, so this is an extension rather
than parity. It should either transform each left-recursive strongly connected
component into a form the existing precedence-climbing analysis understands, or
use a general seed-growing algorithm.

- [ ] Detect left-recursive strongly connected components instead of only the
      first cycle.
- [ ] Transform or evaluate indirect cycles while preserving the original
      alternative order and tree shape.
- [ ] Preserve labels, alternative labels, and `<assoc=right>` through the
      transformation.
- [ ] Handle nullable and optional leading elements without changing the
      existing errors for left recursion after consuming input.
- [ ] Avoid uncontrolled grammar expansion; report a clear error for patterns
      that cannot be rewritten.
- [ ] Compare interpreted and generated parsers on mutual recursion, longer
      cycles, precedence combinations, and recoverable syntax errors.
- [ ] Add fuzz seeds and edge-case grammars, and document the new support in
      `README.md`.

## Sample grammars

ANTLR rejects indirect left recursion, so no grammar written for ANTLR can
contain it. The samples below are yacc/BNF grammars of real languages, which
are also the grammars users will try to port.

- **Lua 5.4** ([manual §9](https://www.lua.org/manual/5.4/manual.html#9)) —
  the case that matters for #10:

  ```antlr
  exp          : ... | prefixexp | tableconstructor | exp binop exp | unop exp ;
  prefixexp    : var | functioncall | '(' exp ')' ;
  var          : Name | prefixexp '[' exp ']' | prefixexp '.' Name ;
  functioncall : prefixexp args | prefixexp ':' Name args ;
  ```

  `prefixexp -> var -> prefixexp` and
  `prefixexp -> functioncall -> prefixexp` are two 2-cycles; `exp` is also
  directly left-recursive and reaches `prefixexp`, so the transform has to
  work with precedence climbing and preserve the `<assoc=right>` of `^`
  and `..`.

  The grammars-v4 port avoids the cycles by hand:
  [LuaParser.g4](https://github.com/antlr/grammars-v4/blob/master/lua/LuaParser.g4)
  inlines the suffix chain into `prefixexp` and `functioncall`, and gates
  one `prefixexp` alternative with a predicate (see #22). It is a good
  reference for the shape the transform should produce.

- **PHP** ([zend_language_parser.y](https://github.com/php/php-src/blob/master/Zend/zend_language_parser.y))
  — a longer cycle for dereference chains such as `$a->b()[0]()`:

  ```c
  variable : callable_variable | static_member
           | array_object_dereferenceable T_OBJECT_OPERATOR property_name
           | ... ;
  callable_variable : simple_variable
           | array_object_dereferenceable '[' optional_expr ']'
           | ... | function_call ;
  function_call : name argument_list | ...
           | callable_expr argument_list ;
  callable_expr : callable_variable | '(' expr ')' | ... ;
  array_object_dereferenceable : fully_dereferenceable | constant ;
  fully_dereferenceable : variable | '(' expr ')' | ... ;
  ```

  The cycle is longer than two and passes through rules with different
  shapes, which is what "detect the first cycle" and a naive precedence
  rewrite miss.

- **Ruby** ([parse.y](https://github.com/ruby/ruby/blob/master/parse.y)) —
  the ternary operator is expressed indirectly, and the obvious fix is a
  direct, right-associative rule:

  ```c
  arg     : ... | ternary | primary ;
  ternary : arg '?' arg '\n'? ':' arg ;
  ```

  The same file has `p_as : p_expr tASSOC p_variable | p_alt` with
  `p_expr : p_as` for pattern matching.

- **PostgreSQL** ([gram.y](https://github.com/postgres/postgres/blob/master/src/backend/parser/gram.y))
  — a 2-cycle around set operations, where a rule that also starts with a
  terminal has alternatives that start with a nonterminal:

  ```c
  select_clause : simple_select | select_with_parens ;
  simple_select : SELECT ...
                | select_clause UNION set_quantifier select_clause
                | select_clause INTERSECT set_quantifier select_clause
                | select_clause EXCEPT set_quantifier select_clause ;
  ```

  Preserving alternative order matters: `SELECT ...` must still win over a
  set operation when both are feasible.
