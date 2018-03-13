" FZF wrappers to be used with neoview.
" Author:  Andrew Pyatkov <mrbiggfoot@gmail.com>
" License: MIT
"------------------------------------------------------------------------------

" Save cpo.
let s:save_cpo = &cpo
set cpo&vim

"------------------------------------------------------------------------------

function! neoview#fzf#run(fzf_win_cmd, preview_win_cmd, source, view_fn)
  let id = neoview#create(a:fzf_win_cmd, a:preview_win_cmd, a:view_fn)
  if a:fzf_win_cmd != ''
    exec a:fzf_win_cmd
  endif
  let prefix = (a:source == '') ? '' : '(' . a:source . ')|'
  let fzf = 'fzf --preview="' . neoview#script_name() . ' ' . id .
    \ ' {}" --preview-window=right:0'
  let cmd = prefix . fzf
  call termopen(cmd)
endfunction

"------------------------------------------------------------------------------

" Restore cpo.
let &cpo = s:save_cpo
unlet s:save_cpo
