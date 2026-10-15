---
id: 16
title: Element label `label` clashes with the parse tree API
status: open
labels: [usability]
---

`name=ID` style element labels become accessor procs on the parse tree
(`n.name`), so a label that is already a field or proc of `ParseNode` is
rejected: `label 'label' clashes with the parse tree API; choose another
name`. `label` is a natural element name in many grammars (an assembler's or
a disassembler's labels, a statement label), and the user can't tell from
the grammar which names are taken.

## To decide

- Rename the clashing parts of the parse tree API (the `label` field to,
  say, `edge`), so ordinary words stay free;
- or generate accessors under a prefix or in their own namespace only when
  they clash;
- or keep the error, but list the reserved names in `docs/DESIGN.md` and in
  the message.

- [ ] The chosen way, in the runtime, the code generator and the checks
- [ ] Tests in `tchecks`/`tparsegen`
