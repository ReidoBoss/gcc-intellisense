# State

> Always read this file first. Always update it before you stop.

## Current phase
**P6 — Performance shipped.** Incremental re-index on `BufWritePost`
(re-extracts just the saved file, splices into `s:idx`, re-persists).
mtime-gated `:GccideIndex` (find -newer short-circuits when nothing
changed). Baseline timings captured in `tests/manual/p6.md` step 5
for future comparison against the firmware codebase.

**Post-P6 polish (same session):** go-to-def now jumps in place
(same window, no new tab) when the definition lives in the current
buffer. Prior cursor position is pushed to the jumplist via
`<lnum>G`, so `<C-o>` walks back. Cross-file behavior unchanged
(still `tabedit`). User feedback drove the change.
`tests/manual/p5.md` gains a scripted "same-file" step 3 (uses
`append()` to inject a phantom in-memory call without modifying
the on-disk fixture) and a corresponding interactive step.

All roadmap phases (P0–P6) are now ticked in `TASKS.md`. Plugin
surface area is stable; remaining work is real-codebase validation
and the explicit "not in scope" deferrals listed below.

## Last agent
claude (2026-06-08) — P6:
- `autoload/gccide/index.vim`:
  - Added `gccide#index#refresh_file(file)`. Drops every entry in
    `s:idx` whose `file ==# abs(<file>)`, re-runs `s:extract_file`,
    splices the fresh symbols back, re-persists. Silent no-op when
    no in-memory + no on-disk index, or when the file is outside
    the source root, or when the file isn't readable. Lazy-loads
    from disk if `s:idx` is empty.
  - Restructured `gccide#index#build()` into a two-phase async
    pipeline. New entry checks for an existing index file; if
    present, runs `find . -newer <index> ... | head -n 1` first.
    Empty stdout → `gccide: index up to date` echo + no-op. Non-
    empty → fall through to `s:do_full_build(src)` (the prior
    body). Initial build (no on-disk index) goes straight to
    `s:do_full_build` without the check.
  - New script-local state for the check job: `s:check_job`,
    `s:check_lines`. Pulse timer and `_wait_done(ms)` extended to
    track both jobs. Self-stops when both are idle.
  - Extracted `s:find_predicates()` so the build find and the
    newer-check find share the same `-name '*.c' -o …` list.
- `plugin/gccide.vim` — added `gccide_index` augroup with
  `BufWritePost *.c,*.cpp,*.cc,*.cxx,*.h,*.hpp,*.hh,*.hxx
  call gccide#index#refresh_file(expand('<afile>:p'))`. Gated on
  `g:gccide_auto` like the diag/complete autocmds.
- `tests/manual/p6.md` — 6 scripted + 1 interactive step. Covers:
  surfaces, full build + persistence, mtime-gate short-circuit
  (asserts `index up to date` echo, no `index built` echo),
  refresh add/remove correctness, baseline timings (full build,
  refresh_file, candidates×1000, lookup×1000), end-to-end
  BufWritePost integration (open buffer, `append`, `:write`,
  verify `candidates('proj_')` now includes the new symbol), and
  an interactive walkthrough of "type, save, complete the new
  identifier without `:GccideIndex`".

## Smoke results (Mac, vim80)
- Step 1: `gccide#index#refresh_file` + `gccide#index#build`
  both defined.
- Step 2: full build → 5 symbols, 3 files; `.gccide/index` exists
  (640 bytes).
- Step 3: second `:GccideIndex` echoes `gccide: index up to date`
  — no `indexing` / `index built` lines.
- Step 4: `candidates('proj_')` 2 → 3 after appending
  `proj_brand_new` + `refresh_file`; `lookup('proj_brand_new')`
  returns 1 hit; both drop to 2 / 0 after restoring the file +
  re-refreshing.
- Step 5 baseline (fixture, ~3 files, microscopic):
  - `full_build`        ≈ 0.078s (dominated by async find +
    `_wait_done` polling at 50 ms granularity)
  - `refresh_file`      ≈ 0.005s (single file, no `find`)
  - `candidates`×1000   ≈ 0.116s (≈ 0.12 ms/call)
  - `lookup`×1000       ≈ 0.007s (≈ 0.007 ms/call)
  Re-record these on the real firmware tree when you first run
  there; they're the comparison baseline.
- Step 6: BufWritePost integration end-to-end — append a function
  to util.c, `:write` inside vim, then candidate count rises from
  2 to 3 and `lookup('proj_save_test')` returns 1 hit. Fixture
  restored via `git checkout --` at the end.

## Previous (P5)
claude (2026-06-08) — P5:
- `autoload/gccide/index.vim` — added `gccide#index#lookup(name)`.
  Same lazy-load pattern as `candidates()`. Returns the raw hit list
  `[{file, lnum, col, kind}]` (copy, not aliased into `s:idx`) or
  `[]` if the name is missing.
- `autoload/gccide/goto.vim` — new module.
  `gccide#goto#def()` is the entry point. Sequence:
  1. `expand('<cword>')` for the identifier under the cursor; empty
     → `gccide: no word under cursor` echo, bail.
  2. `gccide#index#lookup(word)` → 0 hits echo
     `gccide: no definition for <word>` and bail.
  3. 1 hit: if `(file, lnum)` matches the current buffer + cursor
     line, echo `gccide: already at definition of <word>` and bail
     (no tab/split). Otherwise run `s:split_cmd() . ' ' . fnameescape(file)`
     (default `tabedit`, override via `g:gccide_split_cmd`),
     `cursor(lnum, col)`, `normal! zz` to centre.
  4. >1 hits: build qf items (mirrors `:GccideFind`'s format with a
     `gccide-goto:<word>` title), `setqflist(items, 'r')` +
     `setqflist([], 'a', {'title': …})` (vim 8.0 two-call form,
     same as P2/P3), `:copen`, `:cfirst`.
- `plugin/gccide.vim`:
  - Registered `:GccideGoto` (command form).
  - `nnoremap <silent> <Plug>(gccide-goto-def) :<C-u>call gccide#goto#def()<CR>`.
  - Default mapping `gd → <Plug>(gccide-goto-def)` is installed
    only when both `!hasmapto('<Plug>(gccide-goto-def)')` and
    `empty(maparg('gd', 'n'))` are true. `maparg('gd', 'n')` only
    sees user-defined mappings, so vim's built-in `gd` (goto local
    declaration) reports empty and our mapping installs over it —
    which is what we want. Gated on `g:gccide_auto`.
- `tests/manual/p5.md` — 5 scripted + 1 interactive step. Covers
  surface reachability, single-hit jump (main.c:5 `proj_greet` call
  → util.c:8 definition, wincount=2), no-hit echo (printf in main.c
  → no split), already-at-definition (cursor on `proj_add`'s
  definition line → no split), `<Plug>` + `<leader>gd` mapping
  introspection. Multi-hit qflist path is documented as unexercised
  by the fixture (all symbols are unique-name) — flagged for
  verification against a real codebase.

## Smoke results (Mac, vim80)
- Step 1: `gccide#goto#def` and `gccide#index#lookup` both defined.
- Step 2: cursor at main.c (5, 10) → new tab opens util.c, cursor
  lands at (8, 1), `tabpagenr('$') == 2`, `tabpagenr() == 2`.
- Step 3: cursor on `printf` (no index entry) → echo
  `gccide: no definition for printf`, no tab opened, still on
  main.c (`tabpagenr('$') == 1`).
- Step 4: cursor at util.c (4, 5) (on `proj_add`'s definition
  line) → echo `gccide: already at definition of proj_add`, no
  tab opened, cursor unchanged.
- Step 5: `maparg('<Plug>(gccide-goto-def)', 'n')` reports
  `:<C-U>call gccide#goto#def()<CR>`; `maparg('gd', 'n')` reports
  `<Plug>(gccide-goto-def)`.

## Previous (P4)
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

## Next step
1. User runs `tests/manual/p6.md` locally (6 scripted + 1
   interactive). Capture any failure in `docs/JOURNAL.md` first.
2. Validate on the real firmware codebase. Re-run step 5's
   timing block there and append the numbers to STATE.md so we
   have a real-world baseline to regress against. Also verify
   the multi-hit go-to-def quickfix path (the fixture has no
   multi-defined symbol).
3. Optional follow-ups (none of these are P6 — they are deferred
   polish work):
   - **Header-guard filter** in `s:extract_file`: drop a `#define
     UPPER` when the prior non-blank line in the same file is
     `#ifndef UPPER`. Cleans `PROJ_H` out of `PROJ_`-prefix
     completions.
   - **Refresh debounce** if rapid saves on big files prove
     noticeable. Currently every `:w` runs `s:extract_file` +
     `s:persist`; a 100 ms `timer_start` cancel/reset would
     collapse bursts.
   - **Deletion detection** for the mtime gate: rare enough that
     `rm -rf .gccide/index && :GccideIndex` is the documented
     workaround.

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
- **P5 go-to-def opens a new tab (`tabedit`) by default.** Picked
  by the user (was horizontal `split` in the first cut). Tabs keep
  the source buffer fully visible and let the user `gt`/`gT`
  between locations without juggling window heights. Override via
  `g:gccide_split_cmd = 'split'` (horizontal), `'vsplit'`
  (vertical), or any ex command that accepts a filename arg.
- **P5 default normal-mode mapping is `gd`.** Shadows vim's
  built-in `gd` (goto local declaration) — intentional: the
  built-in is rarely useful inside multi-file C projects, ours
  jumps cross-file through the index. `maparg('gd', 'n')` only
  reports user mappings (not built-ins), so the conditional
  install correctly skips when a user has bound `gd` themselves
  but happily installs over the built-in.
- **P5 short-circuits on jump-to-self.** Single-hit lookup whose
  `(file, lnum)` matches the current buffer + cursor line produces
  an echo instead of opening a split. Avoids the "looks like
  nothing happened" UX of splitting onto the same line you're
  already on.
- **P6 refresh-on-save is silent on success.** Saves happen too
  often for a status echo to be useful; the user notices the index
  is fresh because completion shows new identifiers. Failure modes
  (no index, file outside source root) also no-op silently.
- **P6 mtime gate uses `find -newer <index>`**, not a synchronous
  stat of every file. The check itself is async via the same
  job-channel machinery as the full build; pulse timer and
  `_wait_done` track both jobs so the test seam still works.
- **P6 incremental refresh is per-file, not debounced.** Every
  `:w` runs `s:extract_file` + `s:persist`. Cost is small (single
  file, regex-only — ~5 ms in the smoke). Debouncing would add
  complexity for no measurable win at this size; revisit if real
  codebase saves feel sluggish.
- **P6 mtime gate cannot detect deletions.** If a user `rm`s a
  source file outside vim, `find -newer` reports nothing newer
  than the index and we short-circuit, leaving the deleted file's
  symbols. Documented workaround: nuke `.gccide/index` and
  rebuild. The extra `find` to detect deletions wasn't worth the
  rare-case ROI.
- **Same-file go-to-def jumps in place, not in a new tab.**
  `s:jump()` checks `fnamemodify(hit.file, ':p') ==# expand('%:p')`
  before running `s:split_cmd()`. Same-file path uses
  `execute 'normal! <lnum>G'` (which adds the prior cursor to the
  jumplist) followed by `cursor(lnum, col)` to refine the column.
  Cross-file path is unchanged: `tabedit <file> | cursor(lnum,
  col)`. Result: `<C-o>` after a same-file jump returns to the
  call site, and cross-file jumps still spawn the tab. User
  feedback drove the change — opening a tab for an in-file move
  is overkill.
- **Index auto-builds at plugin-load time, not on `VimEnter`.**
  Vim sources `plugin/*.vim` AFTER vimrc, so
  `g:gccide_project_root` is already set by the time
  `plugin/gccide.vim` runs. A `VimEnter` autocmd is attractive in
  principle but doesn't fire under `vim80 -u NONE -S script.vim`
  (no event loop), which would break every scripted test seam.
  Plugin-load time works for both real users and the tests.
  `gccide#index#build()` is async (job_start returns
  immediately), so no startup blocking; the P6 mtime gate makes
  re-launches free. Opt out with `let g:gccide_index_on_startup =
  0` in your vimrc before this plugin loads.
- **Top-level `README.md` was added on user request.** It is the
  on-ramp: install, configure, commands, mappings, config-var
  reference. Deep material stays in `docs/` (architecture,
  conventions, journal, state, roadmap). The README links to
  those at the bottom so a new contributor lands on the right
  page.
