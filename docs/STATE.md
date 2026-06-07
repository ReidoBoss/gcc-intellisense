# State

> Always read this file first. Always update it before you stop.

## Current phase
**P3 — Identifier index shipped.** Async `find` walk over
`g:gccide_source_root`, per-file regex extraction with brace-depth
tracking, JSON persistence to `<project_root>/.gccide/index`.
`:GccideIndex` builds; `:GccideFind <symbol>` populates the quickfix
with all hits and `:copen`s.

## Last agent
claude (2026-06-08) — P3:
- `autoload/gccide/index.vim` — new module. `gccide#index#build()`
  fires `find . -type f \( -name '*.c' -o … \)` async via
  `job_start(['sh','-c','cd <src> && find …'], ...)`, captures stdout
  line-by-line, then on exit chunks the file list through
  `s:parse_chunk()` (50 files at a time, re-armed via `timer_start(1, …)`)
  so vim's main loop ticks between batches. Each file is `readfile()`d
  and run through `s:extract_file()`. Symbols: `d` (#define), `t`
  (typedef, single-line or trailing `} name;`), `s` (struct/union/enum
  tag, incl. `typedef struct NAME { … }`), `f` (function definition —
  signature with `{` same line or next line, declarations skipped via
  `;` detection), `g` (file-scope global — loose `\w \w (=|;|[)`
  pattern with `(`-absence guard and keyword filter). Strings + line
  comments + one-line block comments are stripped before brace
  counting; multi-line `/* … */` state is threaded across lines.
- `plugin/gccide.vim` — `:GccideIndex` and
  `:GccideFind` (`-nargs=1`) registered.
- `tests/fixtures/proj/inc/proj.h` — **unchanged** from P2. The
  earlier draft of P3 added a typedef + struct tag here to exercise
  more extractor branches; that change was reverted to keep the
  fixture minimal. The extractor still implements `t`/`s`/`g` kinds
  — they are simply not covered by the bundled checklist (a note in
  p3.md flags this).
- `tests/manual/p3.md` — 6 scripted + 1 interactive step. Covers:
  command registration, full build + on-disk file + stats, find-by-
  function (also exercises auto-load from `.gccide/index` on a fresh
  vim), find-by-define-and-function, missing-symbol, no-root warning,
  interactive `:GccideFind` → quickfix → Enter jump.

## Smoke results (Mac, vim80)
- Fixture build: 5 symbols across 3 files (PROJ_H, PROJ_MAGIC,
  proj_add, proj_greet, main).
- All `:GccideFind` lookups return the expected `kind: name` qf text
  with correct lnums (util.c:4, util.c:8, main.c:4, proj.h:2/4).
- Index persists to JSON at
  `tests/fixtures/proj/.gccide/index`; fresh vim auto-loads on first
  `:GccideFind` (no rebuild needed).
- P2 step-3 sanity (clean fixture): still passes — 0 signs, empty qf.

## Next step
1. User runs `tests/manual/p3.md` locally (6 scripted + 1 interactive).
   Capture any failure in `docs/JOURNAL.md` first.
2. Begin **P4 (autocomplete)**: `omnifunc=gccide#omnicomplete` returning
   identifier-prefix-filtered candidates from `s:idx`. Pluggable
   candidate source so a future semantic backend slots in by replacing
   the source, not the omnifunc surface. The index module already
   exposes the raw data — P4 just needs a `gccide#index#candidates(prefix)`
   accessor and the omnifunc dispatch glue.

## Open questions (the next agent must resolve when their phase needs them)
- **Should P4 trigger an implicit `:GccideIndex` on first
  omnicomplete?** Lean yes (with a one-shot "indexing…" echo) so
  out-of-the-box completion works without the user knowing about the
  build command. But the build is async, so the first invocation will
  return [] — UX needs to either block briefly or echo "still
  building" and let the user retry. Decide when designing P4.
- **Incremental re-index on save** is queued for P6, but a P4
  implementation that returns stale candidates after an edit could
  feel broken. May need a lightweight per-buffer re-extract on
  BufWritePost in P4 to keep the current file's symbols fresh, even if
  the cross-file re-walk waits until P6.
- **Header guard noise**: the index currently picks up `PROJ_H` from
  `#define PROJ_H`. Acceptable for P3 (it's a real define), mildly
  annoying for autocomplete. Filtering heuristic (uppercase-only +
  matching `#ifndef` in the same file) is a P4-or-later polish.

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
  Interactive vim doesn't need it. Manual test scripts do. P3 reuses
  the same pattern via `gccide#index#_wait_done(ms)` and a pulse
  timer in `index.vim`.
- A repeating 100 ms pulse timer in diag.vim calls `job_status()` on
  the in-flight job. Without it, vim 8.0's main loop didn't wake up
  to reap exited children until some unrelated event (next keystroke,
  redraw) happened — interactive users saw 5+ second sign-update
  delays. The pulse self-stops once the job is gone. Index module
  mirrors this for the `find` job and stops once parsing is also
  finished.
- Single in-flight make job for the whole project (not one per
  buffer). Newer saves call `job_stop` on the prior job; that job's
  exit_cb sees `s:current_job isnot a:job` and discards its result
  while still deleting its tempfile.
- `g:gccide_project_root` is **required**. No auto-detection — the
  Makefile typically lives outside the source tree, an upward walk
  would miss it. The plugin no-ops cleanly when unset.
- **P3 walks `g:gccide_source_root`** (falls back to project root),
  not the Makefile-derived TU list. Headers don't appear in `make
  -Bnk` output and we want them indexed; `find` is fast enough on
  firmware-sized trees and avoids coupling the index to the flags
  cache.
- **P3 parsing is chunked through `timer_start(1, …)`** at 50 files
  per chunk. A single firmware codebase has thousands of files;
  blocking vim during a full parse would be unacceptable. The chunk
  size is conservative — adjust in P6 profiling if needed.
- **P3 extracts at brace-depth 0 only.** Strings and one-line `/* */`
  comments are stripped before counting `{`/`}`; multi-line block
  comments are threaded across lines via a one-element state list.
  Approximate but cheap; the cost of a miscount is an extra sym or a
  missed sym, never a vim hang.
- **P3 does not consult the flags cache.** Tempting (Makefile knows
  every `.c` file the project actually compiles), but the source
  tree typically contains headers and conditionally-excluded `.c`
  files we still want indexed for navigation. `find` over the source
  root is the right scope.
