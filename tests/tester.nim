## Runs every `tests/t*.nim` file. Run from the project root:
## `nim c -r tests/tester.nim`. `-d:release` and `-d:danger` are passed on.

import std/os

proc fatal(msg: string) = quit "FAILURE " & msg

proc exec(cmd: string) =
  echo "Running: ", cmd
  if execShellCmd(cmd) != 0: fatal cmd

const mode =
  when defined(danger): " -d:danger"
  elif defined(release): " -d:release"
  else: ""

let testDir = getCurrentDir() / "tests"
for f in walkFiles(testDir / "t*.nim"):
  let name = f.extractFilename
  if name != "tester.nim":
    exec "nim c --hints:off" & mode & " -r " & quoteShell(testDir / name)

echo "All test files completed."
