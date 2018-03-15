" Neovim plugin for showing preview in a neovim window.
" Author:  Andrew Pyatkov <mrbiggfoot@gmail.com>
" License: MIT
"------------------------------------------------------------------------------

" Save cpo.
let s:save_cpo = &cpo
set cpo&vim

if !exists('g:neoview_toggle_preview')
  let g:neoview_toggle_preview = '<F1>'
endif

exec 'tmap <silent> ' . g:neoview_toggle_preview .
  \ ' <C-\><C-n>:call neoview#toggle_preview()<CR>'
exec 'nmap <silent> ' . g:neoview_toggle_preview .
  \ ' :call neoview#toggle_preview()<CR>'

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
" cur_bufnr       - int, buffer number displayed in preview window.
" cur_bufnr_excl  - bool, whether the buffer was created exclusively
"                   for preview.
" context_str     - string, set to the last context_str from neoview#update().
let s:state = {}

"------------------------------------------------------------------------------

" Return preview window number with the specified id, 0 if none exists.
function! s:neoview_winnr(id, type)
  for nr in range(1, winnr('$'))
    if getwinvar(nr, a:type) == a:id
      return nr
    endif
  endfor
  return 0
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
  if !getwinvar(winnr(), 'neoview_p')
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

" Returns non-zero if the session contains a buffer that is opened exclusively
" for it, zero otherwise. Also, if there's no associated buffer, return zero.
function! s:has_exclusive_buffer(id)
  let state = s:state[a:id]
  let cur_bufnr = state.cur_bufnr
  if cur_bufnr == -1 || !state.cur_bufnr_excl || getbufvar(cur_bufnr, '&mod')
    return 0
  endif

  " Check if the buffer is opened in another neoview preview window.
  for [key, val] in items(s:state)
    if key == a:id
      continue
    endif
    if cur_bufnr == val.cur_bufnr
      return 0
    endif
  endfor
  return 1
endfunction

"------------------------------------------------------------------------------

" Toggle preview window. Works from both search and preview windows.
function! neoview#toggle_preview()
  let id = getwinvar(winnr(), 'neoview_p')
  if id
    " Preview window is in focus, switch to the search window.
    let nr = s:neoview_winnr(id, 'neoview_s')
    exec nr . 'wincmd w'
  else
    let id = getwinvar(winnr(), 'neoview_s')
  endif

  if id
    " Search window is in focus.
    let state = s:state[id]
    let nr = s:neoview_winnr(id, 'neoview_p')
    if nr
      " Close the preview.
      if state.preview_win_cmd != ''
        exec nr . 'wincmd q'
      else
        call setwinvar(nr, 'neoview_p', 0)
      endif
      if s:has_exclusive_buffer(id)
        if exists('g:loaded_bbye')
          exec 'Bwipeout ' . state.cur_bufnr
        else
          exec 'bw ' . state.cur_bufnr
        endif
      endif
      let state.enable_preview = 0
      let state.cur_bufnr = -1
      let state.cur_bufnr_excl = 0
    else
      " Open the preview.
      let state.enable_preview = 1
      call neoview#update(id, state.context_str)
    endif
    startinsert
  endif
endfunction

"------------------------------------------------------------------------------

" Initialize context for a new neoview session. Returns the session id.
" When the session is complete, neoview#close(id) must be called.
function! neoview#create(search_win_cmd, preview_win_cmd, view_fn)
  let s:neoview_id = s:neoview_id + 1
  " Deal with overflow.
  while (has_key(s:state, s:neoview_id) || s:neoview_id == 0)
    let s:neoview_id = s:neoview_id + 1
  endwhile

  call setwinvar(winnr(), 'neoview_s', s:neoview_id)
  enew
  exec 'setlocal statusline=-\ neoview\ ' . s:neoview_id . '\ -'

  let s:state[s:neoview_id] = {
    \ 'search_win_cmd' : a:search_win_cmd,
    \ 'search_bufnr' : bufnr('%'),
    \ 'preview_win_cmd' : a:preview_win_cmd,
    \ 'view_fn' : a:view_fn,
    \ 'enable_preview' : 0,
    \ 'cur_bufnr' : -1,
    \ 'cur_bufnr_excl' : 0
    \ }
  return s:neoview_id
endfunction

"------------------------------------------------------------------------------

" Destroy the context of neoview session. Also, closes the preview window if
" required. If view_context is not empty, call view_fn(view_context).
function! neoview#close(id, view_context)
  let state = s:state[a:id]

  " Close preview window if required.
  if state.preview_win_cmd != ''
    let nr = s:neoview_winnr(a:id, 'neoview_p')
    if nr
      exec nr . 'wincmd q'
    endif
  endif

  " Close search window if it was created, otherwise reset 'neoview_s' var.
  let nr = s:neoview_winnr(a:id, 'neoview_s')
  if state.search_win_cmd == ''
    call setwinvar(nr, 'neoview_s', 0)
    setlocal statusline=
  else
    exec nr . 'wincmd q'
  endif

  " Close the search buffer. Use 'vim-bbye' plugin's function if possible to
  " preserve the window layout.
  if exists('g:loaded_bbye')
    exec 'Bdelete! ' . state.search_bufnr
  else
    exec 'bd! ' . state.search_bufnr
  endif

  " Remove the preview buffer if required.
  if s:has_exclusive_buffer(a:id)
    if exists('g:loaded_bbye')
      exec 'Bwipeout ' . state.cur_bufnr
    else
      exec 'bw ' . state.cur_bufnr
    endif
  endif

  " Call view function with 'final' = true.
  if a:view_context != ''
    exec 'call ' . state['view_fn'] . '(''' . a:view_context . ''', 1)'
  endif
  unlet s:state[a:id]
endfunction

"------------------------------------------------------------------------------

" Open preview window if required and call view_fn(context_str).
function! neoview#update(id, context_str)
  let state = s:state[a:id]
  let state.context_str = a:context_str
  if !state.enable_preview
    return
  endif

  " Put the search window in focus.
  let search_winnr = s:neoview_winnr(a:id, 'neoview_s')
  exec search_winnr . 'wincmd w'

  " Find out preview window number.
  let preview_winnr = s:neoview_winnr(a:id, 'neoview_p')
  if !preview_winnr
    if state.preview_win_cmd
      exec s:state[a:id].preview_win_cmd
      let preview_winnr = winnr()
      wincmd p
    else
      wincmd k
      let preview_winnr = winnr()
      if preview_winnr == search_winnr
        wincmd j
        let preview_winnr = winnr()
      endif
    endif
    call setwinvar(preview_winnr, 'neoview_p', a:id)
  endif

  " Store vars for faster access.
  let cur_bufnr = state.cur_bufnr
  let cur_bufnr_excl = state.cur_bufnr_excl

  " Close the buffer displayed in the preview window if this buffer was opened
  " exclusively for neoview and contains no unsaved changes. Will be closed
  " only if the next view opens a new buffer and no other preview window has
  " it.
  if s:has_exclusive_buffer(a:id)
    let del_buf = cur_bufnr
  endif

  " Save current buffers names.
  let bufnames = map(copy(getbufinfo()), 'v:val.name')

  " Change focus to preview window.
  exec preview_winnr . 'wincmd w'

  " Call the view function that will set the preview window content based
  " on the context_str. The 'final' argument is false.
  exec 'call ' . state['view_fn'] . '(''' . a:context_str . ''', 0)'

  " Maybe delete the previously previewed buffer.
  let new_bufnr = winbufnr(preview_winnr)
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
      exec 'bw ' . del_buf
    endif
  endif

  " Return focus to the search window.
  wincmd p
endfunction

"------------------------------------------------------------------------------

" Restore cpo.
let &cpo = s:save_cpo
unlet s:save_cpo
