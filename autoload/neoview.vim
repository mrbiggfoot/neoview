" Neovim plugin for showing preview in a neovim window.
" Author:  Andrew Pyatkov <mrbiggfoot@gmail.com>
" License: MIT
"------------------------------------------------------------------------------

if !exists('g:loaded_bbye')
  echoerr '"moll/vim-bbye" is required!'
  finish
endif

" Save cpo.
let s:save_cpo = &cpo
set cpo&vim

if !exists('g:neoview_toggle_preview')
  let g:neoview_toggle_preview = '<F1>'
endif

if !exists('g:neoview_enable_dyn_size')
  let g:neoview_enable_dyn_size = v:true
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
let s:timer_id = -1

" Maps neoview_id to the current state. An entry is added by neoview#create()
" and removed by neoview#close() calls.
"
" A state consists of:
"
" search_win_cmd  - string, vim command to create the search window.
" preview_win_cmd - string, vim command to create the preview window.
" view_fn         - string, vim script function name to be called on
"                   candidate for both preview and candidate(s) selection.
" enable_preview  - bool, whether preview window is enabled.
" cur_bufnr       - int, buffer number displayed in the preview window.
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

" Get tag searcher script name.
function! neoview#tag_searcher_name()
  return s:bin_dir.'tags.py'
endfunction

"------------------------------------------------------------------------------

" Returns true if the current window is a neoview search window.
function! neoview#is_search_win()
  return getwinvar(winnr(), 'neoview_s') != ''
endfunction

" Returns true if the current window is a neoview preview window.
function! neoview#is_preview_win()
  return getwinvar(winnr(), 'neoview_p') != ''
endfunction

"------------------------------------------------------------------------------

" Send keystrokes to the preview window. If called not from a preview or
" a search window, becomes a no op.
function! neoview#feed_keys_to_preview(keys)
  let id = getwinvar(winnr(), 'neoview_s')
  if id
    let nr = s:neoview_winnr(id, 'neoview_p')
    if nr
      exec nr . 'wincmd w'
      call feedkeys(a:keys, 'x')
      wincmd p
    endif
    startinsert
  else
    let nr = winnr()
    let id = getwinvar(nr, 'neoview_p')
    if !id
      return
    endif
    call feedkeys(a:keys, 'x')
  endif
endfunction

"------------------------------------------------------------------------------

" Adjust 'fzf' window sizes based on a hack that either the 2nd or next to
" the last line contains "N/M", where N is the number of shown matches and
" M is the total number of matches.
function! neoview#adjust_fzf_win_sizes(timer_id)
  let cur_winnr = winnr()
  for nr in range(1, winnr('$'))
    if getwinvar(nr, 'neoview_s')
      let bufnr = winbufnr(nr)
      let h0 = getwinvar(nr, 'neoview_h0', 1000)

      let m = matchlist(getbufline(bufnr, 2), '..\(\d\+\)/\(\d\+\)')
      if empty(m)
        let m =
          \ matchlist(getbufline(bufnr, line('$') - 1), '..\(\d\+\)/\(\d\+\)')
        if empty(m)
          continue
        endif
      endif

      " m[1] now has the number of candidates displayed.
      let cur_h = min([h0, m[1] + 2])
      if cur_h != winheight(nr)
        exec nr . 'wincmd w'
        exec 'resize ' . cur_h
      endif
    endif
  endfor
  exec cur_winnr . 'wincmd w'
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

function! s:close_preview(id)
  let state = s:state[a:id]
  let nr = s:neoview_winnr(a:id, 'neoview_p')
  if nr
    if state.preview_win_cmd == ''
      " Restore original content of the window.
      exec nr . 'wincmd w'
      let rbuf = getwinvar(nr, 'neoview_p_buf', -1)
      let rview = getwinvar(nr, '', {})
      if rbuf != -1 && getbufinfo(rbuf) != []
        exec 'b ' . rbuf
        if rview != {}
          call winrestview(rview)
        endif
      else
        enew
      endif
      call setwinvar(nr, 'neoview_p', 0)
      call setwinvar(nr, 'neoview_p_buf', -1)
      call setwinvar(nr, 'neoview_p_view', {})
      wincmd p
    else
      exec nr . 'wincmd q'
    endif
  endif

  if s:has_exclusive_buffer(a:id)
    exec 'Bwipeout ' . state.cur_bufnr
  endif

  let state.enable_preview = 0
  let state.cur_bufnr = -1
  let state.cur_bufnr_excl = 0
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
      call s:close_preview(id)
    else
      " Open the preview.
      let state.enable_preview = 1
      call neoview#update(id, state.context_str)
    endif
    startinsert
  endif
endfunction

"------------------------------------------------------------------------------
" Default view functions
"------------------------------------------------------------------------------
" Signature:
" 'ctx' - array of strings that contains the candidates to preview or select.
" If 'final' is 0, the function was called to preview the candidate.
" If 'final' is 1, the function was called to select the candidate.

" Helper function to show file which may contain changes.
" Simple 'edit' returns E37 in this case, and this function handles it.
function! s:show_file(filename, excmd)
  try
    if a:excmd != ''
      exec 'silent edit +' . a:excmd . ' ' . a:filename
    else
      exec 'silent edit ' . a:filename
    endif
  catch /^Vim\%((\a\+)\)\=:E37/
    " E37: No write since last change (add ! to override)
    let nr = bufnr(a:filename)
    if nr == -1
      echoerr 'Buffer does not exist for ' . a:filename
      return
    endif
    exec 'silent b ' . nr
    exec a:excmd
  endtry
endfunction

" View function that expects a file name string in 'ctx[0]'.
function! neoview#view_file(ctx, final)
  if a:final
    for f in a:ctx
      call s:show_file(f, '')
    endfor
  else
    call s:show_file(a:ctx[0], '')
  endif
endfunction

" View function that expects file:line at the beginning of ctx[0].
" Opens all folds on preview and centers the previewed line.
function! neoview#view_fileline(ctx, final)
  " m[1] - file name, m[2] - line number
  if a:final
    for f in a:ctx
      let m = matchlist(f, '\([^:]\+\):\(\d\+\)')
      call s:show_file(m[1], m[2])
    endfor
  else
    let m = matchlist(a:ctx[0], '\([^:]\+\):\(\d\+\)')
    call s:show_file(m[1], m[2])
    exec 'match Search /\%'.line('.').'l/'
    exec 'normal! zRzz'
  endif
endfunction

" View function that expects file\texcmd\t... lines in ctx.
" Opens all folds on preview and centers the previewed line.
function! neoview#view_file_excmd(ctx, final)
  function! EscapeCmd(excmd)
    let cmd = substitute(a:excmd, '\\', '\\\\', 'g')
    let cmd = substitute(cmd, ' ', '\\ ', 'g')
    return cmd
  endfunction
  " m[0] - file name, m[1] - ex cmd
  if a:final
    for ln in a:ctx
      let m = split(ln, '\t')
      call s:show_file(m[0], EscapeCmd(m[1]))
    endfor
  else
    let m = split(a:ctx[0], '\t')
    call s:show_file(m[0], EscapeCmd(m[1]))
    exec 'match Search /\%'.line('.').'l/'
    exec 'normal! zRzz'
  endif
endfunction

"------------------------------------------------------------------------------

" Returns percentage 'pct' of 'value', but no more than 'lim'.
function! s:calc_dim(pct, value, lim)
  let x = float2nr(round(a:pct / 100.0 * a:value))
  return (x > a:lim) ? a:lim : x
endfunction

" Replace percentages with the actual line/column counts:
"   %X is replaced with percentage of (&lines - &cmdheight)
"   $X is replaced with percentage of &columns
function! s:normalize_cmd(cmd, lim_width, lim_height)
  let s = substitute(a:cmd, '%\(\d\+\)',
    \ '\=s:calc_dim(submatch(1), &lines - &cmdheight - 1, a:lim_height) - 1',
    \ 'g')
  let s = substitute(s, '$\(\d\+\)',
    \ '\=s:calc_dim(submatch(1), &columns, a:lim_width) - 1', 'g')
  return s
endfunction

"------------------------------------------------------------------------------

" Initialize context for a new neoview session. Returns the session id.
" When the session is complete, neoview#close(id) must be called.
function! neoview#create(search_win_cmd, preview_win_cmd, view_fn,
                         \ adjust_win_sizes_fn)
  let s:neoview_id = s:neoview_id + 1
  " Deal with overflow.
  while (has_key(s:state, s:neoview_id) || s:neoview_id == 0)
    let s:neoview_id = s:neoview_id + 1
  endwhile

  " Set original window info to be able to go back to it when we are done.
  call setwinvar(winnr(), 'neoview_orig', s:neoview_id)

  let view_fn = (a:view_fn == '') ? 'neoview#view_file' : a:view_fn

  if a:search_win_cmd != ''
    let lim_width = &columns - 1
    let lim_height = &lines - &cmdheight - 2
    let search_win_cmd =
      \ s:normalize_cmd(a:search_win_cmd, lim_width, lim_height)
    exec search_win_cmd
  else
    let search_win_cmd = ''
  endif

  call setwinvar(winnr(), 'neoview_s', s:neoview_id)
  call setwinvar(winnr(), 'neoview_h0', winheight('%'))
  enew
  exec 'setlocal statusline=-\ neoview\ ' . s:neoview_id . '\ -'

  let s:state[s:neoview_id] = {
    \ 'search_win_cmd' : search_win_cmd,
    \ 'search_bufnr' : bufnr('%'),
    \ 'preview_win_cmd' : a:preview_win_cmd,
    \ 'view_fn' : view_fn,
    \ 'enable_preview' : 0,
    \ 'cur_bufnr' : -1,
    \ 'cur_bufnr_excl' : 0
    \ }

  if g:neoview_enable_dyn_size && a:adjust_win_sizes_fn != ''
    " Start the update timer if we just created the first state.
    if len(s:state) == 1
      let s:timer_id =
        \ timer_start(50, a:adjust_win_sizes_fn, {'repeat' : -1})
    endif
  endif

  return s:neoview_id
endfunction

"------------------------------------------------------------------------------

" Returns true if a neoview session with the specified id is already running.
function! neoview#is_running(id)
  return has_key(s:state, a:id)
endfunction

"------------------------------------------------------------------------------

" Destroy the context of neoview session. Also, closes the preview window if
" required. If view_context list is not empty, call view_fn(view_context, 1).
function! neoview#close(id, view_context)
  let state = s:state[a:id]
  call s:close_preview(a:id)

  " Close search window if it was created, otherwise reset 'neoview_s' var.
  let nr = s:neoview_winnr(a:id, 'neoview_s')
  if state.search_win_cmd == ''
    call setwinvar(nr, 'neoview_s', 0)
    setlocal statusline=
  else
    exec nr . 'wincmd q'
  endif

  " Close the search buffer.
  exec 'bw! ' . state.search_bufnr

  " Go back to the originating window.
  let orig_nr = s:neoview_winnr(a:id, 'neoview_orig')
  if nr
    exec orig_nr . 'wincmd w'
    unlet w:neoview_orig
  endif

  " Call view function with 'final' = true.
  if len(a:view_context) > 0
    exec 'call ' . state['view_fn'] . '(a:view_context, 1)'
  endif
  unlet s:state[a:id]

  if len(s:state) == 0 && s:timer_id != -1
    call timer_stop(s:timer_id)
    let s:timer_id = -1
  endif
endfunction

"------------------------------------------------------------------------------

" Open preview window if required and call view_fn([context_str], 0).
function! neoview#update(id, context_str)
  let state = s:state[a:id]
  let state.context_str = a:context_str
  if !state.enable_preview
    return
  endif

  " Find out preview window number.
  let preview_winnr = s:neoview_winnr(a:id, 'neoview_p')
  if !preview_winnr
    let search_winnr = s:neoview_winnr(a:id, 'neoview_s')
    if state.preview_win_cmd != ''
      let preview_win_cmd = s:normalize_cmd(state.preview_win_cmd,
        \ &columns - winwidth(search_winnr) - 2,
        \ &lines - &cmdheight - winheight(search_winnr) - 3)
      exec preview_win_cmd
      let preview_winnr = winnr()
    else
      exec search_winnr . 'wincmd w'
      wincmd k
      let preview_winnr = winnr()
      if preview_winnr == search_winnr
        wincmd j
        let preview_winnr = winnr()
        if preview_winnr == search_winnr
          wincmd h
          let preview_winnr = winnr()
          if preview_winnr == search_winnr
            wincmd l
            let preview_winnr = winnr()
            if preview_winnr == search_winnr
              " Preview window command is not specified and we were unable to
              " find a window to use for preview. Just create a new window
              " for preview.
              new
              let preview_winnr = winnr()
            endif
          endif
        endif
      endif
      " Save the currently opened buffer and position.
      call setwinvar(preview_winnr, 'neoview_p_buf', bufnr('%'))
      call setwinvar(preview_winnr, 'neoview_p_view', winsaveview())
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
  let ctx = substitute(a:context_str, "'", "''", 'g')
  exec 'call ' . state['view_fn'] . '([''' . ctx . '''], 0)'

  " Maybe delete the previously previewed buffer.
  let new_bufnr = winbufnr(preview_winnr)
  if new_bufnr != cur_bufnr
    let cur_bufnr_excl =
      \(index(bufnames, getbufinfo(new_bufnr)[0]['name']) == -1)
    let state.cur_bufnr = new_bufnr
    let state.cur_bufnr_excl = cur_bufnr_excl
    if exists('del_buf')
      exec 'bw ' . del_buf
    endif
  endif

  " Return focus to the search window.
  let search_winnr = s:neoview_winnr(a:id, 'neoview_s')
  exec search_winnr . 'wincmd w'
endfunction

"------------------------------------------------------------------------------

" Restore cpo.
let &cpo = s:save_cpo
unlet s:save_cpo
