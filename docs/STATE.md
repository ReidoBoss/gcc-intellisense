# State

> Always read this file first. Always update it before you stop.

## Current phase
**P2 — Diagnostics** code is in. Plugin runs `gcc -fsyntax-only`
async on save and on a 300ms-debounced TextChanged, places signs in
the gutter, populates the quickfix list. Manual checklist
`tests/manual/p2.md` written (9 steps, scripted + interactive).
Smoke-tested locally on this Mac — clean buffer, injected error,
header fallback all green. Awaiting the user's local run.

## Last agent
claude (2026-06-07) — shipped P2:
- `autoload/gccide/diag.vim` — new module. Async `gcc -fsyntax-only`
  via `job_start` against a tempfile dump of the live buffer; stderr
  captured to another tempfile via `err_io=file`; on exit_cb parse and
  route to signs + quickfix. `schedule(bufnr)` debounces via
  `timer_start` (`g:gccide_debounce_ms`, default 300). `clear(bufnr)`
  removes signs and empties qf.
- `autoload/gccide/flags.vim` — refactored: split `project_root` into
  prompting (`gccide#flags#project_root`) and quiet
  (`gccide#flags#project_root_quiet`) variants. Per-file root cache
  added so the diag hot path doesn't re-walk on every keystroke.
  `for_file` falls back to a TU's flags when the file is a header.
- `plugin/gccide.vim` — `:GccideDiag`, `:GccideDiagClear` commands.
  `gccide_diag` augroup (gated on `g:gccide_auto`, default on) wires
  `BufWritePost` → `gccide#diag#run` and
  `TextChanged`/`TextChangedI` → `gccide#diag#schedule` for `.c`/`.cpp`/
  `.cc`/`.cxx`/`.h`/`.hpp`/`.hh`/`.hxx` buffers.
- `tests/manual/p2.md` — 9-step checklist (scripted: load, no-gcc
  warning, clean, error, header fallback, clear, severity matrix;
  interactive: TextChanged debounce, BufWritePost).

## Next step
1. User runs `tests/manual/p2.md` locally on the Mac (steps 1–7
   scripted, 8–9 interactive). Any failure → capture output in
   `docs/JOURNAL.md` first.
2. Ask the user whether to commit P2 (the new `diag.vim`, refactored
   `flags.vim`, `:GccideDiag*` commands + augroup in `plugin/gccide.vim`,
   `tests/manual/p2.md`).
3. **Before P3 (identifier index)**, ask the user to run
   `command -v ctags` and `command -v cscope` on the Mac and record
   the result in this file's "Open questions" section. P3 design
   depends on whether either is available; we will not depend on them
   if not confirmed.
4. P3 itself: walk `.c`/`.cpp`/`.h` files reachable from the project
   root, regex-extract function/typedef/define/tag/global names, build
   `{symbol -> [{file, lnum, col, kind}]}`, persist to
   `<root>/.gccide/index`, expose `:GccideFind <symbol>`.

## Open questions (the next agent must resolve when their phase needs them)
- **ctags / cscope availability** on the user's work laptop is unknown.
  Before starting P3 (identifier index), ask the user to run
  `command -v ctags` and `command -v cscope` and record the result here.
  Do not depend on either until confirmed.
- **Real path to gcc 8.5.0** (Mac): now known —
  `/Users/stephensagarino/Personal-Binaries/xpack-gcc-8.5.0-1/bin/gcc`.
  The work laptop path is still unknown; the user will set
  `g:gccide_gcc` there when they deploy. Plugin code does not hardcode
  paths — only the Mac manual tests do.

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
- Manual tests run on the Mac, not the work laptop. Fixtures live under
  `tests/fixtures/` so checklists are copy-paste-runnable.
- P2 diagnostics compile a **tempfile dump of the live buffer**, not
  stdin. `in_io='buffer'` and `ch_sendraw`+`ch_close_in` both rely on
  vim's event loop ticking during `:sleep`, which doesn't happen in
  scripted `-S` mode — gcc waits forever for EOF. Tempfiles sidestep
  this entirely.
- P2 stderr is captured via `err_io='file'`. The `err_cb` pipe path is
  unreliable in vim 8.0 for short-lived processes (lines get dropped
  before exit_cb fires).
- `setqflist([], 'r', {'items': …})` requires a post-8.0.0 patch.
  We use the older two-call form: `setqflist(items, 'r')` then
  `setqflist([], 'a', {'title': 'gccide'})`.
- `gccide#diag#_wait_done(bufnr, ms)` polls `job_status()` to force vim
  to reap exited children. Bare `:sleep` doesn't do it in `-S` mode.
  Interactive vim doesn't need it. Manual test scripts do.
- P2 tempfile lifecycle: `errfile`/`srcfile` are bound into the
  `exit_cb` partial (not stored in `s:jobs`), so a preempted job's
  cleanup still runs even though its result is discarded. `s:jobs[bufnr]`
  just identifies "which job's result do we still want."
- A repeating 100 ms pulse timer in diag.vim calls `job_status()` on
  every in-flight job. Without it, vim 8.0's main loop didn't wake up
  to reap exited gcc children until some unrelated event (next
  keystroke, redraw) happened — interactive users saw 5+ second
  sign-update delays. The pulse self-stops once `s:jobs` is empty.
- Diagnostics default to **save-only** (`BufWritePost`). Live-while-typing
  checks are opt-in via `let g:gccide_live = 1`. Reason: gcc on a large
  firmware TU can take seconds, so re-running on every typing pause is
  wasteful. `gccide#diag#schedule()` no-ops early when live mode is off.
  Don't flip this default without checking with the user.
