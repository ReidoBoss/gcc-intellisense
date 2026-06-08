# gcc-only-ide

A C/C++ IntelliSense layer for **vim 8.0** built on **gcc** and the
project's own Makefile. Pure vimscript — no clangd, no LSP, no
Python, no third-party vim plugins.

If your work machine restricts third-party tooling to `vim80`,
`gcc85`, and standard Unix utilities, this plugin gets you:

- **Diagnostics** in the sign column and quickfix, sourced from the
  errors the project's `make` already produces.
- **Identifier autocomplete** via vim's omnifunc, fed by a regex
  index of every `#define`, typedef, struct/union/enum tag,
  file-scope global, and function definition in the source tree.
- **Go-to-definition** on `gd` — same-file jumps in place
  (`<C-o>` returns), cross-file jumps open in a new tab. Multiple
  hits route through the quickfix list.

Prerequisites: vim 8.0 (`vim80`), and whatever your project's
`make` command needs (typically gcc — but the plugin doesn't invoke
gcc directly; it shells out to your Makefile).

## Install

There's no package manager. Drop the repo onto your runtime path:

**Option A: clone into your `~/.vim/pack`** (vim 8 packages — easiest):
```sh
mkdir -p ~/.vim/pack/local/start
git clone <this-repo-url> ~/.vim/pack/local/start/gcc-only-ide
```

**Option B: clone anywhere, add to `runtimepath` in vimrc**:
```vim
set runtimepath+=/path/to/gcc-only-ide
```

Either way, restart vim. Sanity-check with `:GccideStatus` — it
should print `alive`.

## Configure

Add to your vimrc, **before** the plugin loads (so step 2 happens
first):

```vim
" Required. Absolute path to the directory that holds the
" Makefile you want the plugin to run for diagnostics.
let g:gccide_project_root = '/abs/path/to/your/project'

" Optional. Where the source tree lives, for the identifier
" index. Falls back to g:gccide_project_root when unset; set this
" explicitly if your Makefile is in a separate folder from the
" .c/.h files.
let g:gccide_source_root  = '/abs/path/to/your/src'

" Optional. Command the diagnostic engine invokes. Default 'make'.
" Set to your build wrapper if you have one.
" let g:gccide_make_cmd = '/abs/path/to/build.sh'
```

That's it. Open a `.c`/`.cpp`/`.h` buffer and you're running:

- On plugin load, the identifier index is built async. First run
  scans the source tree; subsequent runs are no-ops if nothing
  changed (mtime-gated). Disable with
  `let g:gccide_index_on_startup = 0`.
- `:w` triggers diagnostics (runs your Makefile, parses stderr,
  drops signs in the gutter, populates the quickfix list).
- `:w` also refreshes the identifier index for just the saved
  file — your newly-typed identifiers complete immediately.

## Commands

| Command            | What it does                                   |
| ------------------ | ---------------------------------------------- |
| `:GccideStatus`    | Sanity check. Echoes `alive`.                  |
| `:GccideFlags`     | Show the compile flags extracted for the current buffer. |
| `:GccideDiag`      | Run the diagnostic build now.                  |
| `:GccideDiagClear` | Wipe diagnostic signs + quickfix.              |
| `:GccideIndex`     | Build (or refresh) the identifier index.       |
| `:GccideFind <sym>`| Quickfix-list every definition of `<sym>`.     |
| `:GccideGoto`      | Same as the `gd` mapping (jump to definition under cursor). |

## Mappings

| Keys              | Mode | Action                                       |
| ----------------- | ---- | -------------------------------------------- |
| `gd`              | n    | Jump to definition of the word under cursor. |
| `<C-x><C-o>`      | i    | Trigger identifier-prefix autocomplete.      |

`gd` shadows vim's built-in `gd` (goto local declaration), which is
rarely useful in multi-file C projects. To pick a different key,
unmap `gd` and bind `<Plug>(gccide-goto-def)`:

```vim
let g:gccide_auto = 0           " disable our defaults
nmap <leader>gd <Plug>(gccide-goto-def)
```

## Configuration variables

| Variable                    | Default       | Effect                                    |
| --------------------------- | ------------- | ----------------------------------------- |
| `g:gccide_project_root`     | _(required)_  | Directory containing your Makefile.       |
| `g:gccide_source_root`      | project_root  | Where `.c`/`.cpp`/`.h` files live.        |
| `g:gccide_make_cmd`         | `'make'`      | Diagnostic command. Always run via `sh -c` after `cd` into project_root. |
| `g:gccide_index_path`       | `<project_root>/.gccide/index` | Override the index file location. |
| `g:gccide_split_cmd`        | `'tabedit'`   | Open command for cross-file go-to-def. Set `'split'` or `'vsplit'` for in-window splits. |
| `g:gccide_index_on_startup` | `1`           | Auto-build the index when the plugin loads. |
| `g:gccide_auto`             | `1`           | Master switch: install the BufWritePost autocmds, the FileType omnifunc autocmd, the default `gd` mapping, and the startup index build. Set to 0 to wire everything manually. |

## Verification

Each phase ships a manual checklist under `tests/manual/`. They
run on any machine with `vim80` available and exercise the plugin
end-to-end against the bundled fixture in `tests/fixtures/proj/`.
Start with `tests/manual/p0.md` if you want to verify the install
top-to-bottom; jump to the phase you're touching otherwise.

## Where to read more

- `docs/ARCHITECTURE.md` — how the pieces fit together and why.
- `docs/CONVENTIONS.md` — coding conventions for contributors.
- `docs/ROADMAP.md` — phase plan, scope, and what's intentionally
  out.
- `docs/JOURNAL.md` — append-only design history.
- `docs/STATE.md` — current state, open questions, next steps.
- `CLAUDE.md` / `AGENTS.md` — AI-agent instructions (identical
  pointers into `docs/`).

## Limitations to be aware of

- The plugin only touches `.c`, `.cpp`, `.cc`, `.cxx`, `.h`,
  `.hpp`, `.hh`, `.hxx`. Other file types are ignored.
- Identifier completion is exactly that — identifier-based,
  prefix-matched. It does not understand types, scopes, or
  membership. That's intentional: the surface is pluggable so a
  semantic backend can slot in later (`gccide#complete#register_source(Funcref)`).
- Diagnostics run the project's Makefile; they do **not**
  re-invoke gcc per buffer or live-while-typing. Save (`:w`) to
  re-run.
- The index walker uses a regex, not a parser. It catches the
  common cases (functions with `{` near the signature, single-line
  typedefs, trailing typedef names after multi-line aggregates,
  struct/union/enum tags, file-scope globals via a loose pattern).
  Multi-line K&R function signatures and a handful of edge-case
  declarations may be missed. The cost of a miss is a missing
  completion or go-to-def hit, never a vim hang.
