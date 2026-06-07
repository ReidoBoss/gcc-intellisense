" Diagnostics: async 'gcc -fsyntax-only' against the live buffer.
" Signs in the gutter + items in the quickfix list.

" {bufnr: timer_id}
let s:timers = {}
" {bufnr: [sign_id, ...]}  -- our placed sign IDs, so we can unplace them.
let s:signs = {}
" {bufnr: job} — only the most-recent in-flight job per buffer. exit_cb
" compares against this to decide whether its result should still update
" signs (a newer keystroke may have preempted the run). Tempfile cleanup
" is unconditional because the file paths are bound into the exit_cb
" partial, not stored here.
let s:jobs = {}
" Repeating timer that pulses job_status() on all in-flight jobs every
" 100 ms. Without this, vim 8.0's main loop does not wake up to reap an
" exited child until some unrelated event (next keystroke, redraw)
" happens — interactive users see multi-second sign-update delays.
" The pulse self-stops once s:jobs is empty.
let s:pulse_timer = -1
" Monotonic counter for sign ids. We avoid sign groups (8.1+) and manage
" lifecycle by id, scoped per buffer.
let s:sign_id = 12000

function! s:ensure_defines() abort
  if exists('s:defined') | return | endif
  silent! sign define GccideError   text=E> texthl=ErrorMsg
  silent! sign define GccideWarning text=W> texthl=WarningMsg
  silent! sign define GccideNote    text=N> texthl=Comment
  let s:defined = 1
endfunction

function! s:clear_signs(bufnr) abort
  if !has_key(s:signs, a:bufnr) | return | endif
  for l:id in s:signs[a:bufnr]
    silent! execute printf('sign unplace %d buffer=%d', l:id, a:bufnr)
  endfor
  let s:signs[a:bufnr] = []
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

function! s:lang_for(file) abort
  return a:file =~? '\v\.(cpp|cc|cxx|hpp|hh|hxx)$' ? 'c++' : 'c'
endfunction

" gcc 8 diagnostic line: '<file>:<line>:<col>: <severity>: <msg>'.
" When we pipe via stdin, <file> is the literal '<stdin>'.
" Severity may be 'fatal error', 'error', 'warning', or 'note'.
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
            \ 'lnum': str2nr(l:m[2]),
            \ 'col':  str2nr(l:m[3]),
            \ 'sev':  l:m[4],
            \ 'text': l:m[5],
            \ })
      continue
    endif
    let l:m = matchlist(l:line, s:diag_nocol_re)
    if !empty(l:m)
      call add(l:items, {
            \ 'lnum': str2nr(l:m[2]),
            \ 'col':  1,
            \ 'sev':  l:m[3],
            \ 'text': l:m[4],
            \ })
    endif
  endfor
  return l:items
endfunction

function! s:on_exit(bufnr, errfile, srcfile, job, status) abort
  let l:lines = filereadable(a:errfile) ? readfile(a:errfile) : []
  call delete(a:errfile)
  call delete(a:srcfile)
  " A newer keystroke may have started another job between when this one
  " was launched and when it exited; in that case, discard this result.
  if !has_key(s:jobs, a:bufnr) || s:jobs[a:bufnr] isnot a:job
    return
  endif
  call remove(s:jobs, a:bufnr)
  if !bufexists(a:bufnr) | return | endif

  call s:ensure_defines()
  call s:clear_signs(a:bufnr)

  let l:items = s:parse_diags(l:lines)
  let l:qfitems = []
  for l:d in l:items
    call s:place_sign(a:bufnr, l:d.lnum, s:severity_to_sign(l:d.sev))
    call add(l:qfitems, {
          \ 'bufnr': a:bufnr,
          \ 'lnum':  l:d.lnum,
          \ 'col':   l:d.col,
          \ 'type':  s:severity_to_qftype(l:d.sev),
          \ 'text':  l:d.sev . ': ' . l:d.text,
          \ })
  endfor
  call setqflist(l:qfitems, 'r')
  call setqflist([], 'a', {'title': 'gccide'})
endfunction

function! gccide#diag#run(bufnr) abort
  if !bufexists(a:bufnr) | return | endif
  if !exists('g:gccide_gcc') || empty(g:gccide_gcc)
    echohl WarningMsg
    echom 'gccide: g:gccide_gcc is not set (e.g. let g:gccide_gcc = "/path/to/gcc")'
    echohl None
    return
  endif
  if !executable(g:gccide_gcc)
    echohl WarningMsg | echom 'gccide: g:gccide_gcc not executable: ' . g:gccide_gcc | echohl None
    return
  endif

  let l:file = fnamemodify(bufname(a:bufnr), ':p')
  if empty(l:file) || l:file !~? '\v\.(c|cpp|cc|cxx|h|hpp|hh|hxx)$'
    return
  endif

  let l:root = gccide#flags#project_root_quiet(l:file)
  if empty(l:root)
    return
  endif
  let l:flags = gccide#flags#for_file(l:file)

  " Drop any prior in-flight job for this buffer; we only want the
  " latest result to win. The old job's exit_cb still runs and cleans
  " up its own tempfiles, but its result is discarded (see on_exit).
  if has_key(s:jobs, a:bufnr)
    try
      call job_stop(s:jobs[a:bufnr])
    catch
    endtry
    call remove(s:jobs, a:bufnr)
  endif

  let l:lang = s:lang_for(l:file)
  let l:srcfile = tempname() . (l:lang ==# 'c++' ? '.cpp' : '.c')
  call writefile(getbufline(a:bufnr, 1, '$'), l:srcfile)
  let l:errfile = tempname()

  let l:argv = [g:gccide_gcc, '-fsyntax-only', '-x', l:lang] + l:flags + [l:srcfile]
  let l:argv_shell = join(map(copy(l:argv), 'shellescape(v:val)'), ' ')
  let l:cmd = ['sh', '-c', 'cd ' . shellescape(l:root) . ' && ' . l:argv_shell]

  let l:job = job_start(l:cmd, {
        \ 'in_io':    'null',
        \ 'out_io':   'null',
        \ 'err_io':   'file',
        \ 'err_name': l:errfile,
        \ 'exit_cb':  function('s:on_exit', [a:bufnr, l:errfile, l:srcfile]),
        \ })
  let s:jobs[a:bufnr] = l:job
  call s:ensure_pulse()
endfunction

function! s:ensure_pulse() abort
  if s:pulse_timer != -1
    return
  endif
  let s:pulse_timer = timer_start(100, function('s:pulse'), {'repeat': -1})
endfunction

function! s:pulse(tid) abort
  if empty(s:jobs)
    call timer_stop(s:pulse_timer)
    let s:pulse_timer = -1
    return
  endif
  for l:job in values(s:jobs)
    call job_status(l:job)
  endfor
endfunction

" Blocking wait used by manual tests in batch (-S) mode. Vim's main loop
" runs naturally between keystrokes, so interactive use never needs this
" — but in `vim80 -S script.vim`, ':sleep' alone doesn't reap exited
" children. Calling job_status() in the loop forces the reap; once the
" exit_cb fires, the s:jobs entry is removed and we return.
function! gccide#diag#_wait_done(bufnr, timeout_ms) abort
  let l:elapsed = 0
  while has_key(s:jobs, a:bufnr) && l:elapsed < a:timeout_ms
    call job_status(s:jobs[a:bufnr])
    sleep 50m
    let l:elapsed += 50
  endwhile
endfunction

function! s:fire(bufnr, tid) abort
  if has_key(s:timers, a:bufnr)
    call remove(s:timers, a:bufnr)
  endif
  call gccide#diag#run(a:bufnr)
endfunction

" Live (typing-time) diagnostics are opt-in via g:gccide_live. A big TU
" can take seconds for gcc to check; rerunning on every TextChanged debounce
" would be a lot of wasted work. Save-only (BufWritePost) is the default.
function! gccide#diag#schedule(bufnr) abort
  if !get(g:, 'gccide_live', 0)
    return
  endif
  if has_key(s:timers, a:bufnr)
    call timer_stop(s:timers[a:bufnr])
  endif
  let l:ms = get(g:, 'gccide_debounce_ms', 300)
  let s:timers[a:bufnr] = timer_start(l:ms, function('s:fire', [a:bufnr]))
endfunction

function! gccide#diag#clear(bufnr) abort
  call s:clear_signs(a:bufnr)
  call setqflist([], 'r')
  call setqflist([], 'a', {'title': 'gccide'})
endfunction
