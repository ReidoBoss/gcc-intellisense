# Tasks

Checkbox board. Tick when done. `[in progress — claude]` or
`[in progress — codex]` marks active work. Only one task is in progress at
a time, since agents run sequentially.

## P0 — Skeleton
- [x] Create `plugin/gccide.vim` (entry point).
- [x] Create `autoload/gccide.vim` with `gccide#status()` returning `"alive"`.
- [x] Create `autoload/gccide/` subdirectory.
- [x] Register `:GccideStatus` command.
- [x] Write `tests/manual/p0.md`.

## P1 — Project detection + flag extraction
- [x] Walk parent dirs from the current buffer for a `Makefile`.
- [x] `input()`-prompt the user for the Makefile dir if not found.
- [x] Run `make -Bnk` in the project root and capture stdout.
- [x] Parse gcc invocations from `make -Bnk` output.
- [x] Extract per-file `-I`, `-D`, `-isystem`, `-include`, language-mode flags.
- [x] Cache flags by Makefile mtime in `.gccide/flags`.
- [x] `:GccideFlags` command for inspection.
- [x] Write `tests/manual/p1.md`.

## P2 — Diagnostics
- [x] Async runner for `gcc -fsyntax-only` via `job_start()`.
- [x] Parse stderr lines into structured diagnostics.
- [x] Place signs in the gutter.
- [x] Populate the quickfix list.
- [x] Debounced re-parse on `TextChanged` (default 300 ms).
- [x] Write `tests/manual/p2.md`.

## P3 — Identifier index
- [x] Probe ctags/cscope availability; record result in `STATE.md`.
- [x] File walker scoped to `.c`/`.cpp`/`.h`.
- [x] Regex symbol extraction (functions, typedefs, defines, tags, globals).
- [x] Persist `.gccide/index`.
- [x] `:GccideFind <symbol>` command.
- [x] Write `tests/manual/p3.md`.

## P4 — Autocomplete
- [x] `gccide#omnicomplete()` returning index-filtered candidates.
- [x] Pluggable candidate source (semantic backend slot).
- [x] Write `tests/manual/p4.md`.

## P5 — Go-to-def
- [x] `<Plug>(gccide-goto-def)` mapping; default `<leader>gd`.
- [x] New-split jump on single hit.
- [x] Quickfix list on multiple hits.
- [x] Write `tests/manual/p5.md`.

## P6 — Performance
- [x] Profile the diagnostic + completion path.
- [x] Incremental re-index on save.
- [x] mtime-keyed cache invalidation throughout.
- [x] Write `tests/manual/p6.md`.
