" FZF wrappers to be used with neoview.
" Author:  Andrew Pyatkov <mrbiggfoot@gmail.com>
" License: MIT
"------------------------------------------------------------------------------

" Save cpo.
let s:save_cpo = &cpo
set cpo&vim

" Common options to be added to fzf unless 'arg.ignore_common_opt' is set.
let g:neoview_fzf_common_opt = ''

"------------------------------------------------------------------------------

" Run fzf as the searcher.
" The arguments 'arg' is a dictionary that can contain the following:
"
" fzf_win - vim command to create a window for fzf. If empty, uses the
"           current window. Can contain a sequence of commands, for
"           example: 'below 10new|set winfixheight'.
"
" preview_win - vim command to create the preview window when fzf is
"               running and toggle preview key is pressed (which is <F1>
"               by default). Relative to the search window, e.g.
"               'above 20new'. If empty, tries to use an existing window
"               in this order: above the search window, below the search
"               window, left of the search window, right of the search
"               window.
"
" source - shell command which output is piped to fzf for selection. If empty,
"          fzf is executed without input. Example: 'rg --files'.
"
" view_fn - view function. If empty, the default view function is used, which
"           opens the file in read only mode for preview, and opens the file
"           in read/write mode when the candidate is selected.
"           See neoview#def_view_fn() for reference.
"
" opt - a string containing custom fzf command line options. Combined with
"       'g:neoview_fzf_common_opt' unless 'ignore_common_opt' is set.
"
" ignore_common_opt - if true, ignore 'g:neoview_fzf_common_opt'.
"
function! neoview#fzf#run(arg) "fzf_win_cmd, preview_win_cmd, source, view_fn)
  let id = neoview#create(
    \ has_key(a:arg, 'fzf_win') ? a:arg.fzf_win : '',
    \ has_key(a:arg, 'preview_win') ? a:arg.preview_win : '',
    \ has_key(a:arg, 'view_fn') ? a:arg.view_fn : '')

  " We can't just use stdout because it will contain stuff from fzf interface.
  let out = tempname()

  if has_key(a:arg, 'ignore_common_opt') && a:arg.ignore_common_opt
    let fzf_opt = ''
  else
    let fzf_opt = g:neoview_fzf_common_opt
  endif
  if has_key(a:arg, 'opt')
    let fzf_opt = fzf_opt . ' ' . a:arg.opt
  endif

  let prefix = has_key(a:arg, 'source') ? '(' . a:arg.source . ')|' : ''
  let fzf = 'fzf ' . fzf_opt . ' --preview="' . neoview#script_name() . ' ' .
    \ id . ' {}" --preview-window=right:0 > ' . out
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
