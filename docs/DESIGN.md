# Lindeboom — Nim Parser Generator: Design Document

## 1. Summary

`lindeboom` reads a grammar file (`.ldb`, ANTLR 4–style syntax) and generates a
lexer and recursive-descent parser as plain Nim code. Indentation-based
languages like Python are supported directly in the grammar: no hand-written
lexer code is needed to produce `INDENT` / `DEDENT` tokens.

Work is tracked in [`issues/`](../issues/README.md)

## 2. Goals

- Grammar in a separate input file, readable by anyone who knows ANTLR.
- First-class support for indentation-based languages.
- Simple, readable generated Nim code with no dependencies beyond a small
  runtime (which can be copied into the output).
- Good diagnostics, both for grammar problems and for syntax errors.

**Non-goals (v1):** embedded actions/predicates, lexer modes, grammar imports,
indirect left recursion, targets other than Nim, error recovery.

## 3. Grammar format

ANTLR 4 syntax, minus target-language code, plus one new `indentation`
block that declares the newline, indent and dedent tokens and the bracket
pairs inside which line breaks are ignored.

```antlr
grammar MiniPy;

tokens { INDENT, DEDENT }
indentation { newline = NL; indent = INDENT; dedent = DEDENT; brackets = '(' ')'; }

stmt  : 'if' cond=expr ':' body=block   # if
      | expr NL                         # exprStmt
      ;
block : expr NL | NL INDENT stmt+ DEDENT ;
```

## 4. Architecture

```
.ldb ─▶ parse grammar ─▶ checks + analysis ─▶ codegen ─▶ foo_lexer.nim, foo_parser.nim

At runtime:
source ─▶ lexer ─▶ indentation filter ─▶ parser ─▶ parse tree
```

Key decisions:

- **Lexer:** a DFA built from the lexer rules. Fast, and keeps the lexer
  free of hand-written code.
- **Indentation:** handled by a separate token filter rather than in the
  lexer or parser, so one well-tested algorithm serves every indent grammar.
- **Parser:** recursive descent with one-token lookahead. Readable and easy
  to debug. Where a grammar needs more, lindeboom tries alternatives in order
  and warns. Expression rules may be left-recursive, with ANTLR's precedence
  rules.
- **Output:** a generic parse tree in the style of the Nim compiler's own
  `PNode`, processed with `case n.kind`.
- **Tooling:** a CLI to check grammars, generate code, run a grammar on
  input without generating code, and to output an ASCII art parse tree.

