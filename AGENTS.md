# Agent Guidelines for Lindeboom

Lindeboom is a Nim parser generator. It reads an ANTLR-4-style `.ldb` grammar and emits a DFA lexer plus a recursive-descent parser using ALL(*) prediction and precedence climbing. `README.md` is the language/tool manual; tests are the behavior spec.

## Build and test

- Requires Nim >= 2.2.10; no other dependencies.
- `nimble build` produces the CLI at `bin/lindeboom` and first regenerates every parser from its `.ldb` grammar (all of `examples/` plus the self-hosted front end). It bootstraps with a temporary build of the checked-in front end, so the final binary compiles the regenerated sources.
- `nimble test` regenerates the parsers the same way before running every `tests/t*.nim`, stopping at the first failure. The suite compiles generated parsers and example programs with `nim c`, so a run is slow; it needs no services and no prior `nimble build`.
- Use `nimble test -d:release` for the expensive fuzz and descriptor suites.
- Run one suite with `nim c -r tests/tparsegen.nim`. Root `config.nims` puts `src` on the path and sends test/example binaries to `bin/tests/` and `bin/examples/<name>/`, so no extra `--path:src` is needed. Suites that use `examples/` generated modules (`tgolden`, `tcli`) need `nimble build` or `nimble test` to have generated them first.
- Test files must be named `tests/t*.nim`; shared helpers such as `codegenhelpers.nim` use other names.
- `tests/tgolden.nim` is the generated-code snapshot test; `tests/tcli.nim` builds `src/lindeboom.nim` into `bin/lindeboom_test` itself.

## Layout and data flow

- CLI entrypoint: `src/lindeboom.nim`. Facade modules: `src/lindeboom/{grammar,lexgen,parsegen}.nim`.
- Pipeline: `loadGrammar` (parse + checks) -> `buildVocabulary` -> `buildLexer` -> `analyze` -> `genLexerModule` / `genParserModule`, or the interpreter. The interpreter and generated parsers must produce identical trees and diagnostics; many tests assert this.
- `grammar/`: `.ldb` AST, checks, vocabulary, and the hand-written AST conversion in `parser.nim`; `lexgen/`: regex -> NFA -> DFA -> codegen; `parsegen/`: ATN analysis, codegen, interpreter; `runtime/`: shared lexer, parser, and diagnostics used by generated code.
- Generated modules import `lindeboom/runtime/...`. In-repo builds get this through `config.nims`; external builds need `--path:<repo>/src` or `lindeboom gen --standalone`.
- Generated module names lowercase only the first letter of the grammar name: `CalcVar` -> `calcVar_parser.nim`, `MiniPy` -> `miniPy_parser.nim`.
- The `.ldb` front end is self-hosted from `src/lindeboom/grammar/ldb.ldb`; `ldb_lexer.nim` and `ldb_parser.nim` are generated.

## Generated and golden files

- Never hand-edit `*_lexer.nim` or `*_parser.nim`; `nimble build` regenerates them, or use `bin/lindeboom gen <grammar.ldb>` for one grammar.
- Generated example modules are gitignored, not checked in. `src/lindeboom/grammar/ldb_lexer.nim` and `ldb_parser.nim` are the one deliberate exception: they are the self-hosted bootstrap needed to build a clean checkout.
- `tgolden` checks that generated output matches `examples/{calc,calc_var,json}` and the self-hosted front end, and it builds and runs the example programs.
- After a deliberate codegen change, run `nimble build`, then `nimble test` (or `nim c -r tests/tgolden.nim`).
- The self-hosted front end bootstraps automatically during `nimble build` and `nimble test`; `tgolden` checks that it is a fixpoint.
- `examples/minipy` generated modules are also covered by the build/test regeneration, though `tgolden` does not compare them directly.

## Issues

- `issues/NNNN-short-slug.md` files use YAML frontmatter; take the next free number and never reuse one. Close an issue by setting `status: done` and keep the file. See `issues/README.md`.
