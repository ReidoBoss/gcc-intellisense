# Agent instructions

This file is intentionally minimal. Two AI agents (Claude and Codex) work on
this project sequentially. Both must follow the **same** instructions, so
`CLAUDE.md` and `AGENTS.md` are byte-for-byte identical pointers to the
shared docs in `docs/`.

## Before doing anything

1. Read `docs/STATE.md` — that is where the last session left off.
2. Read the most recent entry in `docs/JOURNAL.md`.
3. If you have not seen them in this session, read `docs/README.md`,
   `docs/CONVENTIONS.md`, and `docs/ARCHITECTURE.md`.
4. Check `docs/TASKS.md` for what is in progress and what to pick up next.

## Before finishing

1. Append a new entry to `docs/JOURNAL.md` describing what you did and why.
2. Update `docs/STATE.md` so the next agent knows where to start.
3. Tick or move items in `docs/TASKS.md`.
4. **Hand the user a manual test they can run.** If you wrote or changed
   code, the relevant `tests/manual/<phase>.md` must cover it — create
   or extend the checklist so the user has concrete steps to verify your
   work on the work laptop. Never end a coding session without this.

## Hard rules

- Never install anything. Never download third-party code.
- Only `gcc85` (gcc 8.5.0) and `vim80` (vim 8.0) are guaranteed to exist.
- No Python, Perl, Lua, clangd, clang, or vim plugins.
- `make`, `awk`, `sed`, `grep`, `find` are allowed but only against
  `.c`, `.cpp`, `.h` files.
- Do not commit without asking the user first.
