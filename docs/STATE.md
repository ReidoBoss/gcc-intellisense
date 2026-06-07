# State

> Always read this file first. Always update it before you stop.

## Current phase
**P2 — Diagnostics reworked to run the project's Makefile** instead of
`gcc -fsyntax-only` per buffer. User flagged that their codebase has a
Makefile in a separate folder that produces all the right errors;
running their build is closer to their actual workflow than per-file
syntax checks. The plugin now calls `g:gccide_make_cmd` (default
`'make'`) in `g:gccide_project_root` on BufWritePost.

## Last agent
claude (2026-06-07) — reworked P2 around `make`:
- `autoload/gccide/diag.vim` — rewritten. `gccide#diag#run()` runs
  `g:gccide_make_cmd` (default `make`) async via
  `job_start(['sh','-c','cd <root> && <cmd>'], ...)`. One in-flight
  job for the whole project; newer calls preempt via `job_stop`.
  stderr → tempfile (`err_io=file`); on exit_cb parse and distribute
  signs across buffers by absolute path, populate `setqflist` for
  every diagnostic. The 100 ms pulse timer stays (still needed to
  reap exited children in vim 8.0).
- `autoload/gccide/flags.vim` — stripped to a thin wrapper around
  `g:gccide_project_root`. No more `findfile()` walker, no more
  `input()` prompt. P1 flag extraction (`make -Bnk`) still works, just
  with the required-config gate.
- `plugin/gccide.vim` — removed `TextChanged`/`TextChangedI` autocmd
  (live mode is gone; no longer makes sense with whole-project make).
  `:GccideDiag` and `:GccideDiagClear` no longer take a bufnr.
- `tests/manual/p2.md` — rewritten. 6 steps (5 scripted + 1
  interactive). Scripted tests inject a broken `main.c` via heredoc,
  run the diagnostic, verify the sign, then `git checkout --` to
  restore the fixture.
- `docs/ARCHITECTURE.md` — diagnostics engine section, config vars,
  and external-tool whitelist all updated to reflect make-based design.
  `g:gccide_gcc`, `g:gccide_live`, `g:gccide_debounce_ms` are gone.

## Next step
1. User runs `tests/manual/p2.md` locally (5 scripted steps + 1
   interactive). Capture any failure in `docs/JOURNAL.md` first.
2. Begin P3 (identifier index): walk `g:gccide_source_root` for
   `.c`/`.cpp`/`.h`, regex-extract function/typedef/define/tag/global
   names, build `{symbol → [{file, lnum, col, kind}]}`, persist to
   `<source_root>/.gccide/index`, expose `:GccideFind <symbol>`. No
   ctags/cscope dependency — `command -v ctags` on the Mac returned
   the BSD/Xcode ctags which doesn't support the flags we'd need, and
   cscope isn't installed.

## Open questions (the next agent must resolve when their phase needs them)
- **ctags / cscope availability**:
  - Dev Mac (2026-06-07): `/usr/bin/ctags` exists but is BSD/Xcode
    ctags — rejects `--version`, doesn't support `--c-kinds` /
    `--fields` / `-f -`. Effectively unusable for symbol extraction.
    `cscope` not installed.
  - Work laptop: still unknown.
  - **Decision:** P3 will not depend on ctags or cscope. We roll our
    own walker + regex extractor in pure vimscript. The prerequisites
    stay at `vim80` + `gcc85` + standard Unix tools (`find`, `grep`,
    `awk`, `sed`) — all already on the whitelist.
- **Real path to gcc 8.5.0**: no longer needed by the plugin. The
  Makefile owns gcc invocation. (`g:gccide_gcc` is gone.)

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
- Manual tests run on any machine that has `vim80` and `gcc85` —
  prerequisites are those two binaries, nothing else. Checklists
  parametrize through `$PWD` (after `cd` into the repo) and
  `$GCCIDE_GCC` (env var the user `export`s). Fixtures under
  `tests/fixtures/` keep checklists copy-paste-runnable. Do not
  hardcode `/Users/<somebody>/…` or `/home/<somebody>/…` paths.
- **Diagnostics run the project's Makefile, not `gcc -fsyntax-only`.**
  The user's codebase has a Makefile in a separate folder that
  produces all the right errors. Per their workflow, running that
  build is more useful than re-implementing per-file syntax checks.
  Live-while-typing mode is gone (can't run make against an unsaved
  buffer). `:w` is the trigger.
- P2 stderr is captured via `err_io='file'`. The `err_cb` pipe path is
  unreliable in vim 8.0 for short-lived processes (lines get dropped
  before exit_cb fires).
- `setqflist([], 'r', {'items': …})` requires a post-8.0.0 patch.
  We use the older two-call form: `setqflist(items, 'r')` then
  `setqflist([], 'a', {'title': 'gccide'})`.
- `gccide#diag#_wait_done(ms)` polls `job_status()` to force vim to
  reap the exited child. Bare `:sleep` doesn't do it in `-S` mode.
  Interactive vim doesn't need it. Manual test scripts do.
- A repeating 100 ms pulse timer in diag.vim calls `job_status()` on
  the in-flight job. Without it, vim 8.0's main loop didn't wake up
  to reap exited children until some unrelated event (next keystroke,
  redraw) happened — interactive users saw 5+ second sign-update
  delays. The pulse self-stops once the job is gone.
- Single in-flight make job for the whole project (not one per
  buffer). Newer saves call `job_stop` on the prior job; that job's
  exit_cb sees `s:current_job isnot a:job` and discards its result
  while still deleting its tempfile.
- `g:gccide_project_root` is **required**. No auto-detection — the
  Makefile typically lives outside the source tree, an upward walk
  would miss it. The plugin no-ops cleanly when unset.
