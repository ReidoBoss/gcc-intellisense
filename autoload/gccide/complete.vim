" Autocomplete surface (omnifunc).
"
" Candidate sources are pluggable: each source is a Funcref taking a prefix
" string and returning a list of vim completion dicts
" ({word, kind, menu, dup}). A future semantic backend slots in via
" gccide#complete#register_source() without touching the omnifunc surface.

let s:sources = []

function! gccide#complete#register_source(Fn) abort
  call add(s:sources, a:Fn)
endfunction

function! gccide#complete#sources() abort
  return s:sources
endfunction

function! s:default_source(prefix) abort
  return gccide#index#candidates(a:prefix)
endfunction

function! gccide#complete#omnifunc(findstart, base) abort
  if a:findstart
    let l:line = getline('.')
    let l:start = col('.') - 1
    while l:start > 0 && l:line[l:start - 1] =~# '\w'
      let l:start -= 1
    endwhile
    return l:start
  endif

  let l:out = []
  let l:seen = {}
  for SourceFn in s:sources
    let l:cands = call(SourceFn, [a:base])
    if type(l:cands) != type([]) | continue | endif
    for l:c in l:cands
      if type(l:c) != type({}) || !has_key(l:c, 'word') | continue | endif
      if has_key(l:seen, l:c.word) | continue | endif
      let l:seen[l:c.word] = 1
      call add(l:out, l:c)
    endfor
  endfor
  if empty(l:out) && empty(gccide#complete#_index_loaded())
    echohl WarningMsg
    echom 'gccide: index empty (run :GccideIndex)'
    echohl None
  endif
  return l:out
endfunction

" Quick check used to decide whether to nudge the user toward :GccideIndex.
" Returns a non-empty string when an index is present (in-memory or on disk).
function! gccide#complete#_index_loaded() abort
  let l:stats = gccide#index#_stats()
  if l:stats.symbols > 0 | return 'mem' | endif
  if !empty(l:stats.loaded_from) | return 'disk' | endif
  return ''
endfunction

" Default source: identifier index. Registered once on first load.
if empty(s:sources)
  call gccide#complete#register_source(function('s:default_source'))
endif
