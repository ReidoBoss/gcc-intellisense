# Journal

Append-only history. Newest entry at the **bottom**. Format:

```
## YYYY-MM-DD HH:MM — <claude|codex>
- what changed
- why
- anything the next agent needs to know
```

---

## 2026-06-06 17:17 — claude
- Bootstrapped the repo: `CLAUDE.md`, `AGENTS.md`, and the `docs/` skeleton
  (`README.md`, `ARCHITECTURE.md`, `CONVENTIONS.md`, `ROADMAP.md`,
  `JOURNAL.md`, `STATE.md`, `TASKS.md`).
- Captured constraints from the user: vim 8.0 only (`vim80`), gcc 8.5.0
  only (`gcc85`), no Python/Perl/Lua, no clangd/clang, no third-party
  plugins. Operate on `.c`/`.cpp`/`.h` only. `make`/`awk`/`sed`/`grep`/`find`
  are allowed but restricted to those file types. ctags/cscope are
  unconfirmed and must not be relied on.
- Captured feature scope: identifier-only autocomplete (designed to evolve
  to semantic), diagnostics via signs + quickfix, go-to-def in a new split,
  multi-file project awareness, ≤500 ms latency target.
- Captured coordination model: agents run sequentially. `CLAUDE.md` and
  `AGENTS.md` are byte-identical pointers to `docs/`. Agents may commit
  but must ask the user first every time. Verification is manual.
- Deleted the original `temp` brief now that its contents are captured in
  the docs.
- No vimscript yet. P0 (skeleton) is the next agent's task.

## 2026-06-06 (P0) — claude
- Shipped P0 (skeleton). Files created:
  - `plugin/gccide.vim` — load guard `g:loaded_gccide`, registers
    `:GccideStatus`. Deferred all logic to autoload per CONVENTIONS.md.
  - `autoload/gccide.vim` — `gccide#status()` returning `'alive'`.
  - `autoload/gccide/.gitkeep` — keeps the sub-module directory in git
    while it is empty. Sub-modules (`autoload/gccide/flags.vim`,
    `autoload/gccide/diag.vim`, …) land in later phases and replace this.
  - `tests/manual/p0.md` — 4 vim80 checks: plugin loads clean,
    `:GccideStatus` prints `alive`, double-source respects the load
    guard, autoload resolves on demand without sourcing the plugin file.
- Pure vim 8.0 syntax, no vim9script, no `system()` calls, no external
  tools touched. Matches the whitelist.
- Did **not** commit. CLAUDE.md says ask first; waiting on the user.
- Handoff: the user needs to run `tests/manual/p0.md` on the work laptop
  and report results. After sign-off, P1 begins by asking the user for
  the real path to gcc 8.5.0 (the `gcc85` alias does not survive
  `job_start()`).

## 2026-06-06 (P1) — claude
- User authorized starting P1 before running the P0 checklist. P0 sign-off
  is still owed; if step 1 of `tests/manual/p1.md` fails on plugin load,
  fall back to `tests/manual/p0.md` to bisect.
- Shipped P1 (project detection + flag extraction):
  - `autoload/gccide/flags.vim` — new module. `gccide#flags#project_root()`
    walks parent dirs via `findfile('Makefile', dir.';')` and falls back
    to an `input()` prompt. `gccide#flags#extract(root)` returns the
    cached `{absfile: flags}` dict or kicks off an async `make -Bnk`
    via `job_start(['sh','-c','cd <root> && make -Bnk 2>/dev/null'], ...)`
    and returns `{}` until the exit_cb populates the cache.
    `gccide#flags#for_file(file)` and `gccide#flags#show()` are the
    surfaces P2+ will use.
  - `plugin/gccide.vim` — added `:GccideFlags` command.
  - Removed `autoload/gccide/.gitkeep` now that `flags.vim` occupies the
    directory.
  - `tests/manual/p1.md` — 8 steps covering: plugin still loads,
    async extraction message + non-blocking UI, post-extract display,
    disk cache file shape (`.gccide/flags` JSON), cache hit timing,
    mtime invalidation, `input()` fallback when no Makefile, and the
    `g:gccide_project_root` override.
- Design notes for the next agent:
  - `make -Bnk` runs through `sh -c 'cd … && …'` instead of relying on
    `job_start`'s `cwd` option, which only landed in a later vim 8.0
    patch. Stays safe on any vim 8.0.x.
  - Flag parser folds two-arg flags into one token (`-I` `foo` → `-Ifoo`)
    so cached flag lists are positionally independent. Drops `-c`/`-S`/`-E`,
    `-o <file>`, and `-M*` dep-tracking flags. Keeps everything else
    starting with `-`. First `.c`/`.cpp`/`.h` token on the line wins.
  - Recursive make is handled via the `Entering directory '…'` /
    `Leaving directory '…'` GNU make markers — important for firmware
    trees with sub-Makefiles. Relative source paths are resolved against
    the current directory on the stack.
  - Disk cache is `<root>/.gccide/flags`, `json_encode`'d, keyed by
    Makefile mtime. In-memory cache + disk cache + mtime check is the
    full invalidation story for P1.
  - `:GccideFlags` is synchronous in spirit: first invocation may return
    "still extracting; re-run when notified" — the exit_cb echoes a
    `ready` message so the user knows when to re-run.
- User authorized a single bootstrap commit covering P0 + P1 + docs
  (root commit `7eeba58`).
- Handoff: still need the real path to gcc 8.5.0 from the user before
  starting P2 (diagnostics) — `gcc85` is a shell alias and will not
  resolve inside `job_start()`. The user must `let g:gccide_gcc =
  '/real/path/to/gcc'` in their vimrc. P1 itself does not need it
  (we parse the literal token `gcc`/`g++` out of `make -Bnk` output),
  so P1 can be tested without it.

## 2026-06-06 (test rewrite) — claude
- User pushed back on the existing `tests/manual/*.md`: they were written
  assuming verification on the locked-down Linux work laptop. The user
  doesn't always have that laptop in front of them; they need the manual
  tests to run on the Mac dev box right now.
- Confirmed the Mac toolchain via `command -v`:
  - `vim80` → `/Users/stephensagarino/opt/vim80/bin/vim`
  - `gcc85` → `/Users/stephensagarino/Personal-Binaries/xpack-gcc-8.5.0-1/bin/gcc`
  These shell aliases resolve from the shell, so `vim80 …` lines in
  the checklists work as-is. `gcc85` does not survive `job_start()` —
  the plugin already reads `g:gccide_gcc`, so this matters only for the
  vimrc line that manual tests now hardcode.
- Shipped fixture project at `tests/fixtures/proj/`:
  - `Makefile` with `-Iinc -DPROJ_BUILD=1 -DVERSION=\"0.1\" -std=c99
    -Wall -Wextra`.
  - `inc/proj.h`, `src/main.c`, `src/util.c`. A tiny but realistic 2-TU
    C99 project; `make -Bnk` emits two parseable gcc invocations.
- Rewrote `tests/manual/p0.md` and `tests/manual/p1.md` to be entirely
  self-contained and Mac-local: `cd` into the repo, `set rtp+=.`,
  point at the bundled fixture. No more `<REPO>`/`<PROJ>`/`<SRC>`
  substitutions.
- Updated `docs/README.md`, `docs/CONVENTIONS.md`, `CLAUDE.md`,
  `AGENTS.md` (the byte-identical pointers stayed in sync) to make the
  Mac the primary verification surface and to require fixtures over
  placeholders. The hard rule "tests run on the work laptop" is gone.
- Added top-level `.gitignore` excluding `.gccide/`, `*.o`, and the
  fixture's built `proj` binary.
- Smoke-tested locally with vim80 against the fixture:
  - Plugin loads with no errors.
  - First `:GccideFlags` printed `extracting compile flags ...`, the
    async exit_cb printed `flags ready ... (2 files)`, and a second
    `:GccideFlags` displayed the right flags for `src/main.c`.
  - Cache file exists at `tests/fixtures/proj/.gccide/flags` with
    correct JSON shape.
  - Cache hit on a fresh vim invocation: no `extracting` line, instant
    output.
- Fixed a UX wart caught by the smoke run: first `:GccideFlags` was
  printing both `extracting ...` and `still extracting; re-run when
  notified` in the same call. Now the "still extracting" line only
  appears on subsequent calls while a job is already in flight
  (we check `has_key(s:jobs, root)` *before* calling `extract()` and
  only echo on the re-entrant path).
- Saved three memory entries for future sessions:
  - feedback: manual tests run on Mac, ship fixtures not placeholders.
  - reference: Mac paths behind the `vim80`/`gcc85` aliases.
  - user: dev on Mac, deploy on locked-down Linux laptop.
- Did **not** commit. Awaiting user confirmation that the rewritten
  checklists pass when they run them locally.
- Next: P2 (diagnostics). gcc path is now known
  (`/Users/stephensagarino/Personal-Binaries/xpack-gcc-8.5.0-1/bin/gcc`)
  and will be hardcoded into `tests/manual/p2.md` with a reminder to
  set `g:gccide_gcc` in the user's vimrc.

## 2026-06-07 (P2) — claude
- Shipped P2 (diagnostics).
- `autoload/gccide/diag.vim` — new module. `gccide#diag#run(bufnr)` is
  the entry point: dump live buffer to a tempfile, run `gcc -fsyntax-only
  -x <lang> <flags> <tempfile>` async via `job_start`, capture stderr
  to a separate tempfile via `err_io=file`, on exit_cb parse and route
  to signs + quickfix. `gccide#diag#schedule(bufnr)` debounces on a
  `timer_start` (`g:gccide_debounce_ms`, default 300 ms).
  `gccide#diag#clear(bufnr)` removes signs and empties qf.
- `autoload/gccide/flags.vim` — refactored: split `project_root` into
  prompting + quiet variants, added per-file root caching so the diag
  hot path never re-walks the filesystem, added header fallback in
  `for_file` so `.h` buffers borrow flags from a TU.
- `plugin/gccide.vim` — registered `:GccideDiag`, `:GccideDiagClear`,
  and a `gccide_diag` augroup that wires `BufWritePost` to
  `gccide#diag#run()` and `TextChanged`/`TextChangedI` to
  `gccide#diag#schedule()` for `*.c,*.cpp,*.cc,*.cxx,*.h,*.hpp,*.hh,*.hxx`.
  Gated on `get(g:, 'gccide_auto', 1)`.
- `tests/manual/p2.md` — 9-step checklist. Steps 1–7 are scripted
  (heredoc into `/tmp` + `vim80 -S`); steps 8–9 are interactive.
- Design notes for the next agent (these were *not* obvious; preserving
  the reasoning so we don't relearn it):
  - Signs are managed via the ex-command form (`:sign define`, `:sign
    place`, `:sign unplace`). `sign_define()` / `sign_placelist()` /
    sign groups are vim 8.1+. We allocate sign IDs from a monotonic
    counter scoped per-buffer.
  - We dump the live buffer to a tempfile and tell gcc to compile *that*
    file rather than piping via stdin. Both `in_io='buffer'` and
    `ch_sendraw` + `ch_close_in` rely on vim's event loop being active
    to flush; under `vim80 -S script.vim` the loop doesn't tick during
    `:sleep` and the job stays stuck waiting for EOF. Tempfile = no
    dependency on the event loop.
  - Stderr is captured via `err_io: 'file'`. The pipe + `err_cb` path
    is unreliable in vim 8.0 for short-lived processes — `err_cb` may
    not fire before `exit_cb` and lines get dropped. Reading the tempfile
    in `exit_cb` is the robust pattern.
  - `setqflist([], 'r', {'items': …})` (items inside the what dict) is
    a post-8.0 patch. We use the older two-call form: `setqflist(items,
    'r')` then `setqflist([], 'a', {'title': 'gccide'})`.
  - Vim 8.0 in scripted (`-S`) batch mode doesn't reap exited children
    during plain `:sleep`. Calling `job_status()` in a polling loop
    forces the reap (and consequently fires the exit_cb). Interactive
    vim doesn't need this — keystrokes drain callbacks naturally — but
    the manual test checklist *does*, so `gccide#diag#_wait_done(bufnr,
    timeout_ms)` is exposed as a test seam.
  - Tempfile lifecycle: errfile + srcfile paths are bound into the
    `exit_cb` partial, not stored in `s:jobs`. That way, when a newer
    keystroke preempts an in-flight job via `job_stop`, the old job's
    exit_cb (with its bound paths) still cleans up its files. `s:jobs[bufnr]`
    just tracks "what's the latest job we care about results from" —
    older callbacks check it with `isnot` and discard their results.
  - Header support is via flag inheritance, not via stdin tricks: when
    `gccide#flags#for_file(file)` is called for a `.h`/`.hpp`/etc and
    the file isn't in the Makefile output, we return the flags of any
    TU in the same project so gcc gets the right `-I`/`-D` set.
- Smoke-tested locally on the Mac:
  - Step 1 (load + status + flags): passes.
  - Step 3 (clean main.c → 0 signs): passes.
  - Step 4 (injected error → 2 GccideWarning signs at line 10 + 2 qf
    items): passes.
  - Step 5 (header fallback → errors on proj.h): passes.
- Did **not** commit. Awaiting user verification of the full P2
  checklist plus the interactive steps 8–9, then commit on request.
- Next: P3 (identifier index). Open question: ask the user to run
  `command -v ctags` and `command -v cscope` and record results in
  `STATE.md` before designing the index walker.

## 2026-06-07 (test portability) — claude
- User pushed back that the project should not be Mac-only; the only
  prerequisites are `vim80` (vim 8.0) and `gcc85` (gcc 8.5.0). The
  plugin code was already portable (reads `g:gccide_gcc`), but
  `tests/manual/p{0,1,2}.md` had baked in `/Users/stephensagarino/…`
  paths from earlier sessions.
- Rewrote all three checklists to parametrize through `$PWD` (after
  `cd` into the repo) and `$GCCIDE_GCC` (env var the user `export`s
  once before running). Heredocs that build vim scripts now use the
  unquoted `<<VIM` form so the shell expands variables; literal `$`
  that vim must still see is escaped as `\$`.
- Verified step 4 of `p2.md` still works on this Mac after the rewrite
  — same output (2 GccideWarning signs at line 10, qf-len 2).
- Updated `docs/README.md`, `docs/CONVENTIONS.md`, `CLAUDE.md`,
  `AGENTS.md` (kept byte-identical) to drop "Mac dev box" framing.
- Updated memories: `feedback_manual_tests_local.md` renamed to
  "Manual tests run on any prereq machine";
  `reference_local_toolchain.md` renamed to make it explicit those
  Mac-specific paths are for the agent's own smoke testing and must
  not be hardcoded into any committed file.
- Did **not** commit. Asking the user before commit per CLAUDE.md.
- Next agent: this is purely a docs/test rewrite — the
  plugin code at HEAD (`d818076`) is unchanged.

## 2026-06-07 (P2 reworked around make) — claude
- User flagged that their codebase has a Makefile in a separate folder
  that already produces all the right errors via the build. They want
  diagnostics to come from running that Makefile, not from
  `gcc -fsyntax-only` per buffer. Confirmed: just `make`, no args, paths
  in output are absolute, and they invoke it through their own script
  that cd's into the Makefile dir.
- Rewrote `autoload/gccide/diag.vim` around `make`:
  - Single in-flight job for the whole project (not per buffer).
  - `job_start(['sh','-c','cd <root> && <g:gccide_make_cmd>'], ...)`
    with `out_io='null'` and `err_io='file'`.
  - On exit_cb, parse stderr for `abs:line:col: severity: msg`. Signs
    land in any loaded buffer matching the abs path; quickfix gets
    every diagnostic. Discards results from preempted jobs (newer
    save preempts older via `job_stop`).
  - Same 100 ms pulse timer trick as before to force vim to reap the
    child promptly.
- Stripped `autoload/gccide/flags.vim` down to a thin wrapper around
  `g:gccide_project_root` — no more `findfile()` walker, no `input()`
  prompt. The Makefile lives outside the source tree; auto-detect was
  always going to be wrong here.
- `plugin/gccide.vim`: removed the `TextChanged`/`TextChangedI`
  autocmd. `:GccideDiag` and `:GccideDiagClear` no longer take a
  bufnr.
- `docs/ARCHITECTURE.md`: diagnostics-engine section, external-tool
  whitelist, and config-var list all updated. Dropped
  `g:gccide_gcc`, `g:gccide_live`, `g:gccide_debounce_ms`. Added
  `g:gccide_make_cmd`. Added `g:gccide_source_root` /
  `g:gccide_index_path` as P3 placeholders.
- Smoke-tested locally: clean fixture → 0 signs, qf empty. Broken
  fixture (`bad_token_xyz();` injected into main.c) → 1 GccideError
  sign at line 8 + 1 qf item with the right error text.
- Rewrote `tests/manual/p2.md`: 5 scripted + 1 interactive. Tests
  inject a broken main.c via heredoc, run the diagnostic, verify,
  then `git checkout --` to restore the fixture.
- Recorded ctags/cscope probe on the Mac (BSD ctags unusable, cscope
  not installed); P3 will roll its own walker.
- Plugin no longer invokes gcc at all — `$GCCIDE_GCC` env var in the
  manual tests is also gone. Prerequisites narrow to just `vim80`,
  `make`, and whatever `make` itself needs. Project still works
  anywhere those are available.
- Smoke + commit + push pending user approval (they pre-authorized
  "one commit" for this whole rework).

## 2026-06-08 (P3) — claude
- Shipped P3 (identifier index). No new external tools — the plugin
  still only shells out via `sh -c '… && find …'`. ctags + cscope
  remain unused (BSD ctags on the dev Mac is unusable and cscope
  isn't installed; this was settled in the prior session's STATE.md).
- `autoload/gccide/index.vim` — new module.
  - `gccide#index#source_root()` returns `g:gccide_source_root` or
    falls back to `g:gccide_project_root`. Plugin no-ops cleanly when
    neither is set.
  - `gccide#index#build()` async-walks via
    `job_start(['sh','-c','cd <src> && find . -type f \( -name '*.c'
    -o ... \)'])` with one in-flight job at a time. stdout streams
    into `s:find_lines` via `out_cb`; exit_cb hands the list off to
    `s:parse_chunk(files, 0)` which slices 50 files per chunk and
    re-arms itself with `timer_start(1, ...)`. This keeps vim's main
    loop ticking between chunks — important for firmware-sized trees.
  - `s:extract_file(file)`: per-file regex extraction at brace-depth 0.
    Strings + `//` comments + one-line `/* */` comments are stripped
    before depth counting; multi-line block comments thread through a
    `[in_block]` state list. Symbols: `d` (#define), `t` (typedef —
    single-line `typedef ... NAME;` OR trailing `} NAME;`), `s`
    (struct/union/enum tag — also from `typedef struct NAME { … }`),
    `f` (function definition — signature with `{` same-line, or sig
    ending in `)` plus `{` on next line; declarations dropped via `;`
    detection), `g` (file-scope global — loose regex with `(`-absence
    guard and a keyword denylist).
  - Persistence: `<project_root>/.gccide/index` (override with
    `g:gccide_index_path`), JSON-encoded `{name: [{file, lnum, col,
    kind}]}`. Loaded lazily on first `:GccideFind` if the in-memory
    dict is empty.
  - `gccide#index#find(sym)` populates qf with every hit, attaches the
    `gccide-find:<sym>` title, and `:copen`s. Missing symbol → empty
    qf + an echo line.
  - 100 ms pulse timer (`s:pulse`) reaps `find` children the same way
    diag.vim does. Self-stops once both job and parse are done.
  - Test seams: `_wait_done(ms)` blocks until build settles;
    `_stats()` returns `{symbols, loaded_from}`.
- `plugin/gccide.vim`: registered `:GccideIndex` (no args) and
  `:GccideFind` (`-nargs=1`).
- `tests/fixtures/proj/inc/proj.h`: an interim draft of P3 added a
  typedef and a struct tag here to broaden checklist coverage. The
  user reverted that change; the fixture is back to the P2 baseline.
  The extractor still implements `t`/`s`/`g` kinds — they are simply
  not exercised by the bundled checklist, and `tests/manual/p3.md`
  flags this so the user knows to verify those branches against a
  real codebase.
- `tests/manual/p3.md`: 6 scripted + 1 interactive step. Build →
  on-disk file → stats; find-by-function (auto-loads from disk on a
  fresh vim, with no `:GccideIndex` call); find-by-kind across the
  define + function symbols present in the fixture; missing-symbol;
  no-root warning; interactive `Enter` jump from the quickfix
  window.
- Smoke against the fixture on the Mac (`vim80`): 5 symbols indexed,
  every lookup returns the right qf payload (PROJ_H@proj.h:2,
  PROJ_MAGIC@proj.h:4, main@main.c:4, proj_add@util.c:4,
  proj_greet@util.c:8). Index file shape verified. Fresh-vim
  auto-load works.
- Did **not** commit. CLAUDE.md says ask first; waiting on user
  sign-off on the P3 checklist before commit.
- Handoff to P4 (autocomplete): the index module already exposes the
  data the omnifunc needs (`s:idx` is `{name: [...]}`). Add a public
  `gccide#index#candidates(prefix)` accessor and wire
  `omnifunc=gccide#omnicomplete`. Two open design questions: implicit
  index-on-first-complete vs. require `:GccideIndex` explicitly, and
  whether to add a per-buffer re-extract on `BufWritePost` so
  freshly-typed identifiers complete without a full re-walk (the
  cross-file re-walk is queued for P6).
