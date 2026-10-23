---
id: 22
title: Semantic predicates
status: open
labels: [parser, grammar]
depends: [17]
---

Support ANTLR 4 semantic predicates (`{ ... }?`) so a grammar can reject an
alternative based on parser state or the tokens seen so far. Today target code
in a grammar is rejected, and there is no way to express context-sensitive
choices that the ALL(*) lookahead alone cannot settle.

The main design question is how predicates work in both generated parsers and
the interpreter without allowing arbitrary actions.

- [ ] Decide the supported predicate expression and its access to parser state,
      current token, and labels already matched.
- [ ] Parse predicates in parser rules, and decide whether lexer predicates are
      in scope. Keep actions out of scope.
- [ ] Represent predicates in the AST with their source position and text.
- [ ] Check placement and types, and reject statements or unsupported Nim.
- [ ] Evaluate predicates during prediction: prune failing alternatives before
      committing, without side effects, and reuse cached results where safe.
- [ ] Emit predicates in generated parsers at the point where their alternative
      is considered.
- [ ] Give the interpreter an equivalent evaluation path, or reject predicates
      there with a clear message. `lindeboom parse` must not silently disagree
      with generated parsers.
- [ ] Test gated alternatives, predicates interacting with ALL(*) decisions and
      error recovery, lexer predicates if supported, and generated/interpreter
      parity.
- [ ] Document the syntax and limitations, and remove semantic predicates from
      the unsupported list.

## Sample grammars

Real grammars use predicates for exactly the choices ALL(*) cannot settle.
They show the range of state a predicate may need, from lookahead only to a
symbol table:

- [LuaParser.g4](https://github.com/antlr/grammars-v4/blob/master/lua/LuaParser.g4)
  — the simplest case: a lookahead-only predicate separating a call
  statement from an assignment target when both start with `NAME`:

  ```antlr
  prefixexp
      : { this.IsFunctionCall() }? NAME ( '[' exp ']' | '.' NAME )*
      | functioncall ( '[' exp ']' | '.' NAME )*
      | '(' exp ')' ( '[' exp ']' | '.' NAME )*
      ;
  ```

  `IsFunctionCall()` only inspects `LT(1)` and `LT(2)`; it reads no parse
  state. A token/lookahead predicate covers this one. See #23 for why this
  rule looks the way it does.

- [CParser.g4](https://github.com/antlr/grammars-v4/blob/master/c/CParser.g4)
  — gated alternatives for the typedef/identifier problem, which need a
  declaration symbol table built up while parsing:

  ```antlr
  unaryExpression
      : ...
      | {!this.IsSomethingOfTypeName()}? 'sizeof' unaryExpression
      | {this.IsSomethingOfTypeName()}? 'sizeof' '(' typeName ')'
      ;
  castExpression
      : {this.IsCast()}? '(' typeName ')' castExpression
      | unaryExpression
      ;
  declaration
      : declarationSpecifiers
        ( {this.IsInitDeclaratorList()}? initDeclaratorList | ) ';'
      ;
  ```

  This is the upper bound: if predicates are restricted to the current
  token and labels already matched, these rules need rewriting instead.

- [Python3Parser.g4](https://github.com/antlr/grammars-v4/blob/master/python/python3/Python3Parser.g4)
  — two alternatives with the same token prefix but different meanings:

  ```antlr
  literal_expr
      : signed_number { this.CannotBePlusMinus() }?
      | complex_number
      | strings
      | ...
      ;
  pattern_capture_target
      : name { this.CannotBeDotLpEq() }?
      ;
  ```

  The Python target implements these helpers as stubs, but the placement
  and the shape of the generated check are still representative.

- [STLexer.g4](https://github.com/antlr/grammars-v4/blob/master/stringtemplate/STLexer.g4)
  — lexer predicates selecting delimiters and mode switches, e.g.
  `LDELIM : . { this.isLDelim() }? -> mode(Inside)` and
  `LBRACE : LBrace { this.startsSubTemplate() }? -> mode(SubTemplate)`.
  If lexer predicates stay out of scope, this grammar shows what that
  costs.
