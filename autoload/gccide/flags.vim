" Project detection + compile-flag extraction.
" Source of truth for every later phase that needs gcc flags.

" Cache shape: {root: {'mtime': int, 'files': {absfile: [flags]}}}
let s:cache = {}
" Live job state, keyed by root: {root: {'lines': [...]}}.
let s:jobs = {}

" --- Project root -----------------------------------------------------

" The project root is `g:gccide_project_root` — required, no auto-detect.
" The Makefile typically lives outside the source tree and an upward
" walk would not find it. Both the prompting and quiet variants exist
" only so older call sites stay valid; behaviour is identical.

function! gccide#flags#project_root_quiet(...) abort
  if !exists('g:gccide_project_root') || empty(g:gccide_project_root)
    return ''
  endif
  return substitute(fnamemodify(g:gccide_project_root, ':p'), '/$', '', '')
endfunction

function! gccide#flags#project_root(...) abort
  let l:r = gccide#flags#project_root_quiet()
  if empty(l:r)
    echohl WarningMsg
    echom 'gccide: g:gccide_project_root not set (point it at the Makefile directory)'
    echohl None
  endif
  return l:r
endfunction

" --- Cache helpers ----------------------------------------------------

function! s:cache_dir(root) abort
  return a:root . '/.gccide'
endfunction

function! s:cache_file(root) abort
  return s:cache_dir(a:root) . '/flags'
endfunction

function! s:makefile_mtime(root) abort
  return getftime(a:root . '/Makefile')
endfunction

function! s:load_disk(root) abort
  let l:path = s:cache_file(a:root)
  if !filereadable(l:path)
    return {}
  endif
  try
    return json_decode(join(readfile(l:path), "\n"))
  catch
    return {}
  endtry
endfunction

function! s:save_disk(root, data) abort
  let l:dir = s:cache_dir(a:root)
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  call writefile([json_encode(a:data)], s:cache_file(a:root))
endfunction

" --- Make output parsing ----------------------------------------------

let s:src_re = '\v\.(c|cpp|cc|cxx|h|hpp|hh|hxx)$'
let s:cc_re  = '\v(^|/)(gcc|g\+\+|cc|c\+\+)([-.][0-9.]+)?$'

" Flags that take a separate following token; the token is folded in
" so the cached flag is self-contained (e.g. '-I' 'foo' -> '-Ifoo').
let s:two_arg = {
      \ '-I':1, '-D':1, '-U':1,
      \ '-isystem':1, '-iquote':1, '-idirafter':1,
      \ '-include':1, '-imacros':1, '-x':1,
      \ }
" Flags to discard. Anything in s:drop_with_arg also eats the next token.
let s:drop = {'-c':1, '-S':1, '-E':1,
      \ '-MD':1, '-MMD':1, '-MM':1, '-M':1, '-MP':1, '-MG':1}
let s:drop_with_arg = {'-o':1, '-MF':1, '-MT':1, '-MQ':1}

function! s:is_compile_line(tokens) abort
  for l:tok in a:tokens
    if l:tok =~# s:cc_re
      return 1
    endif
  endfor
  return 0
endfunction

function! s:parse_line(line, cwd) abort
  let l:tokens = split(a:line)
  if !s:is_compile_line(l:tokens)
    return {}
  endif

  let l:file = ''
  let l:flags = []
  let l:saw_cc = 0
  let l:i = 0
  let l:n = len(l:tokens)
  while l:i < l:n
    let l:t = l:tokens[l:i]
    if !l:saw_cc
      if l:t =~# s:cc_re
        let l:saw_cc = 1
      endif
      let l:i += 1
      continue
    endif

    if has_key(s:drop_with_arg, l:t)
      let l:i += 2
      continue
    endif
    if has_key(s:drop, l:t)
      let l:i += 1
      continue
    endif
    if has_key(s:two_arg, l:t)
      if l:i + 1 < l:n
        call add(l:flags, l:t . l:tokens[l:i + 1])
        let l:i += 2
      else
        let l:i += 1
      endif
      continue
    endif
    if l:t =~# '^-'
      call add(l:flags, l:t)
      let l:i += 1
      continue
    endif
    if empty(l:file) && l:t =~? s:src_re
      let l:file = l:t
    endif
    let l:i += 1
  endwhile

  if empty(l:file)
    return {}
  endif
  let l:abs = l:file =~# '^/' ? l:file : simplify(a:cwd . '/' . l:file)
  return {'file': l:abs, 'flags': l:flags}
endfunction

" GNU make prints "Entering directory '/abs/path'" on recursion. Track it so
" relative source paths resolve correctly. Falls back to root if make was
" invoked with --no-print-directory.
let s:enter_re = "\\vmake[^:]*: Entering directory [`']([^']+)'"
let s:leave_re = "\\vmake[^:]*: Leaving directory [`']([^']+)'"

function! s:parse_output(lines, root) abort
  let l:result = {}
  let l:stack = [a:root]
  for l:line in a:lines
    let l:m = matchlist(l:line, s:enter_re)
    if !empty(l:m)
      call add(l:stack, l:m[1])
      continue
    endif
    let l:m = matchlist(l:line, s:leave_re)
    if !empty(l:m)
      if len(l:stack) > 1
        call remove(l:stack, -1)
      endif
      continue
    endif
    let l:parsed = s:parse_line(l:line, l:stack[-1])
    if empty(l:parsed)
      continue
    endif
    let l:result[l:parsed.file] = l:parsed.flags
  endfor
  return l:result
endfunction

" --- Async extraction -------------------------------------------------

function! s:on_stdout(root, ch, msg) abort
  if !has_key(s:jobs, a:root)
    return
  endif
  call add(s:jobs[a:root].lines, a:msg)
endfunction

function! s:on_exit(root, job, status) abort
  if !has_key(s:jobs, a:root)
    return
  endif
  let l:lines = s:jobs[a:root].lines
  call remove(s:jobs, a:root)

  let l:files = s:parse_output(l:lines, a:root)
  let l:mtime = s:makefile_mtime(a:root)
  let s:cache[a:root] = {'mtime': l:mtime, 'files': l:files, 'status': 'ready'}
  call s:save_disk(a:root, {'mtime': l:mtime, 'files': l:files})

  echohl ModeMsg
  echom printf('gccide: flags ready for %s (%d files)', a:root, len(l:files))
  echohl None
endfunction

" Returns the {absfile: flags} dict if cached, else {} and kicks off a job.
function! gccide#flags#extract(root) abort
  if empty(a:root) || !isdirectory(a:root)
    return {}
  endif
  let l:mtime = s:makefile_mtime(a:root)

  if has_key(s:cache, a:root)
        \ && get(s:cache[a:root], 'status', '') ==# 'ready'
        \ && s:cache[a:root].mtime == l:mtime
    return s:cache[a:root].files
  endif

  if has_key(s:jobs, a:root)
    return {}
  endif

  let l:disk = s:load_disk(a:root)
  if !empty(l:disk) && get(l:disk, 'mtime', -1) == l:mtime
    let s:cache[a:root] = {'mtime': l:mtime, 'files': l:disk.files, 'status': 'ready'}
    return l:disk.files
  endif

  let s:jobs[a:root] = {'lines': []}
  let l:cmd = ['sh', '-c', 'cd ' . shellescape(a:root) . ' && make -Bnk 2>/dev/null']
  call job_start(l:cmd, {
        \ 'out_cb':  function('s:on_stdout', [a:root]),
        \ 'exit_cb': function('s:on_exit',   [a:root]),
        \ 'in_io':   'null',
        \ })
  let s:cache[a:root] = {'mtime': -1, 'files': {}, 'status': 'extracting'}
  echom 'gccide: extracting compile flags from ' . a:root . '/Makefile ...'
  return {}
endfunction

function! gccide#flags#for_file(file) abort
  let l:abs = fnamemodify(a:file, ':p')
  let l:root = gccide#flags#project_root_quiet(l:abs)
  if empty(l:root)
    return []
  endif
  let l:files = gccide#flags#extract(l:root)
  if has_key(l:files, l:abs)
    return l:files[l:abs]
  endif
  " Headers don't appear in 'make -Bnk' output. Borrow flags from any TU
  " in the same project so syntax-only checks still produce useful output.
  if a:file =~? '\v\.(h|hpp|hh|hxx)$'
    for l:tu in keys(l:files)
      if l:tu =~? '\v\.(c|cpp|cc|cxx)$'
        return l:files[l:tu]
      endif
    endfor
  endif
  return []
endfunction

" --- :GccideFlags surface ---------------------------------------------

function! gccide#flags#show() abort
  let l:file = expand('%:p')
  if empty(l:file)
    echohl WarningMsg | echom 'gccide: no file in current buffer' | echohl None
    return
  endif
  let l:root = gccide#flags#project_root(l:file)
  if empty(l:root)
    echohl WarningMsg | echom 'gccide: no Makefile found' | echohl None
    return
  endif
  let l:was_running = has_key(s:jobs, l:root)
  let l:files = gccide#flags#extract(l:root)
  if empty(l:files)
    if l:was_running
      echom 'gccide: still extracting; re-run :GccideFlags when notified'
    elseif !has_key(s:jobs, l:root)
      echom 'gccide: no compile lines parsed from ' . l:root . '/Makefile'
    endif
    return
  endif
  let l:flags = get(l:files, l:file, [])
  echo 'root:  ' . l:root
  echo 'file:  ' . l:file
  if empty(l:flags)
    echo printf('flags: (none for this buffer; project has %d files indexed)', len(l:files))
  else
    echo 'flags: ' . join(l:flags, ' ')
  endif
endfunction
