import std/strutils

# Puts `src` on the path for everything in the project, so examples, tests
# and the generated front end in src/lindeboom/grammar can import
# `lindeboom/...` as generated parsers do.
switch("path", thisDir() & "/src")

# Test and example binaries go under bin/ instead of next to their sources.
for dir in ["tests", "examples"]:
  let base = thisDir() & "/" & dir
  if projectDir() == base or projectDir().startsWith(base & "/"):
    switch("outdir", thisDir() & "/bin/" & projectDir().substr(thisDir().len + 1))
