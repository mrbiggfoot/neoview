" FZF wrappers to be used with neoview.
" Author:  Andrew Pyatkov <mrbiggfoot@gmail.com>
" License: MIT
"------------------------------------------------------------------------------

" Save cpo.
let s:save_cpo = &cpo
set cpo&vim

"------------------------------------------------------------------------------

function! neoview#fzf#run(fzf_win_cmd, preview_win_cmd, source, preview_fn)
  if a:fzf_win_cmd != ''
    exec a:fzf_win_cmd
  endif
  let prefix = (a:source == '') ? '' : '(' . a:source . ')|'
  let fzf = 'fzf --preview="' . neoview#script_name() . " '" .
    \ a:preview_win_cmd . "' " . a:preview_fn .
    \ ' {}" --preview-window=right:0'
  let cmd = prefix . fzf
"  echom cmd
  call termopen(cmd)
endfunction

"------------------------------------------------------------------------------

" Restore cpo.
let &cpo = s:save_cpo
unlet s:save_cpo
