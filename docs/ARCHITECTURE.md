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
- Walk `.c`/`.cpp`/`.cc`/`.cxx`/`.h`/`.hpp`/`.hh`/`.hxx` files under
  `g:gccide_source_root` (falls back to `g:gccide_project_root`) via
  `job_start(['sh','-c','cd <src> && find . -type f \( -name '*.c' -o … \)'])`.
  We deliberately do **not** consult the Makefile-derived TU list: the
  source tree typically has headers and conditionally-excluded `.c`
  files we still want indexed for navigation.
- Per-file regex extraction at brace-depth 0. Strings + `//` comments
  + one-line `/* */` comments are stripped before depth counting;
  multi-line block comments thread a state flag across lines.
- Symbol kinds:
  - `d` `#define`
  - `t` typedef (single-line `typedef ... NAME;` or trailing `} NAME;`)
  - `s` struct/union/enum tag (incl. `typedef struct NAME { … }`)
  - `f` function definition (signature with `{` same-line, or sig
    ending in `)` plus `{` on next line — declarations dropped)
  - `g` file-scope global (loose match with `(`-absence guard and a
    keyword denylist)
- Parsing is chunked through `timer_start(1, ...)` at 50 files per
  chunk so vim's main loop ticks between batches.
- Persist `{name: [{file, lnum, col, kind}]}` to
  `<project_root>/.gccide/index` (override with `g:gccide_index_path`)
  as JSON. Loaded lazily on first `:GccideFind` if the in-memory dict
  is empty.

### 5. Autocomplete (identifier-only)
- `omnifunc=gccide#omnicomplete`. Return candidates from the identifier
  index, filtered by the prefix at cursor.
- The candidate source is pluggable. A future semantic backend should
  slot in by replacing the source, not the omnifunc surface.

### 6. Go-to-definition
- `<Plug>(gccide-goto-def)` — default mapping `gd` (shadows vim's
  built-in `gd`; the built-in is rarely useful in multi-file C
  projects).
- Look up the word under the cursor in the index.
- On a single hit: `tabedit <file> | call cursor(lnum, col)`
  (override the open command via `g:gccide_split_cmd` —
  `'split'`/`'vsplit'` for in-window splits).
- On a single hit where `(file, lnum)` already matches the cursor:
  echo `already at definition` and bail.
- On multiple hits: populate the quickfix list, jump to the first.

## External tools the plugin shells out to

Whitelist — agents must not extend without asking the user:

- `make` (or whatever `g:gccide_make_cmd` points at — typically a user
  script that ultimately invokes `make`).
- `sh` for the `cd <root> && <cmd>` wrapper.
- `find` — restricted to `.c`/`.cpp`/`.cc`/`.cxx`/`.h`/`.hpp`/`.hh`/`.hxx`
  via explicit `-name` predicates. Used by the identifier index.
- `awk`, `sed`, `grep` — whitelisted but currently unused; reserved
  for later phases.

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
- `g:gccide_source_root`    — where `.c`/`.cpp`/`.h` files live, for
                              the identifier index. May differ from
                              the Makefile directory. Falls back to
                              `g:gccide_project_root` when unset.
- `g:gccide_index_path`     — override the default
                              `<project_root>/.gccide/index` location
                              for the identifier index.
- `g:gccide_split_cmd`      — open command used by go-to-def
                              (default `'tabedit'`). Set to `'split'`
                              for a horizontal split, `'vsplit'` for
                              vertical, or any ex command that
                              accepts a filename argument.

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
