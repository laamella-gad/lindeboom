## Grammar front end: parse and check `.ldb` files.

import ./runtime/diagnostics, ./grammar/[ast, parser, checks]

export diagnostics, ast, parser, checks

proc loadGrammar*(src, filename: string): (Grammar, Diagnostics) =
  ## Parses and checks `src`. Checks run only when parsing succeeded, to
  ## avoid follow-up errors on a half-parsed grammar.
  var d = Diagnostics(filename: filename)
  let g = parseGrammar(src, d)
  if not d.hasErrors:
    checkGrammar(g, d)
  (g, d)
