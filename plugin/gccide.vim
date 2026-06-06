" gcc-only-ide: plugin entry point
" Loaded by vim on startup. Keep this file tiny: declare the load guard,
" register user-facing commands, and defer the real work to autoload/.

if exists('g:loaded_gccide')
  finish
endif
let g:loaded_gccide = 1

command! GccideStatus echo gccide#status()
command! GccideFlags  call gccide#flags#show()
