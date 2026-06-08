" gcc-only-ide: plugin entry point
" Loaded by vim on startup. Keep this file tiny: declare the load guard,
" register user-facing commands, and defer the real work to autoload/.

if exists('g:loaded_gccide')
  finish
endif
let g:loaded_gccide = 1

command! GccideStatus       echo gccide#status()
command! GccideFlags        call gccide#flags#show()
command! GccideDiag         call gccide#diag#run()
command! GccideDiagClear    call gccide#diag#clear()
command! GccideIndex        call gccide#index#build()
command! -nargs=1 GccideFind call gccide#index#find(<q-args>)
command! GccideGoto         call gccide#goto#def()
command! GccideLogRefresh   call gccide#log#refresh()
command! -nargs=? GccideLogPoll
      \ call gccide#log#enable_poll(<q-args> == '' ? 0 : str2nr(<q-args>))

nnoremap <silent> <Plug>(gccide-goto-def) :<C-u>call gccide#goto#def()<CR>

if get(g:, 'gccide_auto', 1)
  " P2 run-make-on-save is now opt-in. Set g:gccide_diag_make = 1 if
  " you do have build access and want :w to run the project Makefile.
  if get(g:, 'gccide_diag_make', 0)
    augroup gccide_diag
      autocmd!
      autocmd BufWritePost *.c,*.cpp,*.cc,*.cxx,*.h,*.hpp,*.hh,*.hxx
            \ call gccide#diag#run()
    augroup END
  endif
  augroup gccide_complete
    autocmd!
    autocmd FileType c,cpp setlocal omnifunc=gccide#complete#omnifunc
  augroup END
  augroup gccide_index
    autocmd!
    autocmd BufWritePost *.c,*.cpp,*.cc,*.cxx,*.h,*.hpp,*.hh,*.hxx
          \ call gccide#index#refresh_file(expand('<afile>:p'))
  augroup END
  if !hasmapto('<Plug>(gccide-goto-def)') && empty(maparg('gd', 'n'))
    nmap gd <Plug>(gccide-goto-def)
  endif
  " Auto-start log polling when both the path and a positive poll
  " interval are set in the vimrc. Manual :GccideLogPoll <ms> works
  " at runtime regardless; :GccideLogPoll 0 stops the timer.
  if !empty(get(g:, 'gccide_log_path', '')) && get(g:, 'gccide_log_poll_ms', 0) > 0
    call gccide#log#enable_poll(g:gccide_log_poll_ms)
  endif
  " Kick off an index build at plugin-load time when a project root is
  " configured. Vim sources plugin/* AFTER the user's vimrc, so the
  " required vars are already visible. The build is async (job_start
  " returns immediately) and the P6 mtime gate makes it a no-op when
  " nothing has changed on disk since the last persist. Opt out with
  " `let g:gccide_index_on_startup = 0` in your vimrc before this
  " plugin loads.
  if get(g:, 'gccide_index_on_startup', 1)
        \ && (!empty(get(g:, 'gccide_project_root', ''))
        \ || !empty(get(g:, 'gccide_source_root', '')))
    call gccide#index#build()
  endif
endif
