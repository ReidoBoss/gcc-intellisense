# State

> Always read this file first. Always update it before you stop.

## Current phase
**P1 — Project detection + flag extraction** code is in. Manual
checklists `tests/manual/p0.md` and `tests/manual/p1.md` have been
rewritten to run on the Mac dev box against the bundled fixture at
`tests/fixtures/proj/`. Awaiting the user's first real local run.
Smoke-tested internally against vim80 + the fixture — load, extract,
cache hit, and cache file shape all green.

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
1. User runs `tests/manual/p0.md` and `tests/manual/p1.md` locally on
   the Mac. Capture any failure output in `docs/JOURNAL.md` before
   moving on.
2. Ask the user whether to commit the test rewrite (fixture, gitignore,
   rewritten checklists, README/CONVENTIONS/CLAUDE/AGENTS updates, the
   `show()` UX fix).
3. Begin P2 (diagnostics): async `gcc -fsyntax-only <flags> <file>`
   via `job_start`, with input piped from the buffer (`in_io='buffer'`,
   `in_buf=<bufnr>`) so dirty buffers work without temp files. Parse
   `<stdin>:line:col: severity: message` from stderr. Place signs in
   the gutter via the vim 8.0-compatible `:sign place` ex-command
   (sign groups + `sign_placelist` are 8.1+). Populate `setqflist`.
   Debounce `TextChanged`/`TextChangedI` through `timer_start()`
   (default 300 ms; honors `g:gccide_debounce_ms`).
4. P2 manual checklist hardcodes the gcc path:
   `let g:gccide_gcc = '/Users/stephensagarino/Personal-Binaries/xpack-gcc-8.5.0-1/bin/gcc'`

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
