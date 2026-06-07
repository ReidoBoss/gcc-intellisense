# Architecture

## High level

```
  +---------+      +------------------+      +-----------------+
  | vim 8.0 | ---> | autoload/gccide  | ---> | gcc85 job       |
  |  (UI)   | <--- |  (vimscript)     | <--- | (async channel) |
  +---------+      +------------------+      +-----------------+
                            |
                            v
                   +-------------------+
                   | per-project cache |
                   |  .gccide/         |
                   +-------------------+
```

## Vim 8 features in use

- `job_start()` + channels — all gcc calls are async. Never block the UI.
- `+signs` — diagnostic gutter markers.
- `+quickfix` + `setqflist()` — diagnostic list.
- `+timers` — debounced re-parse on `TextChanged`.
- `omnifunc` — autocomplete surface.
- `split` / `edit` — go-to-def opens a new split.

## Components

Each component maps to a phase in `ROADMAP.md`.

### 1. Project detection
- On opening a `.c`/`.cpp`/`.h` buffer, walk parent directories looking for
  a `Makefile`.
- If none found, `input()`-prompt the user for the Makefile directory.
- Cache the discovered project root per buffer.

### 2. Compile-flag extraction
- Run `make -Bnk` (dry run, force, keep going) in the project root.
- Parse stdout for `gcc`/`g++` invocations.
- For each `.c`/`.cpp`/`.h`, extract `-I`, `-D`, `-isystem`, `-include`,
  language-mode (`-std=…`, `-x …`), and warning flags.
- Cache the result in `.gccide/flags`, keyed by the Makefile's mtime.

### 3. Diagnostics engine
- On `BufWritePost`, run `g:gccide_make_cmd` (default `make`) async via
  `job_start(['sh','-c','cd <root> && <cmd>'], ...)` with `out_io=null`
  and `err_io=file` (a tempfile).
- A single in-flight job for the whole project — newer saves preempt
  in-flight ones via `job_stop` so only the latest result wins.
- A repeating 100 ms pulse timer calls `job_status()` on the live job
  so vim's main loop reaps the exited child promptly (without it,
  interactive users see multi-second delays).
- On exit, parse stderr lines matching
  `<abs-path>:<line>:<col>: (fatal error|error|warning|note): msg`.
  Signs (`E>`/`W>`/`N>`) land in any loaded buffer whose absolute path
  matches a diagnostic. The quickfix list gets every entry regardless
  of buffer state.

### 4. Identifier index
- Walk `.c`/`.cpp`/`.h` files reachable from the project root (prefer the
  Makefile-derived source list when available; fall back to `find`).
- Regex-extract: function definitions, typedefs, `#define`s, struct/union/
  enum tags, file-scope globals.
- Build `{symbol -> [{file, lnum, col, kind}]}`. Persist to
  `.gccide/index` in the project root.

### 5. Autocomplete (identifier-only)
- `omnifunc=gccide#omnicomplete`. Return candidates from the identifier
  index, filtered by the prefix at cursor.
- The candidate source is pluggable. A future semantic backend should
  slot in by replacing the source, not the omnifunc surface.

### 6. Go-to-definition
- `<Plug>(gccide-goto-def)` — default mapping `<leader>gd`.
- Look up the word under the cursor in the index.
- On a single hit: `split | edit <file> | call cursor(lnum, col)`.
- On multiple hits: populate the quickfix list, jump to the first.

## External tools the plugin shells out to

Whitelist — agents must not extend without asking the user:

- `make` (or whatever `g:gccide_make_cmd` points at — typically a user
  script that ultimately invokes `make`).
- `sh` for the `cd <root> && <cmd>` wrapper.
- `awk`, `sed`, `grep`, `find` — restricted to `.c`/`.cpp`/`.h` files
  (planned for P3+).

The plugin no longer calls `gcc` directly — the user's Makefile owns
that.

## Configuration variables

- `g:gccide_project_root`   — **required.** Absolute path to the
                              directory that holds your Makefile. No
                              auto-detection; the Makefile typically
                              lives outside the source tree and walking
                              parents would miss it.
- `g:gccide_make_cmd`       — diagnostic command (default `'make'`).
                              Set to `'/path/to/your/script.sh'` or
                              `'make some_target'` if your build wraps
                              it. Always runs via `sh -c` after `cd`
                              into `g:gccide_project_root`.
- `g:gccide_auto`           — install the BufWritePost autocmd (default 1).
- `g:gccide_source_root`    — **future (P3).** Where `.c`/`.cpp`/`.h`
                              files live, for the identifier index.
                              May differ from the Makefile directory.
- `g:gccide_index_path`     — **future (P3).** Override `.gccide/index`
                              location.

## Why these choices

- **Async via jobs**: a syntax check on a firmware-sized translation unit
  can easily take hundreds of ms. Blocking vim is unacceptable.
- **Makefile as truth**: the user said the Makefile is the only source of
  flags. Inventing `-I`/`-D` flags would produce wrong diagnostics on a
  big firmware codebase.
- **Identifier-only first**: semantic completion needs a real parser
  (which gcc does not expose cleanly). Identifier completion gets us 80%
  of the value at a fraction of the cost, and the surface stays the same
  when we upgrade.
