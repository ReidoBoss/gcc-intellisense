# Roadmap

Phases are sequential. Finish one before starting the next. Each phase
ships with a manual verification checklist at `tests/manual/p<N>.md`.

## P0 — Skeleton
- Create `plugin/gccide.vim`, `autoload/gccide.vim`, `autoload/gccide/`
  subdir, `tests/manual/`.
- Wire a `:GccideStatus` command that prints "alive".
- Goal: confirm vim 8.0 picks the plugin up.

## P1 — Project detection + flag extraction
- Walk parent dirs from the current buffer for a `Makefile`.
- If none found, `input()` and ask the user for the Makefile directory.
- Run `make -Bnk` there, parse stdout for gcc invocations.
- Extract per-file `-I`, `-D`, language-mode flags.
- Cache by Makefile mtime in `.gccide/flags`.
- `:GccideFlags` command for inspection.

## P2 — Diagnostics
- On `BufWritePost`, async `gcc85 -fsyntax-only <flags>`.
- Parse stderr lines (`file:line:col: error|warning: msg`).
- Place signs in the gutter; populate the quickfix list.
- Debounced `TextChanged` re-parse (default 300 ms).
- Target: a syntax error appears as a sign within 500 ms of save.

## P3 — Identifier index
- Walk `.c`/`.cpp`/`.h` reachable from the project root.
- Regex-extract function defs, typedefs, `#define`s, struct/union/enum
  tags, file-scope globals.
- Build `{symbol -> [locations]}`. Persist to `.gccide/index`.
- `:GccideFind <symbol>` returns every defining location.

## P4 — Autocomplete (identifier-only)
- `omnifunc=gccide#omnicomplete`. Candidates from the identifier index,
  filtered by the prefix at cursor.
- Candidate source is pluggable so a future semantic backend swaps in
  without touching the omnifunc surface.

## P5 — Go-to-definition
- `<Plug>(gccide-goto-def)`, default-mapped to `<leader>gd`.
- Single hit: open in a new split, cursor at definition.
- Multiple hits: populate the quickfix list, jump to the first.

## P6 — Performance + caching
- Profile the diagnostic and completion paths.
- Target ≤500 ms perceived latency on the firmware project. Snappier is
  better.
- Cache aggressively keyed by mtime. Re-index incrementally on save.

## Future (out of scope until the user asks)
- Semantic completion (struct members after `.`/`->`, signature hints).
- Hover info if it is cheap to derive from gcc output.
- Symbol rename, find references.
