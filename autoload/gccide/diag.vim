" Diagnostics: run the project's Makefile, surface gcc errors via signs
" and the quickfix list. Single in-flight job for the whole project, not
" one per buffer — this mirrors the user's actual build workflow.

" The most-recent in-flight make job, or v:null. Newer jobs preempt
" older ones so only the latest result wins.
let s:current_job = v:null
" {bufnr: [sign_id, ...]} so we can unplace signs we placed.
let s:signs = {}
" Monotonic sign-id counter. Sign groups are vim 8.1+; we manage by id.
let s:sign_id = 12000
" 100 ms pulse forces vim's main loop to reap the child. Without it,
" exit_cb doesn't fire until some unrelated event wakes the loop —
" interactive users would see multi-second delays.
let s:pulse_timer = -1

function! s:ensure_defines() abort
  if exists('s:defined') | return | endif
  silent! sign define GccideError   text=E> texthl=ErrorMsg
  silent! sign define GccideWarning text=W> texthl=WarningMsg
  silent! sign define GccideNote    text=N> texthl=Comment
  let s:defined = 1
endfunction

function! s:clear_all_signs() abort
  for [l:bufnr, l:ids] in items(s:signs)
    for l:id in l:ids
      silent! execute printf('sign unplace %d buffer=%d', l:id, str2nr(l:bufnr))
    endfor
  endfor
  let s:signs = {}
endfunction

function! s:place_sign(bufnr, lnum, name) abort
  let s:sign_id += 1
  silent! execute printf('sign place %d line=%d name=%s buffer=%d',
        \ s:sign_id, a:lnum, a:name, a:bufnr)
  if !has_key(s:signs, a:bufnr)
    let s:signs[a:bufnr] = []
  endif
  call add(s:signs[a:bufnr], s:sign_id)
endfunction

" gcc 8 diagnostic line: '<file>:<line>:<col>: <severity>: <msg>'.
" make output uses absolute paths (per the project setup); make may
" also interleave 'In file included from …' and source-context lines,
" which the regex below ignores (no severity match).
let s:diag_re       = '\v^([^:]+):(\d+):(\d+):\s+(fatal error|error|warning|note):\s*(.*)$'
let s:diag_nocol_re = '\v^([^:]+):(\d+):\s+(fatal error|error|warning|note):\s*(.*)$'

function! s:severity_to_sign(sev) abort
  if a:sev =~? 'error'   | return 'GccideError'   | endif
  if a:sev =~? 'warning' | return 'GccideWarning' | endif
  return 'GccideNote'
endfunction

function! s:severity_to_qftype(sev) abort
  if a:sev =~? 'error'   | return 'E' | endif
  if a:sev =~? 'warning' | return 'W' | endif
  return 'I'
endfunction

function! s:parse_diags(lines) abort
  let l:items = []
  for l:line in a:lines
    let l:m = matchlist(l:line, s:diag_re)
    if !empty(l:m)
      call add(l:items, {
            \ 'file': l:m[1], 'lnum': str2nr(l:m[2]),
            \ 'col':  str2nr(l:m[3]),
            \ 'sev':  l:m[4], 'text': l:m[5],
            \ })
      continue
    endif
    let l:m = matchlist(l:line, s:diag_nocol_re)
    if !empty(l:m)
      call add(l:items, {
            \ 'file': l:m[1], 'lnum': str2nr(l:m[2]),
            \ 'col':  1,
            \ 'sev':  l:m[3], 'text': l:m[4],
            \ })
    endif
  endfor
  return l:items
endfunction

" Public: parse a list of stderr-style lines into diagnostic items.
" Returns [{file, lnum, col, sev, text}, ...]. Shared with log.vim so
" both the run-make and read-log paths use the same regex.
function! gccide#diag#parse_lines(lines) abort
  return s:parse_diags(a:lines)
endfunction

" Public: render `items` (from parse_lines) as signs + quickfix.
" Resolves any relative file paths against `root` (pass '' to skip;
" relative paths then fall through to the cwd). Used by both diag#run
" and log#refresh.
function! gccide#diag#publish(items, root) abort
  call s:ensure_defines()
  call s:clear_all_signs()
  let l:qfitems = []
  for l:d in a:items
    if l:d.file =~# '^/'
      let l:abs = l:d.file
    elseif !empty(a:root)
      let l:abs = simplify(a:root . '/' . l:d.file)
    else
      let l:abs = l:d.file
    endif
    let l:bufnr = bufnr(l:abs)
    if l:bufnr > 0 && bufloaded(l:bufnr)
      call s:place_sign(l:bufnr, l:d.lnum, s:severity_to_sign(l:d.sev))
    endif
    call add(l:qfitems, {
          \ 'filename': l:abs,
          \ 'lnum':     l:d.lnum,
          \ 'col':      l:d.col,
          \ 'type':     s:severity_to_qftype(l:d.sev),
          \ 'text':     l:d.sev . ': ' . l:d.text,
          \ })
  endfor
  call setqflist(l:qfitems, 'r')
  call setqflist([], 'a', {'title': 'gccide'})
endfunction

function! s:on_exit(errfile, root, job, status) abort
  " A newer save may have preempted this job; discard the result.
  if s:current_job isnot a:job
    call delete(a:errfile)
    return
  endif
  let l:lines = filereadable(a:errfile) ? readfile(a:errfile) : []
  call delete(a:errfile)
  let s:current_job = v:null
  call gccide#diag#publish(gccide#diag#parse_lines(l:lines), a:root)
endfunction

function! gccide#diag#run() abort
  if !exists('g:gccide_project_root') || empty(g:gccide_project_root)
    echohl WarningMsg
    echom 'gccide: g:gccide_project_root not set (point it at the Makefile directory)'
    echohl None
    return
  endif
  let l:root = substitute(fnamemodify(g:gccide_project_root, ':p'), '/$', '', '')
  if !isdirectory(l:root)
    echohl WarningMsg | echom 'gccide: project root does not exist: ' . l:root | echohl None
    return
  endif

  let l:make_cmd = get(g:, 'gccide_make_cmd', 'make')

  if s:current_job isnot v:null
    try
      call job_stop(s:current_job)
    catch
    endtry
    let s:current_job = v:null
  endif

  let l:errfile = tempname()
  " Don't redirect: gcc's errors land on sh's stderr (captured via
  " err_io='file'); make's stdout chatter lands on sh's stdout
  " (discarded via out_io='null'). The parser ignores any non-matching
  " stderr lines, so make's Entering/Leaving messages are harmless.
  let l:cmd = ['sh', '-c', 'cd ' . shellescape(l:root) . ' && ' . l:make_cmd]
  let l:job = job_start(l:cmd, {
        \ 'in_io':    'null',
        \ 'out_io':   'null',
        \ 'err_io':   'file',
        \ 'err_name': l:errfile,
        \ 'exit_cb':  function('s:on_exit', [l:errfile, l:root]),
        \ })
  let s:current_job = l:job
  call s:ensure_pulse()
endfunction

function! s:ensure_pulse() abort
  if s:pulse_timer != -1 | return | endif
  let s:pulse_timer = timer_start(100, function('s:pulse'), {'repeat': -1})
endfunction

function! s:pulse(tid) abort
  if s:current_job is v:null
    call timer_stop(s:pulse_timer)
    let s:pulse_timer = -1
    return
  endif
  call job_status(s:current_job)
endfunction

function! gccide#diag#clear() abort
  call s:clear_all_signs()
  call setqflist([], 'r')
  call setqflist([], 'a', {'title': 'gccide'})
endfunction

" Blocking wait for batch tests. Interactive vim doesn't need this.
function! gccide#diag#_wait_done(timeout_ms) abort
  let l:elapsed = 0
  while s:current_job isnot v:null && l:elapsed < a:timeout_ms
    call job_status(s:current_job)
    sleep 50m
    let l:elapsed += 50
  endwhile
endfunction
