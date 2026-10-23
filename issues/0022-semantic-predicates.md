---
id: 22
title: Semantic predicates
status: open
labels: [parser, grammar]
depends: [17]
---

Support semantic predicates so a grammar can reject an alternative based on
the tokens seen so far. Today target code in a grammar is rejected, and there
is no way to express context-sensitive choices that the ALL(*) lookahead
alone cannot settle. ANTLR 4's `{ ... }?` is the reference for the use cases,
but arbitrary target code is not the surface (see Design).

The main design question is how predicates work in both generated parsers and
the interpreter without allowing arbitrary actions.

- [ ] Decide the supported predicate expression: a fixed, side-effect-free
      language over the current token, `next`/`prev`, and labels already
      matched (see Design).
- [ ] Parse predicates in parser rules, and decide whether lexer predicates are
      in scope. Keep actions out of scope.
- [ ] Represent predicates in the AST with their source position and text.
- [ ] Check placement and types, and reject anything outside the expression
      language.
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

## Design

The goal is a predicate that is data, not code: no Nim, no method calls, no
host callbacks, and nothing the interpreter cannot evaluate. That keeps
generated parsers and `lindeboom parse` on one path and makes predicates
side-effect free and cacheable.

A predicate is a boolean expression over facts the parser already has:

- the current token: type, text, or `EOF`;
- `next` and `look(k)`: type or text of the token `k` ahead;
- `prev`: the previous token, for lexer-ish decisions in parser rules;
- labels already matched in the rule, by type or text.

Sketch:

```antlr
prefixexp : [next != OP] NAME ( '[' exp ']' | '.' NAME )* | ... ;
literal   : signed_number [next != '+' and next != '-'] | ... ;
```

No assignment, no calls, no arbitrary member access. If a check cannot be
written in this language it is a grammar error, not an escape hatch.

What this covers:

- Lua's `IsFunctionCall()` is `LT(2) != OP`; a `next` guard is enough.
- Python 3's `CannotBePlusMinus` / `CannotBeDotLpEq` are stubs in the
  reference grammar and are really next-token checks.
- C's `IsSomethingOfTypeName` / `IsCast` need a typedef symbol table. Keep
  symbol-table predicates out of scope rather than import actions; such
  grammars need rewriting (parse the ambiguity, resolve it outside the
  parser) or stay unsupported.

Fallbacks that are not predicates:

- #6 ordered speculation already resolves some same-prefix choices.
- Lexer-y decisions (regex vs division, heredoc versus `<<`) belong in #21
  state, not here.
- Resolving an ambiguous parse in a host-side post-pass is possible, but it
  is a separate API and a tree-shape problem; not part of this issue.

Rejected: named predicates bound by the host program. They keep the grammar
code-free, but `lindeboom parse` can no longer run the grammar standalone and
"generated and interpreted agree" is only testable when the hooks exist.

Lexer predicates are out of scope for now: the state they test (`isLDelim`,
`opened`) is either configuration or lexer state, which #21 handles. Adding
the same expression language to the lexer runtime is a separate decision.

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
