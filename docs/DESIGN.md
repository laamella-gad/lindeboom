# npg — Nim Parser Generator: Design Document

## 1. Summary

`npg` reads a grammar file (`.npg`, ANTLR 4–style syntax) and generates a
lexer and recursive-descent parser as plain Nim code. Indentation-based
languages like Python are supported directly in the grammar: no hand-written
lexer code is needed to produce `INDENT` / `DEDENT` tokens.

**Non-goals (v1):** embedded actions/predicates, lexer modes, grammar imports,
indirect left recursion, targets other than Nim.

## 2. Grammar format

```antlr
grammar MiniPy;

tokens { INDENT, DEDENT }

indentation {
  newline  = NL;
  indent   = INDENT;
  dedent   = DEDENT;
  brackets = '(' ')', '[' ']';
}

file    : stmt* EOF ;
stmt    : 'if' cond=expr ':' body=block   # if
        | expr NL                         # exprStmt
        ;
block   : expr NL
        | NL INDENT stmt+ DEDENT
        ;
expr    : expr op=('*' | '/') expr        # mul
        | expr op=('+' | '-') expr        # add
        | ID                              # name
        | INT                             # int
        | '(' expr ')'                    # paren
        ;

ID      : [a-zA-Z_] [a-zA-Z_0-9]* ;
INT     : [0-9]+ ;
NL      : '\r'? '\n' ;
WS      : [ \t]+          -> skip ;
COMMENT : '#' ~[\r\n]*    -> skip ;
CONT    : '\\' '\r'? '\n' -> skip ;   // line continuation
```

Borrowed from ANTLR: lowercase parser rules / Uppercase lexer rules,
`'literals'`, `[sets]`, `~`, `.`, `? * +`, alternative labels (`# name`),
element labels (`x=`, `xs+=`), `fragment`, `-> skip` / `channel(HIDDEN)`,
`tokens {}`, `options {}`, `<assoc=right>`. Unsupported ANTLR constructs give a
clear "not supported" error.

The only new construct is the `indentation` block, which turns on the
indentation filter (§3.2). `tabs = expand | strict | error` (in the block)
controls tab handling; `tabWidth` defaults to 8.

## 3. Design

### 3.1 Pipeline

```
.npg ─▶ parse grammar ─▶ checks + analysis ─▶ codegen ─▶ foo_lexer.nim, foo_parser.nim

At runtime:
source ─▶ DFA lexer ─▶ indentation filter ─▶ parser ─▶ parse tree
```

- **Checks:** undefined/duplicate rules, unused rules (warning), indirect left
  recursion, empty loops, FIRST/FOLLOW sets, LL(1) conflicts.
- **Lexer:** rules → NFA → minimized DFA over UTF-8 bytes, emitted as `const`
  tables. Longest match wins; ties go to the earlier rule. Parser literals
  like `'if'` rank before all lexer rules, so keywords beat `ID`.
- **Parser:** one proc per rule, choosing alternatives by one-token lookahead.
  - Where the grammar isn't LL(1), that decision falls back to trying
    alternatives in order (optionally memoized), and `npg` warns.
  - Direct left recursion (`expr : expr '+' expr`) becomes precedence
    climbing: earlier alternatives bind tighter, left-associative unless
    `<assoc=right>`.
- **Error recovery:** single-token deletion/insertion, else skip to the
  rule's FOLLOW set (or `NEWLINE`/`DEDENT` in indent languages).

### 3.2 Indentation filter

Sits between lexer and parser. State: a stack of indent widths (starts `[0]`),
bracket depth, and `atLineStart` (true at file start and after an emitted
newline).

1. Newline token: drop it if inside brackets or `atLineStart` (blank or
   comment-only line); otherwise emit it and set `atLineStart`.
2. First other token while `atLineStart`: compare its column `w` to the stack
   top. Greater: push, emit `INDENT`. Smaller: pop and emit `DEDENT` until
   equal; no match is an error. Then emit the token.
3. Bracket tokens adjust depth.
4. At EOF: emit a final newline if needed, then one `DEDENT` per open level.

Indentation is only measured after a newline the filter *emitted*, so
`\`-continuations (skipped by the lexer) and line breaks inside brackets need
no special cases.

### 3.3 Generated API

```nim
import miniPy_parser

let res = parseFile(src, filename = "x.py")
for d in res.diagnostics: echo d    # x.py:3:9: error: expected ':' but found NL
echo res.tree.dump()
```

- The tree uses one `Node` type with a `NodeKind` per rule/label.
- Each rule also gets a `distinct` wrapper type, so labelled accessors don't
  clash: `proc cond(n: IfNode): ExprNode`.
- Every rule can be used as a start rule (`parseExpr(src)`).

## 4. CLI

```
npg gen   MiniPy.npg [-o dir] [--standalone]   # write parser code
npg check MiniPy.npg                           # report grammar problems
npg parse MiniPy.npg input.py [--tokens|--tree] # interpret grammar, no codegen
```

`--standalone` copies the small runtime into the output so it has no
dependency on `npg`. Later: an `npgGrammar("x.npg")` macro that generates the
parser at compile time.

## 5. Milestones

1. Grammar front end and checks (`npg check`).
2. Lexer generator (`npg parse --tokens`).
3. Indentation filter.
4. LL(1) parser generation and parse trees.
5. Left recursion and precedence.
6. Conflict fallback and error recovery.
7. Self-hosted `.npg` grammar; compile-time macro.

Testing: unit tests per stage, a table of indentation cases checked against
CPython's `tokenize`, golden files for generated code, and fuzzing the
generated parsers.
