" FZF wrappers to be used with neoview.
" Author:  Andrew Pyatkov <mrbiggfoot@gmail.com>
" License: MIT
"------------------------------------------------------------------------------

" Save cpo.
let s:save_cpo = &cpo
set cpo&vim

"------------------------------------------------------------------------------

function! neoview#fzf#def_view_fn(context_str, final)
  if a:final
    exec 'silent edit ' . a:context_str
  else
    exec 'silent view ' . a:context_str
  endif
endfunction

"------------------------------------------------------------------------------

function! neoview#fzf#run(fzf_win_cmd, preview_win_cmd, source, view_fn)
  let view_fn = (a:view_fn == '') ? 'neoview#fzf#def_view_fn' : a:view_fn
  let id = neoview#create(a:fzf_win_cmd, a:preview_win_cmd, view_fn)
  if a:fzf_win_cmd != ''
    exec a:fzf_win_cmd
  endif

  " We can't just use stdout because it will contain stuff from fzf interface.
  let out = tempname()

  let prefix = (a:source == '') ? '' : '(' . a:source . ')|'
  let fzf = 'fzf --preview="' . neoview#script_name() . ' ' . id .
    \ ' {}" --preview-window=right:0 > ' . out
  let cmd = prefix . fzf

  let opts = { 'id' : id, 'out' : out }
  function! opts.on_exit(job_id, code, event)
    if a:code == 0
      let output = readfile(self.out)
      call neoview#close(self.id, output[0])
    else
      call neoview#close(self.id, '')
    endif
    call delete(self.out)
  endfunction

  call termopen(cmd, opts)
endfunction

"------------------------------------------------------------------------------

" Restore cpo.
let &cpo = s:save_cpo
unlet s:save_cpo
