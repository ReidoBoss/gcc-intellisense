" Log-based diagnostics: read g:gccide_log_path, parse gcc-style error
" lines, publish via gccide#diag#publish. For environments where the
" plugin can't run `make` itself (e.g. a locked-down work laptop with
" no build access) — the build runs elsewhere, dumps stderr to a log
" file, and vim consumes it.
"
" Manual: :GccideLogRefresh.
" Optional polling: set g:gccide_log_poll_ms > 0 (or call
" gccide#log#enable_poll(ms) at runtime). Polling fires
" refresh on a timer; mtime-gated so we only re-publish when the
" file has actually changed since the last read.

let s:poll_timer = -1
let s:poll_ms    = 0
let s:last_mtime = -1

function! s:path() abort
  let l:p = get(g:, 'gccide_log_path', '')
  return empty(l:p) ? '' : fnamemodify(l:p, ':p')
endfunction

function! s:project_root() abort
  if exists('g:gccide_project_root') && !empty(g:gccide_project_root)
    return substitute(fnamemodify(g:gccide_project_root, ':p'), '/$', '', '')
  endif
  return ''
endfunction

" Read the log, parse, publish. Force=1 republishes even if mtime is
" unchanged (the manual command always does; the poller skips no-ops).
function! gccide#log#refresh(...) abort
  let l:force = a:0 ? a:1 : 1
  let l:path = s:path()
  if empty(l:path)
    echohl WarningMsg | echom 'gccide: g:gccide_log_path not set' | echohl None
    return
  endif
  if !filereadable(l:path)
    echohl WarningMsg | echom 'gccide: log file not found: ' . l:path | echohl None
    " Clear stale diagnostics if the log went away.
    call gccide#diag#publish([], s:project_root())
    let s:last_mtime = -1
    return
  endif
  let l:mtime = getftime(l:path)
  if !l:force && l:mtime == s:last_mtime
    return
  endif
  let s:last_mtime = l:mtime
  let l:items = gccide#diag#parse_lines(readfile(l:path))
  call gccide#diag#publish(l:items, s:project_root())
endfunction

function! s:on_poll(tid) abort
  call gccide#log#refresh(0)
endfunction

function! gccide#log#enable_poll(ms) abort
  call gccide#log#disable_poll()
  if a:ms <= 0 | return | endif
  let s:poll_ms = a:ms
  let s:poll_timer = timer_start(a:ms, function('s:on_poll'), {'repeat': -1})
endfunction

function! gccide#log#disable_poll() abort
  if s:poll_timer != -1
    call timer_stop(s:poll_timer)
    let s:poll_timer = -1
  endif
  let s:poll_ms = 0
endfunction

function! gccide#log#_state() abort
  return {
        \ 'path':       s:path(),
        \ 'poll_ms':    s:poll_ms,
        \ 'last_mtime': s:last_mtime,
        \ 'polling':    s:poll_timer != -1,
        \ }
endfunction
