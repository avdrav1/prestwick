---
name: next-epic
description: Pick the next planned epic in docs/BACKLOG.md and break it into stories with acceptance criteria and tests. Use when the active epic is done or the user says "next epic".
---

# Next epic

## Steps

1. Read `docs/BACKLOG.md`, `docs/design.md` and `CLAUDE.md`.
2. Confirm the current active epic has every story checked. If not, stop and say which stories remain. Do not start a second epic.
3. Mark the finished epic `done`. Take the first `planned` epic and mark it `active`.
4. Write 5 to 9 stories for it. Each story:
   - Id `E<n>-S<m>`, imperative title, one-line goal.
   - Acceptance criterion a human can verify in the running game or a test can assert.
   - Named test file under `tests/` for any logic story (validator, ball, reactions, economy).
   - Small enough to finish in one session. Split anything that touches more than two folders.
5. Order stories so the first makes something visible and the last closes the milestone's risk.
6. Cross-check against the design doc: every number a story depends on must already be in `docs/design.md`. If one is missing, add it there and note the source.
7. Show the stories to the user before writing them. Ask only if a story's scope is a real fork; otherwise proceed.
8. Write the stories into `docs/BACKLOG.md` and commit: `backlog: plan E<n>`.

## Rules

- Stories reference systems by their folder (`course/`, `golf/`, `guests/`), never by a file that does not exist yet.
- No story may add anything from the "Out of the MVP" list.
- If the epic's milestone depends on an unresolved item in the design doc's Open questions, the first story is a spike that resolves it and calls `/decision`.
