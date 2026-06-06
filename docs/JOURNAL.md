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
- Did **not** commit. Asking the user before any commit per CLAUDE.md.
- Handoff: still need the real path to gcc 8.5.0 from the user before
  starting P2 (diagnostics) — `gcc85` is a shell alias and will not
  resolve inside `job_start()`. The user must `let g:gccide_gcc =
  '/real/path/to/gcc'` in their vimrc. P1 itself does not need it
  (we parse the literal token `gcc`/`g++` out of `make -Bnk` output),
  so P1 can be tested without it.
