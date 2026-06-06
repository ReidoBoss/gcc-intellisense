# Conventions

## Vimscript

- vim 8.0 syntax only. **No vim9script.** A vim9script `def`/`vim9script`
  header will fail to load on a vim that was not compiled with vim9.
- Functions in `autoload/gccide/foo.vim` are named `gccide#foo#bar()`.
- Plugin-global functions live in `autoload/gccide.vim` as `gccide#bar()`.
- Settings keys use the `g:gccide_*` prefix.
- Prefer vim builtins. If you need to look one up, do so before writing.

## Async

- Anything that touches gcc or scans more than a handful of files goes
  through `job_start()`, not `system()`.
- Use `out_cb` / `err_cb` / `exit_cb` callbacks. Never block the UI.
- Debounce text-driven re-parses through `timer_start()`.

## File-type restriction

When walking the project, scanning, parsing, indexing, or grepping, only
touch `.c`, `.cpp`, and `.h` files. Object files, build artifacts, and
generated files are out of scope.

## gcc invocation

- Always invoke `g:gccide_gcc`, not the literal string `gcc85`. The shell
  alias does not survive into `job_start()`.
- Always pass compile flags extracted from the Makefile. Never invent
  `-I` or `-D` flags.

## ctags / cscope

Availability is unknown on the user's machine. **Do not depend on them.**
If a future phase wants to use either, the docs must first add a probe
step ("ask user: do you have ctags?") rather than assume.

## Commits

- Agents may commit, but **must ask the user first** every time. State
  what you want to commit and why; wait for approval.
- Commit messages: short, imperative.

## Manual verification

- Every phase ships with a checklist at `tests/manual/<phase>.md` that
  the user runs by hand. No automated test harness.
- **Manual tests run on the user's Mac dev box, not the work laptop.**
  The Mac has real `vim80` (vim 8.0) and `gcc85` (gcc 8.5.0) installed.
  The work laptop is the deployment target but the user is not always at
  it; tests must be self-contained so the Mac is the primary verification
  surface.
- **Every coding session must end with a manual test the user can run.**
  If you touched code, the matching `tests/manual/<phase>.md` must cover
  the change. Create the file if it does not exist; extend it if it
  does. Concrete `vim80 …` invocations with an explicit "Expect:" line
  per step.
- **Ship fixtures, not placeholders.** If a checklist needs a Makefile
  project, point at `tests/fixtures/proj/` instead of asking the user to
  substitute `<PROJ>`. The user must be able to copy-paste each command
  without filling anything in.
- Hardcode absolute paths only where the user's machine matters
  (e.g. `let g:gccide_gcc = '/Users/.../gcc'` in a test). Avoid
  `<REPO>`-style substitutions; either `cd` into the repo first or use
  `set rtp+=.`.

## Tracking changes

- Append a `JOURNAL.md` entry every session. Newest at the bottom.
- Update `STATE.md` so the next agent knows where to start.
- Update `TASKS.md` so progress is visible.

## Don't

- Don't add features, abstractions, or files the current phase does not
  need.
- Don't introduce backwards-compat shims for code we have not shipped.
- Don't write long comments. One line max, only when the *why* is
  non-obvious.
- Don't edit anything outside the project root.
- Don't install. Don't download. Don't reach for any tool not on the
  whitelist in `ARCHITECTURE.md`.
