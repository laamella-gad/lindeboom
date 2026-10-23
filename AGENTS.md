# Agent Guidelines for Lindeboom

Lindeboom is a parser generator written in Nim. It translates `.ldb` grammars into lexers and recursive-descent parsers using Adaptive LL(*) (ALL(*)) prediction and precedence climbing.

## Build and Test Commands

- **Build binary**:
  ```bash
  nimble build
  ```
  Produces the `bin/lindeboom` CLI.

- **Run all tests**:
  ```bash
  nimble test
  ```
  Nimble automatically discovers and executes every `tests/t*.nim` file, stopping on the first failure.

- **Run tests in release mode** (faster for fuzz and descriptor stress suites):
  ```bash
  nimble test -d:release
  ```

- **Run a single test suite**:
  ```bash
  nim c -r tests/tparsegen.nim
  nim c -r tests/tantlr.nim
  ```

## Repository Structure

- `src/lindeboom/`:
  - `grammar/`: AST definition (`ast.nim`), checks (`checks.nim`), vocabulary (`vocabulary.nim`), and the self-hosted grammar parser/lexer (`ldb_parser.nim`, `ldb_lexer.nim`).
  - `lexgen/`: Regular expression compiler, NFA/DFA conversion, and lexer code generator.
  - `parsegen/`: Grammar analysis (`analysis.nim` building the Thompson-style ATN), code generation (`codegen.nim`), and tree-walking interpreter (`interpreter.nim`).
  - `runtime/`: Shared runtime for parsers (`parser.nim` with GSS, DFA prediction cache, and SLL/LL fallback) and lexers (`lexer.nim`).
- `tests/`:
  - All test files are named `tests/t*.nim`.
  - Do not add non-test runner scripts starting with `t` in `tests/`, as `nimble test` globs `tests/t*.nim`.
- `examples/`: Example grammars and generated parsers (`calc`, `calc_var`, `json`, `flo`, `minipy`).
- `issues/`: Markdown issue tracking files (`NNNN-short-slug.md`) with YAML frontmatter.

## Golden Files

Generated files in `examples/` and the front end's `ldb_lexer.nim` / `ldb_parser.nim` are validated by `tests/tgolden.nim`. If codegen changes deliberately:
1. Regenerate examples: `lindeboom gen <grammar.ldb>`
2. For self-hosting (`ldb.ldb`), generate twice so the second run uses the parser generated in the first.
