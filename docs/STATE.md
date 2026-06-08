# State

> Always read this file first. Always update it before you stop.

## Current phase
**P4 — Identifier autocomplete shipped.** `omnifunc=gccide#complete#omnifunc`
auto-installed on `FileType c,cpp`. Prefix-matched candidates drawn
from the P3 index via `gccide#index#candidates(prefix)`. Candidate
sources are pluggable through `gccide#complete#register_source(Funcref)`
so a future semantic backend slots in without touching the omnifunc
surface.

## Last agent
claude (2026-06-08) — P4:
- `autoload/gccide/index.vim` — added `gccide#index#candidates(prefix)`.
  Lazy-loads `s:idx` from disk if empty (same trick `:GccideFind`
  uses), then returns `[{word, kind, menu, dup}]` for names whose
  string prefix matches. `kind` is the first hit's index kind
  (`f`/`d`/`t`/`s`/`g`) so vim's popup shows it directly. `menu` is
  the basename of the first hit's file, with ` +N` appended when the
  symbol has multiple definitions. Sorted alphabetically.
- `autoload/gccide/complete.vim` — new module.
  `gccide#complete#omnifunc(findstart, base)` is the surface. On
  `findstart`, walks back across `\w` chars from the cursor and
  returns the 0-based start column. On the candidate pass, iterates
  registered sources, de-dups by `word`, returns the merged list. If
  the merged list is empty AND no index is loaded (neither in memory
  nor on disk), echoes `gccide: index empty (run :GccideIndex)`
  — chosen over implicit-build-on-first-complete because the build
  is async; the first call would return `[]` anyway and we'd rather
  be explicit. `gccide#complete#register_source(Funcref)` is the
  pluggable seam; the script-local default source wraps
  `gccide#index#candidates`. `gccide#complete#_index_loaded()` is
  the helper that drives the nudge (test seam too).
- `plugin/gccide.vim` — added `gccide_complete` augroup with
  `FileType c,cpp setlocal omnifunc=gccide#complete#omnifunc`. Gated
  on `g:gccide_auto` like the diag autocmd. No new user commands —
  the omnifunc is the surface, not a `:GccideComplete` wrapper.
- `tests/manual/p4.md` — 6 scripted + 1 interactive step. Covers:
  function existence, empty-index nudge, prefix match on
  `proj_` (auto-loaded from disk on a subsequent run with no
  `:GccideIndex` call), prefix match on `PROJ_`, miss case (no
  nudge when the index is loaded), `findstart` returning the
  identifier start column, and an interactive `<C-x><C-o>` step
  in `main.c`.

## Smoke results (Mac, vim80)
- Function existence: `gccide#complete#omnifunc`,
  `gccide#complete#register_source`, `gccide#index#candidates` all
  defined (1/1/1) after forcing `runtime! autoload/...`.
- Empty index: `len=0` and the `gccide: index empty (run
  :GccideIndex)` nudge fires.
- After `:GccideIndex` + `_wait_done`:
  - `proj_` → `proj_add|f|util.c`, `proj_greet|f|util.c` (sorted).
  - `PROJ_` → `PROJ_H|d|proj.h`, `PROJ_MAGIC|d|proj.h` (auto-loaded
    from `.gccide/index` on a fresh vim invocation — no
    `:GccideIndex` needed).
- Miss case (`no_such_prefix_`): `len=0`, **no** nudge (index is
  loaded; correct behavior).
- `findstart` at `call cursor(5, 10)` on
  `    proj_greet("world");` returns `4`.
- `FileType c` autocmd (with `filetype plugin on`) correctly sets
  `omnifunc=gccide#complete#omnifunc` when `main.c` is loaded.

## Next step
1. User runs `tests/manual/p4.md` locally (6 scripted + 1
   interactive). Capture any failure in `docs/JOURNAL.md` first.
2. Begin **P5 (go-to-def)**: `<Plug>(gccide-goto-def)` mapping with
   default `<leader>gd`. Looks up `expand('<cword>')` in the index
   (`gccide#index#candidates(word)` is overkill — we want exact-name
   lookup; add `gccide#index#lookup(name)` returning the hit list
   directly). Single hit → `split | edit <file> | call cursor(lnum,
   col)`. Multiple hits → reuse the `setqflist` path from `:GccideFind`
   and jump to the first.

## Open questions (the next agent must resolve when their phase needs them)
- **P5 split direction**: `split` (horizontal above) vs `vsplit`
  (vertical left) vs `tabedit`. Lean `split` per ARCHITECTURE.md
  ("opens a new split"); let user override via `g:gccide_split_cmd`
  later if asked.
- **P5 jump-to-self handling**: looking up the word under the cursor
  on the very line that *defines* it produces a single hit pointing
  back at the current position. Worth a `lnum != line('.')` guard
  before opening a split, or just leave it and let the user notice.
- **Incremental re-index on save** (queued for P6): P4's static
  index means a freshly-typed identifier doesn't complete until the
  next full `:GccideIndex`. Acceptable for an initial release;
  flagged in `tests/manual/p4.md` "Known limitations".
- **Header guard noise** (`PROJ_H` etc.): still indexed as `d`
  candidates, still shows in completion. Filter heuristic deferred.

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
- **P4 omnifunc does not implicitly trigger `:GccideIndex`.** The
  build is async, so the first complete would return `[]` regardless.
  Empty-result + no-index combinations echo a one-line nudge instead.
  Explicit > surprising.
- **P4 candidate sources are a list of Funcrefs**, not a single
  pluggable hook. Registering a semantic backend later means
  appending another source — the identifier source keeps running and
  the omnifunc de-dups by `word`. Lets us ship semantic completion
  incrementally without breaking the always-on identifier fallback.
- **P4 prefix match is case-sensitive.** Mirrors vim's built-in
  i_CTRL-X_CTRL-O behavior. Trivial to relax later by lowercasing
  inside `gccide#index#candidates` if asked.
