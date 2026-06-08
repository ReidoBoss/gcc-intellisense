" Go-to-definition: look up the identifier under the cursor in the index.
" Single hit  -> open in a new split, jump the cursor to (lnum, col).
" Multiple    -> populate quickfix and jump to the first.
" None        -> echo and bail.
"
" Override the open command via g:gccide_split_cmd. Default 'tabedit'
" (new tab) — set to 'split' for a horizontal split or 'vsplit' for
" vertical.

function! s:split_cmd() abort
  return get(g:, 'gccide_split_cmd', 'tabedit')
endfunction

function! s:same_position(hit) abort
  if expand('%:p') !=# fnamemodify(a:hit.file, ':p') | return 0 | endif
  return a:hit.lnum == line('.')
endfunction

function! s:jump(hit) abort
  execute s:split_cmd() . ' ' . fnameescape(a:hit.file)
  call cursor(a:hit.lnum, a:hit.col)
  normal! zz
endfunction

function! gccide#goto#def() abort
  let l:word = expand('<cword>')
  if empty(l:word)
    echom 'gccide: no word under cursor'
    return
  endif
  let l:hits = gccide#index#lookup(l:word)
  if empty(l:hits)
    echom 'gccide: no definition for ' . l:word
    return
  endif
  if len(l:hits) == 1
    if s:same_position(l:hits[0])
      echom 'gccide: already at definition of ' . l:word
      return
    endif
    call s:jump(l:hits[0])
    return
  endif
  let l:items = []
  for l:h in l:hits
    call add(l:items, {
          \ 'filename': l:h.file,
          \ 'lnum':     l:h.lnum,
          \ 'col':      l:h.col,
          \ 'text':     l:h.kind . ': ' . l:word,
          \ })
  endfor
  call setqflist(l:items, 'r')
  call setqflist([], 'a', {'title': 'gccide-goto:' . l:word})
  copen
  cfirst
endfunction
