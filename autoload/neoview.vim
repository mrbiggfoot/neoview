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
let s:neoview_id = 0

" Maps neoview_id to the current state. An entry is added by neoview#create()
" and removed by neoview#close() calls.
"
" A state consists of:
"
" search_win_cmd  - string, vim command to create the search window.
" preview_win_cmd - string, vim command to create the preview window.
" view_fn         - string, vim script function name to be called on
"                   candidate for both preview and action.
" enable_preview  - bool, whether preview window is enabled.
" cur_bufnr       - int, buffer number displayed in neoview window.
" cur_bufnr_excl  - bool, whether the buffer was created exclusively
"                   for neoview.
" context_str     - string, set to the last context_str from neoview#update().
let s:state = {}

"------------------------------------------------------------------------------

" Return neoview window number with the specified id, 0 if none exists.
function! s:neoview_winnr(id)
  for nr in range(1, winnr('$'))
    if getwinvar(nr, 'neoview') == a:id
      return nr
    endif
  endfor
  return 0
endfunction

"------------------------------------------------------------------------------

" Open neoview window using preview_win_cmd.
function! s:open_neoview(id)
  exec s:state[a:id].preview_win_cmd
  let nr = winnr()
  call setwinvar(nr, 'neoview', a:id)
  wincmd p
  return nr
endfunction

"------------------------------------------------------------------------------

" Get preview script name.
function! neoview#script_name()
  return s:preview_script
endfunction

"------------------------------------------------------------------------------

" If the buffer displayed exclusively by neoview is opened in another window,
" mark it non-exclusive to prevent closing it when neoview is updated to show
" aother buffer. Also, re-enable ALE for it.
function! s:make_nonexclusive()
  if !getwinvar(winnr(), 'neoview')
    let cur_bufnr = bufnr('%')
    for state in values(s:state)
      if cur_bufnr == state.cur_bufnr && state.cur_bufnr_excl
        let state.cur_bufnr_excl = 0
        if exists('g:ale_enabled')
          ALEEnableBuffer
        endif
      endif
    endfor
  endif
endfunction
autocmd BufWinEnter * call s:make_nonexclusive()

"------------------------------------------------------------------------------

" Initialize context for a new neoview session. Returns the session id.
" When the session is complete, neoview#close(id) must be called.
function! neoview#create(search_win_cmd, preview_win_cmd, view_fn)
  let s:neoview_id = s:neoview_id + 1
  let s:state[s:neoview_id] = {
  \ 'search_win_cmd' : a:search_win_cmd,
  \ 'preview_win_cmd' : a:preview_win_cmd,
  \ 'view_fn' : a:view_fn,
  \ 'enable_preview' : 1,
  \ 'cur_bufnr' : -1,
  \ 'cur_bufnr_excl' : 0
  \ }
  return s:neoview_id
endfunction

"------------------------------------------------------------------------------

" Open neoview window if required and call view_fn(context_str).
function! neoview#update(id, context_str)
  let state = s:state[a:id]
  let state.context_str = a:context_str
  if !state.enable_preview
    return
  endif

  " Find out neoview window number.
  let neoview_winnr = s:neoview_winnr(a:id)
  if !neoview_winnr
    let restore_view = winsaveview()
    let neoview_winnr = s:open_neoview(a:id)
  endif

  " Store vars for faster access.
  let cur_bufnr = state.cur_bufnr
  let cur_bufnr_excl = state.cur_bufnr_excl

  " Close the buffer displayed in the neoview window if this buffer was opened
  " exclusively for neoview and contains no unsaved changes. Will be closed
  " only if the next view opens a new buffer.
  if cur_bufnr != -1 && cur_bufnr_excl && !getbufvar(cur_bufnr, "&mod")
    let del_buf = cur_bufnr
  endif

  " Save current buffers names.
  let bufnames = map(copy(getbufinfo()), 'v:val.name')

  " Change focus to neoview window.
  exec neoview_winnr.'wincmd w'

  " Call the view function that will set the neoview window content based
  " on the context_str.
  exec 'call ' . state['view_fn'] . '(''' . a:context_str . ''')'

  " Maybe delete the previously previewed buffer.
  let new_bufnr = winbufnr(neoview_winnr)
  if new_bufnr != cur_bufnr
    let cur_bufnr_excl =
      \(index(bufnames, getbufinfo(new_bufnr)[0]['name']) == -1)
    if cur_bufnr_excl && exists('g:ale_enabled')
      " Disable ALE if the buffer is opened exclusively for neoview.
      ALEDisableBuffer
    endif
    let state.cur_bufnr = new_bufnr
    let state.cur_bufnr_excl = cur_bufnr_excl
    if exists('del_buf')
      exec 'bw '.del_buf
    endif
  endif

  " Return focus to where it was.
  wincmd p

  " Temporary workarund until https://github.com/neovim/neovim/issues/8096
  " is fixed.
  if exists('restore_view')
    call winrestview(restore_view)
  endif
endfunction

"------------------------------------------------------------------------------

" Restore cpo.
let &cpo = s:save_cpo
unlet s:save_cpo
