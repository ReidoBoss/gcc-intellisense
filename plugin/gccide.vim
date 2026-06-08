" gcc-only-ide: plugin entry point
" Loaded by vim on startup. Keep this file tiny: declare the load guard,
" register user-facing commands, and defer the real work to autoload/.

if exists('g:loaded_gccide')
  finish
endif
let g:loaded_gccide = 1

command! GccideStatus     echo gccide#status()
command! GccideFlags      call gccide#flags#show()
command! GccideDiag       call gccide#diag#run()
command! GccideDiagClear  call gccide#diag#clear()
command! GccideIndex      call gccide#index#build()
command! -nargs=1 GccideFind call gccide#index#find(<q-args>)
command! GccideGoto       call gccide#goto#def()

nnoremap <silent> <Plug>(gccide-goto-def) :<C-u>call gccide#goto#def()<CR>

if get(g:, 'gccide_auto', 1)
  augroup gccide_diag
    autocmd!
    autocmd BufWritePost *.c,*.cpp,*.cc,*.cxx,*.h,*.hpp,*.hh,*.hxx
          \ call gccide#diag#run()
  augroup END
  augroup gccide_complete
    autocmd!
    autocmd FileType c,cpp setlocal omnifunc=gccide#complete#omnifunc
  augroup END
  if !hasmapto('<Plug>(gccide-goto-def)') && empty(maparg('gd', 'n'))
    nmap gd <Plug>(gccide-goto-def)
  endif
endif
