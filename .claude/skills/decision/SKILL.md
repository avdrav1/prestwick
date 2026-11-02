---
name: decision
description: Record an architecture, design, or scope decision for Prestwick in docs/DECISIONS.md. Use when a story forks, an Open question from the design doc gets answered, or something moves in or out of the MVP.
---

# Decision

## Steps

1. State the question in one line.
2. List the options considered, two to four, each with one line of cost and one of benefit.
3. State the choice and the reason in two sentences. Name the pillar it serves.
4. Append to `docs/DECISIONS.md`:

```
## D<n>: <question> (<date>)
Options: ...
Choice: ...
Why: ...
Affects: <files or docs/design.md sections>
```

5. Update `docs/design.md` if a number or rule changed. Remove the item from the Open questions list in the design doc if it answered one; say so in the reply so the user can mirror it there.
6. Commit: `decision: D<n> <short title>`.

## Rules

- A decision that adds scope must say what it removes or delays to pay for it.
- Reversals get a new entry that points at the old one; never edit history.
