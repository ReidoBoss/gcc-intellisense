# gcc-only-ide

A custom IntelliSense for vim 8.0 built on gcc 8.5.0 alone. No clangd, no LSP,
no Python, no third-party vim plugins. Pure vimscript talking to `gcc85` over
vim 8 job channels.

## Why

The user works in a company environment that prohibits third-party
dependencies. Only the following are guaranteed:

- `vim80` — vim 8.0 (shell alias on the user's machine)
- `gcc85` — gcc 8.5.0 (shell alias on the user's machine)
- Standard Unix tools: `make`, `awk`, `sed`, `grep`, `find`
- Possibly `ctags` / `cscope` — **status unknown.** Do not depend on either
  until the user confirms availability.

The host machine runs an old version of Linux. Treat anything beyond the
above list as unavailable.

## Scope

- Languages: C, C++, and headers. Only `.c`, `.cpp`, `.h` files.
- Phase 1 features:
  - Identifier-only autocomplete (designed to evolve to semantic later).
  - Diagnostics in vim's signs column + quickfix list.
  - Go-to-definition opening a new split.
  - Multi-file project awareness.
- Latency target: ≤500 ms. Snappier is better.
- Target codebase: a large firmware project. Day-to-day plugin development
  happens on a dev box that also has `vim80` and `gcc85` installed.
- **Manual verification runs on whichever machine has the prerequisites
  available.** The only prerequisites are `vim80` (vim 8.0) and `gcc85`
  (gcc 8.5.0). Tests ship a self-contained fixture under
  `tests/fixtures/proj/`; checklists parametrize machine-specific paths
  through environment variables, never hardcode them.

## Project layout

```
/                       project root (this directory)
CLAUDE.md               agent pointer (identical to AGENTS.md)
AGENTS.md               agent pointer (identical to CLAUDE.md)
docs/                   shared instructions for both agents
plugin/                 vim plugin entry point
autoload/gccide/        deferred-load vimscript (gccide#... namespace)
tests/manual/           step-by-step verification the user runs by hand
tests/fixtures/proj/    tiny Makefile + .c/.h fixture used by the manual
                        checklists so they are self-contained.
```

## How the two agents coordinate

- Agents run **sequentially**, not in parallel. Only one is active at a time.
- `docs/STATE.md` is the handoff file. Every agent reads it first and updates
  it last.
- `docs/JOURNAL.md` is append-only history. Every agent leaves a dated entry.
- `docs/TASKS.md` is the checkbox board. At most one task in progress.
- Both agents share the same instructions (this folder) so behavior is
  identical regardless of which is driving.
