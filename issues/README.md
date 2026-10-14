# Issues

One Markdown file per issue, named `NNNN-short-slug.md` (zero-padded,
never reused). New issue: take the next free number.

Each file starts with front matter:

```yaml
---
id: 1
title: Grammar front end and checks
status: open        # open | in-progress | done | wontfix
labels: [milestone]
milestone: 1       # optional
depends: [2, 3]    # optional: issue ids that must be done first
---
```

followed by a description and a task checklist. Close an issue by setting
`status: done`; keep the file.

List open issues:

```sh
grep -l '^status: open' issues/*.md
```
