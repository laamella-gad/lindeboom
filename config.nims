# Puts `src` on the path for everything in the project, so examples, tests
# and the generated front end in src/lindeboom/grammar can import
# `lindeboom/...` as generated parsers do.
switch("path", thisDir() & "/src")
