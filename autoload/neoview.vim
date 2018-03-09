" Neovim plugin for showing preview in a neovim window.
" Author:  Andrew Pyatkov <mrbiggfoot@gmail.com>
" License: MIT
"------------------------------------------------------------------------------

" Save cpo.
let s:save_cpo = &cpo
set cpo&vim

"------------------------------------------------------------------------------

" Common vars.
let s:bin_dir = expand('<sfile>:h:h').'/bin/'
let s:preview_script = s:bin_dir.'neoview.py'
let s:enable_preview = 0
let s:cur_bufnr = -1      " Buffer number displayed in neoview window.
let s:cur_bufnr_excl = 0  " Whether the buffer was created exclusively
                          " for neoview.

"------------------------------------------------------------------------------

" Return neoview window number, 0 if none exists.
function! s:neoview_winnr()
  for nr in range(1, winnr('$'))
    if getwinvar(nr, 'neoview')
      return nr
    endif
  endfor
  return 0
endfunction

"------------------------------------------------------------------------------

" Open neoview window using s:create_cmd.
function! s:open_neoview()
  exec s:create_cmd
  let nr = winnr()
  call setwinvar(nr, 'neoview', 1)
  wincmd p
  return nr
endfunction

"------------------------------------------------------------------------------

" Get preview script name.
function! neoview#script_name()
  return s:preview_script
endfunction

"------------------------------------------------------------------------------

" Open neoview window if required and call preview_fn(context_str).
function! neoview#update(create_cmd, preview_fn, context_str)
  echom 'neoview#update("'.a:create_cmd.'", "'.a:preview_fn.'", "'.a:context_str.'")'
  let s:create_cmd = a:create_cmd
  let s:preview_fn = a:preview_fn
  let s:context_str = a:context_str
  if !s:enable_preview
    return
  endif

  " Find out neoview window number.
  let neoview_winnr = s:neoview_winnr()
  if !neoview_winnr
    let neoview_winnr = s:open_neoview()
  endif

  " Close the buffer displayed in the neoview window if this buffer was opened
  " exclusively for neoview and contains no unsaved changes. Will be closed
  " only if the next preview opens a new buffer.
  if s:cur_bufnr != -1 && s:cur_bufnr_excl && !getbufvar(s:cur_bufnr, "&mod")
    let del_buf = s:cur_bufnr
  endif
  let buf_count = len(getbufinfo({'buflisted': 1}))

  " Change focus to neoview window.
  exec neoview_winnr.'wincmd w'

  " Call the preview function that will set the neoview window content based
  " on the context_str.
  exec 'call '.s:preview_fn.'(\"'.s:context_str.'\")'

  " Return focus to where it was.
  wincmd p

  " Maybe delete the previously previewed buffer.
  let new_bufnr = winbufnr(neoview_winnr)
  if new_bufnr != s:cur_bufnr
    let s:cur_bufnr_excl = (len(getbufinfo({'buflisted': 1})) > buf_count)
    let s:cur_bufnr = new_bufnr
    if exists('del_buf')
      bd del_buf
    endif
  endif
endfunction

"------------------------------------------------------------------------------

" Restore cpo.
let &cpo = s:save_cpo
unlet s:save_cpo
