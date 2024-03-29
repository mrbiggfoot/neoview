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
" view_fn         - function object, vim script function to be called on
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

" Get tag searcher script name (ctags).
function! neoview#ctags_searcher_name()
  return s:bin_dir.'tags.py'
endfunction

" Get tag searcher script name (gtags).
function! neoview#gtags_searcher_name()
  return s:bin_dir.'gtags.py'
endfunction

" Get buffer tag searcher script name.
function! neoview#buftag_searcher_name()
  return s:bin_dir.'tags_local.py'
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

if !hlexists('NvSearchTag')
  highlight NvSearchTag ctermfg=LightGreen ctermbg=Black cterm=bold
endif
if !hlexists('NvSearchDef')
  highlight NvSearchDef ctermfg=White ctermbg=Black cterm=bold
endif
if !hlexists('NvSearchCur')
  highlight NvSearchCur ctermfg=White ctermbg=Gray cterm=bold
endif
if !hlexists('NvSearchStatRd')
  highlight NvSearchStatRd ctermfg=LightRed ctermbg=Black cterm=bold
endif
if !hlexists('NvSearchStatFin')
  highlight NvSearchStatFin ctermfg=Yellow ctermbg=Black cterm=bold
endif
if !hlexists('NvSearchNoStatInfo')
  highlight NvSearchNoStatInfo ctermfg=Yellow ctermbg=Black cterm=bold
endif

" Update the search info for search 'id'. Arglist is the following:
" ptn       - search pattern
" x         - cursor X axis position
" num_filt  - number of filtered candidates
" num_total - total nuber of candidates
" num_sel   - number of selected candidates (non-zero only for multi selection)
" rd        - non-zero if the candidate list is still being populated
function! neoview#set_search_info(id, ptn, x, num_filt, num_total, num_sel, rd)
  let nr = s:neoview_winnr(a:id, 'neoview_s')
  if !nr
    echo "No window! > " . a:ptn
    return
  endif

  function! Normalize(ptn)
    let p = substitute(a:ptn, '\\', '\\\\', 'g')
    let p = substitute(p, ' ', '\\ ', 'g')
    let p = substitute(p, '%', '%%', 'g')
    let p = substitute(p, '|', '\\|', 'g')
    let p = substitute(p, '"', '\\"', 'g')
    return p
  endfunction

  function! PtnBegin(ptn, x)
    return Normalize(strpart(a:ptn, 0, a:x))
  endfunction

  function! PtnCur(ptn, x)
    if a:x >= len(a:ptn)
      return '\ '
    endif
    return Normalize(a:ptn[a:x])
  endfunction

  function! PtnEnd(ptn, x)
    if a:x >= len(a:ptn)
      return ''
    endif
    return Normalize(strpart(a:ptn, a:x + 1))
  endfunction

  function! Stats(nf, nt, ns)
    if a:ns > 0
      return a:nf . '\ /\ ' . a:nt . '\ (' . a:ns . ')'
    else
      return a:nf . '\ /\ ' . a:nt
    endif
  endfunction

  let cur = winnr()
  exec nr . 'wincmd w'
  exec 'setlocal statusline=%#NvSearchTag#\ ' . s:state[a:id].tag .
    \ '>\ %#NvSearchDef#' . PtnBegin(a:ptn, a:x) .
    \ '%#NvSearchCur#' . PtnCur(a:ptn, a:x) .
    \ '%#NvSearchDef#' . PtnEnd(a:ptn, a:x) . '\ ' .
    \ (a:rd ? '%#NvSearchStatRd#' : '%#NvSearchStatFin#') . '<\ ' .
    \ Stats(a:num_filt, a:num_total, a:num_sel)
  exec cur . 'wincmd w'
endfunction

"------------------------------------------------------------------------------

function! neoview#set_search_window_height(id, height)
  let nr = s:neoview_winnr(a:id, 'neoview_s')
  if nr
    let h0 = getwinvar(nr, 'neoview_h0', 1000)
    let h = min([h0, a:height])
    let cur = winnr()
    exec nr . 'wincmd w'
    exec 'resize ' . h
    exec cur . 'wincmd w'
  endif
endfunction

"------------------------------------------------------------------------------

" Adjust 'fzf' window sizes based on a hack that either the 2nd or next to
" the last line contains "N/M", where N is the number of shown matches and
" M is the total number of matches.
function! neoview#adjust_fzf_win_sizes(timer_id)
  let cur_winnr = winnr()
  for nr in range(1, winnr('$'))
    let id = getwinvar(nr, 'neoview_s')
    if id
      if s:state[id].search_win_cmd == ''
        " No dedicated window was created for search, so don't resize the
        " current window.
        continue
      endif
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
      let rview = getwinvar(nr, 'neoview_p_view', {})
      if rbuf != -1 && getbufinfo(rbuf) != []
        exec 'b ' . rbuf
        if rview != {}
          call winrestview(rview)
        endif
      else
        enew
      endif
      unlet w:neoview_p
      unlet w:neoview_p_buf
      unlet w:neoview_p_view
      match none
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
      let nr = s:neoview_winnr(id, 'neoview_s')
      if nr
        exec nr . 'wincmd w'
      endif
      if !has('nvim') && &buftype == 'terminal' && mode() == 'n'
        call feedkeys('i', 'x')
      endif
    else
      " Open the preview.
      let state.enable_preview = 1
      call neoview#update(id, state.context_str)
    endif
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
" 'final' specifies whether this is the final action. Set to false for
" preview.
function! s:show_file(filename, excmd, final)
  if a:excmd != ''
    " Do the needed a:excmd escaping.
    let excmd = escape(a:excmd, '*[]~')
  endif
  if a:final
    " Save the current position in the jump list
    normal! m'
    let mods = 'keepp '
  else
    let mods = 'silent keepjumps keepp '
  endif
  let nr = bufnr(a:filename . '$')
  if nr == -1
    if a:final
      let cmd = 'edit '
    else
      let cmd = 'view '
    endif
    exec mods . cmd . a:filename
    if exists('excmd')
      exec mods . excmd
    endif
    return
  endif
  exec mods . 'b ' . nr
  if exists('excmd')
    exec mods . excmd
  endif
endfunction

" View function that expects a file name string in 'ctx[0]'.
function! neoview#view_file(ctx, final)
  if a:final
    for f in a:ctx
      call s:show_file(f, '', 1)
    endfor
  else
    call s:show_file(a:ctx[0], '', 0)
  endif
endfunction

" View function that expects file:line at the beginning of ctx[0].
" Opens all folds on preview and centers the previewed line.
function! neoview#view_file_line(ctx, final)
  " m[1] - file name, m[2] - line number
  if a:final
    for f in a:ctx
      let m = matchlist(f, '\([^:]\+\):\(\d\+\)')
      call s:show_file(m[1], m[2], 1)
    endfor
  else
    let m = matchlist(a:ctx[0], '\([^:]\+\):\(\d\+\)')
    call s:show_file(m[1], m[2], 0)
    exec 'keeppatterns match Search /\%'.line('.').'l/'
  endif
  exec 'normal! zRzz'
endfunction

" View function that expects file\texcmd\t... lines in ctx.
" Opens all folds on preview and centers the previewed line.
function! neoview#view_file_excmd(ctx, final)
  " m[0] - file name, m[1] - ex cmd
  if a:final
    for ln in a:ctx
      let m = split(ln, '\t')
      call s:show_file(m[0], m[1], 1)
    endfor
  else
    let m = split(a:ctx[0], '\t')
    call s:show_file(m[0], m[1], 0)
    exec 'keeppatterns match Search /\%'.line('.').'l/'
  endif
  exec 'normal! zRzz'
endfunction

" View function that is used for buffer lines. Each line should start with its
" number, 1-based.
function! neoview#view_buf_line(bnum, ctx, final)
  let lnum = matchstr(a:ctx[0], '\d\+')
  if empty(lnum)
    echoerr "No line number found!"
    return
  endif
  if a:final
    exec 'b ' . a:bnum
    exec lnum
  else
    exec 'silent keepjumps b ' . a:bnum
    exec 'silent keepjumps ' . lnum
    exec 'keeppatterns match Search /\%'.line('.').'l/'
  endif
  exec 'normal! zRzz'
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
function! neoview#create(search_win_cmd, preview_win_cmd, view_fn, tag,
                         \ adjust_win_sizes_fn)
  let s:neoview_id = s:neoview_id + 1
  " Deal with overflow.
  while (has_key(s:state, s:neoview_id) || s:neoview_id == 0)
    let s:neoview_id = s:neoview_id + 1
  endwhile

  " Set original window info to be able to go back to it when we are done.
  call setwinvar(winnr(), 'neoview_orig', s:neoview_id)

  let View_fn = (a:view_fn == '') ? function('neoview#view_file') : a:view_fn

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
  exec 'setlocal statusline=%#NvSearchNoStatInfo#\ -\ neoview\ ' .
    \ s:neoview_id . '\ -'

  let s:state[s:neoview_id] = {
    \ 'search_win_cmd' : search_win_cmd,
    \ 'search_bufnr' : bufnr('%'),
    \ 'preview_win_cmd' : a:preview_win_cmd,
    \ 'view_fn' : View_fn,
    \ 'enable_preview' : 0,
    \ 'cur_bufnr' : -1,
    \ 'cur_bufnr_excl' : 0,
    \ 'tag' : a:tag
    \ }

  if g:neoview_enable_dyn_size && a:adjust_win_sizes_fn != '' && has('nvim')
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
    exec nr . 'wincmd w'
    unlet w:neoview_s
    setlocal statusline=
  else
    exec nr . 'wincmd q'
  endif

  " Go back to the originating window.
  let orig_nr = s:neoview_winnr(a:id, 'neoview_orig')
  if nr
    exec orig_nr . 'wincmd w'
    unlet w:neoview_orig
  endif

  " Call view function with 'final' = true.
  if len(a:view_context) > 0
    call state['view_fn'](a:view_context, 1)
  endif
  unlet s:state[a:id]

  if has('nvim')
    " Close the search buffer.
    exec 'Bw! ' . state.search_bufnr
  endif

  " Stop timer if it is the last one.
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
      let preview_winnr = s:neoview_winnr(a:id, 'neoview_orig')
      if preview_winnr && !getwinvar(preview_winnr, 'neoview_s')
        exec preview_winnr . 'wincmd w'
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
  call state['view_fn']([a:context_str], 0)

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
