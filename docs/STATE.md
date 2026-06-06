# State

> Always read this file first. Always update it before you stop.

## Current phase
**P1 — Project detection + flag extraction** (code written; awaiting user
manual verification). P0 also still owes a manual sign-off — user
authorized P1 before running `tests/manual/p0.md`. If the P1 checklist
fails at step 1 (plugin load), bisect with the P0 checklist first.

## Last agent
claude (2026-06-06) — shipped P1:
- `autoload/gccide/flags.vim` — new module. Project-root walker
  (`findfile('Makefile', dir.';')` with `input()` fallback), async
  `make -Bnk` runner via `job_start(['sh','-c','cd <root> && …'])`,
  GNU-make recursive-directory tracking, flag parser, mtime-keyed
  on-disk cache at `<root>/.gccide/flags` (json_encode'd).
- `plugin/gccide.vim` — added `:GccideFlags`.
- Removed `autoload/gccide/.gitkeep`; `flags.vim` now occupies the dir.
- `tests/manual/p1.md` — 8-step checklist covering detection, async
  extraction, cache hit, mtime invalidation, fallback prompt, and the
  `g:gccide_project_root` override.

## Next step
1. Wait for the user to run `tests/manual/p1.md` on the work laptop.
   Capture any failure output in `docs/JOURNAL.md` before moving on.
2. Ask the user whether to commit the P1 files (and P0 alongside, if
   not yet committed).
3. **Before starting P2**, get the real path to gcc 8.5.0 from the user.
   `gcc85` is a shell alias and will not survive `job_start()`. The user
   must `let g:gccide_gcc = '/real/path/to/gcc'` in their vimrc and tell
   us the path so the manual P2 checklist can reference it.
4. When P1 is signed off, begin P2 (diagnostics): async
   `gcc85 -fsyntax-only <flags> <file>` via `job_start`, parse stderr,
   place signs in the gutter, populate the quickfix list, debounce
   `TextChanged` through `timer_start()` (default 300 ms).

## Open questions (the next agent must resolve when their phase needs them)
- **ctags / cscope availability** on the user's work laptop is unknown.
  Before starting P3 (identifier index), ask the user to run
  `command -v ctags` and `command -v cscope` and record the result here.
  Do not depend on either until confirmed.
- **Real path to gcc 8.5.0**: still unanswered. P1 did not need it
  (we parse the literal `gcc`/`g++` token out of `make -Bnk` output), but
  P2 cannot start without it.

## Recent decisions
- Agents run sequentially, not in parallel.
- `CLAUDE.md` and `AGENTS.md` are intentionally byte-identical pointers
  to `docs/`.
- Agents may commit but must ask the user first every time.
- No automated test harness — verification is manual checklists in
  `tests/manual/`.
- Makefile is the only source of compile flags. Never invent `-I`/`-D`.
- Phase 1 autocomplete is identifier-only; the candidate source is the
  pluggable seam for a future semantic backend.
- P1 runs `make -Bnk` through `sh -c 'cd … && …'` instead of relying on
  `job_start`'s `cwd` option, which only landed in a later vim 8.0
  patch. Keeps us portable to any vim 8.0.x.
- Two-arg gcc flags (`-I foo`, `-D BAR`, `-isystem path`, `-include hdr`,
  `-x c`) are folded into a single token in the cache (`-Ifoo`, `-DBAR`)
  so downstream consumers do not need to reconstruct argument pairs.
- Recursive make is handled via `Entering directory` / `Leaving directory`
  markers. Relative source paths resolve against the current dir on the
  stack. Important for firmware trees with sub-Makefiles.
