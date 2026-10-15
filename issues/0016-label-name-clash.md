---
id: 16
title: Element label `label` clashes with the parse tree API
status: done
labels: [usability]
---

`name=ID` style element labels become accessor procs on the parse tree
(`n.name`), so a label that is already a field or proc of `ParseNode` is
rejected: `label 'label' clashes with the parse tree API; choose another
name`. `label` is a natural element name in many grammars (an assembler's or
a disassembler's labels, a statement label), and the user can't tell from
the grammar which names are taken.

## Decided

Rename the `label` field of `ParseNode` (to `edge`, or a similar word that
is unlikely as a grammar label), so `label=` is free. The other reserved
names (`kind`, `tok`, `sons`, `len`, `text`, `pos`, `items`, `treeRepr`)
stay reserved.

- [x] The chosen way, in the runtime, the code generator and the checks
- [x] Tests in `tchecks`/`tparsegen`

Notes:

- `ParseNode.label` is now `ParseNode.edge`; `label=` is a free element
  label and `edge` is reserved instead. Generated code never used the field
  (it goes through `add`, `son` and `sonsWith`), so no generated module
  changed.
- `tests/grammars/features.ldb` uses `label=`, so `tparsecodegen` and
  `tfuzz` compile a generated `label` accessor; `tparsegen` checks that
  `edge` is rejected and `label` parses.
