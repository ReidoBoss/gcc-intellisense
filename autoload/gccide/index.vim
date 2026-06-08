" Identifier index: walk the source tree, regex-extract symbols, persist
" {name: [{file, lnum, col, kind}]} to .gccide/index. Used by :GccideFind
" today and by P4 (autocomplete) + P5 (go-to-def) later.

" Kinds: 'f' function, 'd' #define, 't' typedef, 's' struct/union/enum tag,
"        'g' file-scope global.

let s:idx = {}
let s:idx_loaded_from = ''
let s:find_job   = v:null
let s:find_lines = []
let s:build_busy = 0
let s:pulse_timer = -1

" --- Roots + paths ----------------------------------------------------

function! gccide#index#source_root() abort
  if exists('g:gccide_source_root') && !empty(g:gccide_source_root)
    return substitute(fnamemodify(g:gccide_source_root, ':p'), '/$', '', '')
  endif
  if exists('g:gccide_project_root') && !empty(g:gccide_project_root)
    return substitute(fnamemodify(g:gccide_project_root, ':p'), '/$', '', '')
  endif
  return ''
endfunction

function! s:project_root() abort
  if exists('g:gccide_project_root') && !empty(g:gccide_project_root)
    return substitute(fnamemodify(g:gccide_project_root, ':p'), '/$', '', '')
  endif
  return gccide#index#source_root()
endfunction

function! s:index_path() abort
  if exists('g:gccide_index_path') && !empty(g:gccide_index_path)
    return fnamemodify(g:gccide_index_path, ':p')
  endif
  let l:root = s:project_root()
  if empty(l:root) | return '' | endif
  return l:root . '/.gccide/index'
endfunction

" --- Line cleaning: strip strings + comments --------------------------

" Threads block-comment state via a:state (single-element list).
function! s:clean(line, state) abort
  let l:line = a:line
  if a:state[0]
    let l:p = match(l:line, '\*/')
    if l:p < 0 | return '' | endif
    let l:line = strpart(l:line, l:p + 2)
    let a:state[0] = 0
  endif
  let l:line = substitute(l:line, '/\*.\{-}\*/', '', 'g')
  let l:bc = match(l:line, '/\*')
  if l:bc >= 0
    let l:line = strpart(l:line, 0, l:bc)
    let a:state[0] = 1
  endif
  let l:lc = match(l:line, '//')
  if l:lc >= 0
    let l:line = strpart(l:line, 0, l:lc)
  endif
  let l:line = substitute(l:line, '"[^"]*"', '""', 'g')
  let l:line = substitute(l:line, "'[^']*'", "''", 'g')
  return l:line
endfunction

" --- Extractor --------------------------------------------------------

" Function signature: <type-words> <name> (
let s:sig_re   = '\v^\s*%(static\s+|extern\s+|inline\s+|const\s+|volatile\s+|unsigned\s+|signed\s+|struct\s+|union\s+|enum\s+)*[a-zA-Z_]\w*[\w\s\*]*\s\**(\w+)\s*\('
let s:def_re   = '\v^\s*#\s*define\s+(\w+)'
let s:typedef_re_simple = '\v^\s*typedef\s+.+\s\**(\w+)\s*[;\[]'
let s:typedef_re_aggr   = '\v^\s*typedef\s+(struct|union|enum)\s+(\w+)\s*\{'
let s:tag_re   = '\v^\s*(struct|union|enum)\s+(\w+)\s*\{'
let s:global_re = '\v^\s*%(static\s+|extern\s+|const\s+|volatile\s+|unsigned\s+|signed\s+)*[a-zA-Z_]\w*[\w\s\*]*\s\**(\w+)\s*%(\[\d*\])?\s*[=;]'

" Trailing typedef name after a multi-line aggregate: '} foo_t;'
let s:typedef_trail_re = '\v^\s*\}\s*(\w+)\s*;'

function! s:extract_file(file) abort
  if !filereadable(a:file) | return [] | endif
  let l:lines = readfile(a:file)
  let l:syms  = []
  let l:depth = 0
  let l:bcstate = [0]
  let l:pending = {}
  let l:i = 0
  let l:n = len(l:lines)

  while l:i < l:n
    let l:lnum = l:i + 1
    let l:clean = s:clean(l:lines[l:i], l:bcstate)
    let l:trim  = substitute(l:clean, '^\s\+\|\s\+$', '', 'g')
    let l:start_depth = l:depth

    if l:start_depth == 0 && !empty(l:trim)
      " #define
      let l:m = matchlist(l:trim, s:def_re)
      if !empty(l:m)
        call add(l:syms, {'name': l:m[1], 'file': a:file, 'lnum': l:lnum, 'col': 1, 'kind': 'd'})
      else
        " typedef <aggregate> NAME { ... }  (emit tag now; trailing name handled below)
        let l:m = matchlist(l:trim, s:typedef_re_aggr)
        if !empty(l:m)
          call add(l:syms, {'name': l:m[2], 'file': a:file, 'lnum': l:lnum, 'col': 1, 'kind': 's'})
        else
          " simple single-line typedef: 'typedef ... NAME;'
          let l:m = matchlist(l:trim, s:typedef_re_simple)
          if !empty(l:m)
            call add(l:syms, {'name': l:m[1], 'file': a:file, 'lnum': l:lnum, 'col': 1, 'kind': 't'})
          else
            " struct/union/enum TAG { ... }
            let l:m = matchlist(l:trim, s:tag_re)
            if !empty(l:m)
              call add(l:syms, {'name': l:m[2], 'file': a:file, 'lnum': l:lnum, 'col': 1, 'kind': 's'})
            endif
            " trailing typedef name: '} foo_t;' after a multi-line aggregate
            let l:m = matchlist(l:trim, s:typedef_trail_re)
            if !empty(l:m)
              call add(l:syms, {'name': l:m[1], 'file': a:file, 'lnum': l:lnum, 'col': 1, 'kind': 't'})
            endif
          endif
        endif
      endif

      " Function: signature with body. Pending sig + '{' on this line emits.
      if !empty(l:pending) && l:trim =~# '^{'
        call add(l:syms, {'name': l:pending.name, 'file': a:file, 'lnum': l:pending.lnum, 'col': 1, 'kind': 'f'})
        let l:pending = {}
      endif
      let l:sigm = matchlist(l:trim, s:sig_re)
      if !empty(l:sigm) && stridx(l:trim, ';') < 0
        let l:name = l:sigm[1]
        if l:trim =~# '{\s*$'
          call add(l:syms, {'name': l:name, 'file': a:file, 'lnum': l:lnum, 'col': 1, 'kind': 'f'})
          let l:pending = {}
        elseif l:trim =~# ')\s*$'
          let l:pending = {'name': l:name, 'lnum': l:lnum}
        endif
      elseif !empty(l:pending) && stridx(l:trim, ';') >= 0
        " pending sig but a ';' showed up first — was a declaration
        let l:pending = {}
      endif

      " File-scope global (no '(' on the line, ends with = or ;)
      if stridx(l:trim, '(') < 0
        let l:m = matchlist(l:trim, s:global_re)
        if !empty(l:m)
          let l:nm = l:m[1]
          " filter out keywords that the loose regex may capture
          if l:nm !~# '\v^(if|else|while|for|do|switch|case|default|return|goto|break|continue|typedef|struct|union|enum|sizeof)$'
            call add(l:syms, {'name': l:nm, 'file': a:file, 'lnum': l:lnum, 'col': 1, 'kind': 'g'})
          endif
        endif
      endif
    endif

    " Update depth from this line. Strings/comments already removed.
    let l:opens  = strlen(substitute(l:clean, '[^{]', '', 'g'))
    let l:closes = strlen(substitute(l:clean, '[^}]', '', 'g'))
    let l:depth += l:opens - l:closes
    if l:depth < 0 | let l:depth = 0 | endif
    let l:i += 1
  endwhile
  return l:syms
endfunction

" --- Persistence ------------------------------------------------------

function! s:persist() abort
  let l:path = s:index_path()
  if empty(l:path) | return | endif
  let l:dir = fnamemodify(l:path, ':h')
  if !isdirectory(l:dir) | call mkdir(l:dir, 'p') | endif
  call writefile([json_encode(s:idx)], l:path)
  let s:idx_loaded_from = l:path
endfunction

function! s:load() abort
  let l:path = s:index_path()
  if empty(l:path) || !filereadable(l:path) | return 0 | endif
  try
    let s:idx = json_decode(join(readfile(l:path), "\n"))
  catch
    let s:idx = {}
    return 0
  endtry
  if type(s:idx) != type({}) | let s:idx = {} | return 0 | endif
  let s:idx_loaded_from = l:path
  return 1
endfunction

" --- Build pipeline ---------------------------------------------------

function! s:ensure_pulse() abort
  if s:pulse_timer != -1 | return | endif
  let s:pulse_timer = timer_start(100, function('s:pulse'), {'repeat': -1})
endfunction

function! s:pulse(tid) abort
  if s:find_job is v:null && !s:build_busy
    call timer_stop(s:pulse_timer)
    let s:pulse_timer = -1
    return
  endif
  if s:find_job isnot v:null
    call job_status(s:find_job)
  endif
endfunction

function! s:on_find_out(ch, msg) abort
  for l:line in split(a:msg, "\n")
    if !empty(l:line) | call add(s:find_lines, l:line) | endif
  endfor
endfunction

function! s:on_find_exit(src, job, status) abort
  if s:find_job isnot a:job | return | endif
  let s:find_job = v:null
  let l:rel = copy(s:find_lines)
  let s:find_lines = []
  if a:status != 0 && empty(l:rel)
    let s:build_busy = 0
    echohl WarningMsg | echom 'gccide: find failed (status ' . a:status . ')' | echohl None
    return
  endif
  let l:files = []
  for l:p in l:rel
    let l:q = (l:p =~# '^\./') ? strpart(l:p, 2) : l:p
    call add(l:files, a:src . '/' . l:q)
  endfor
  let s:idx = {}
  call s:parse_chunk(l:files, 0)
endfunction

function! s:parse_chunk(files, start) abort
  let l:end = min([a:start + 50, len(a:files)])
  let l:i = a:start
  while l:i < l:end
    for l:s in s:extract_file(a:files[l:i])
      if !has_key(s:idx, l:s.name)
        let s:idx[l:s.name] = []
      endif
      call add(s:idx[l:s.name], {'file': l:s.file, 'lnum': l:s.lnum, 'col': l:s.col, 'kind': l:s.kind})
    endfor
    let l:i += 1
  endwhile
  if l:end < len(a:files)
    call timer_start(1, function('s:parse_chunk_cb', [a:files, l:end]))
  else
    call s:persist()
    let s:build_busy = 0
    echohl ModeMsg
    echom printf('gccide: index built (%d symbols, %d files)', len(s:idx), len(a:files))
    echohl None
  endif
endfunction

function! s:parse_chunk_cb(files, start, tid) abort
  call s:parse_chunk(a:files, a:start)
endfunction

function! gccide#index#build() abort
  if s:build_busy
    echom 'gccide: index build already in progress'
    return
  endif
  let l:src = gccide#index#source_root()
  if empty(l:src)
    echohl WarningMsg
    echom 'gccide: g:gccide_source_root (or g:gccide_project_root) must be set'
    echohl None
    return
  endif
  if !isdirectory(l:src)
    echohl WarningMsg | echom 'gccide: source root does not exist: ' . l:src | echohl None
    return
  endif
  let s:build_busy = 1
  let s:find_lines = []
  let l:find = "find . -type f \\( -name '*.c' -o -name '*.cpp' -o -name '*.cc' -o -name '*.cxx' -o -name '*.h' -o -name '*.hpp' -o -name '*.hh' -o -name '*.hxx' \\)"
  let l:cmd = ['sh', '-c', 'cd ' . shellescape(l:src) . ' && ' . l:find]
  echom 'gccide: indexing ' . l:src . ' ...'
  let s:find_job = job_start(l:cmd, {
        \ 'in_io':   'null',
        \ 'out_cb':  function('s:on_find_out'),
        \ 'exit_cb': function('s:on_find_exit', [l:src]),
        \ })
  call s:ensure_pulse()
endfunction

" --- Lookup -----------------------------------------------------------

function! gccide#index#find(sym) abort
  if empty(s:idx)
    if !s:load()
      echohl WarningMsg | echom 'gccide: no index (run :GccideIndex)' | echohl None
      return
    endif
  endif
  if !has_key(s:idx, a:sym) || empty(s:idx[a:sym])
    echom 'gccide: not found: ' . a:sym
    call setqflist([], 'r')
    call setqflist([], 'a', {'title': 'gccide-find:' . a:sym})
    return
  endif
  let l:items = []
  for l:h in s:idx[a:sym]
    call add(l:items, {
          \ 'filename': l:h.file,
          \ 'lnum':     l:h.lnum,
          \ 'col':      l:h.col,
          \ 'text':     l:h.kind . ': ' . a:sym,
          \ })
  endfor
  call setqflist(l:items, 'r')
  call setqflist([], 'a', {'title': 'gccide-find:' . a:sym})
  copen
endfunction

" --- Exact-name lookup (consumed by goto.vim) ------------------------

" Returns the raw hit list [{file, lnum, col, kind}] for an exact name,
" or [] if missing. Lazy-loads from disk if the in-memory index is empty.
function! gccide#index#lookup(name) abort
  if empty(s:idx)
    call s:load()
  endif
  if empty(s:idx) || !has_key(s:idx, a:name) | return [] | endif
  return copy(s:idx[a:name])
endfunction

" --- Candidates (consumed by complete.vim) ---------------------------

" Returns [{word, kind, menu, dup}] for names with the given prefix.
" Lazy-loads from disk if the in-memory index is empty.
function! gccide#index#candidates(prefix) abort
  if empty(s:idx)
    call s:load()
  endif
  if empty(s:idx) | return [] | endif
  let l:p = a:prefix
  let l:plen = strlen(l:p)
  let l:out = []
  for [l:name, l:hits] in items(s:idx)
    if l:plen > 0 && strpart(l:name, 0, l:plen) !=# l:p
      continue
    endif
    let l:kind = empty(l:hits) ? '' : l:hits[0].kind
    let l:menu = empty(l:hits) ? '' : fnamemodify(l:hits[0].file, ':t')
    if len(l:hits) > 1
      let l:menu .= ' +' . (len(l:hits) - 1)
    endif
    call add(l:out, {'word': l:name, 'kind': l:kind, 'menu': l:menu, 'dup': 0})
  endfor
  call sort(l:out, {a, b -> a.word ==# b.word ? 0 : a.word ># b.word ? 1 : -1})
  return l:out
endfunction

" --- Test seam --------------------------------------------------------

function! gccide#index#_wait_done(timeout_ms) abort
  let l:elapsed = 0
  while (s:find_job isnot v:null || s:build_busy) && l:elapsed < a:timeout_ms
    if s:find_job isnot v:null | call job_status(s:find_job) | endif
    sleep 50m
    let l:elapsed += 50
  endwhile
endfunction

function! gccide#index#_stats() abort
  return {'symbols': len(s:idx), 'loaded_from': s:idx_loaded_from}
endfunction
