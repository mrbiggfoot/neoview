" Neovim plugin for showing preview in a neovim window.
" Author:  Andrew Pyatkov <mrbiggfoot@gmail.com>
" License: MIT
"------------------------------------------------------------------------------

" Update the preview info.
function! Tapi_NvSetPreview(bufnum, arglist)
  let id = getbufvar(a:bufnum, 'neoview_id')
  if empty(id)
    echoerr "No id found for buf " . a:bufnum
    return
  endif
  call neoview#update(id, a:arglist[0])
endfunction

" Resize the search window.
function! Tapi_NvResizeSearchWin(bufnum, arglist)
  let id = getbufvar(a:bufnum, 'neoview_id')
  if empty(id)
    echoerr "No id found for buf " . a:bufnum
    return
  endif
  call neoview#set_search_window_height(id, a:arglist[0])
endfunction

" Update the search info. Arglist is the following:
" ptn       - search pattern
" x         - cursor X axis position
" num_filt  - number of filtered candidates
" num_total - total nuber of candidates
" num_sel   - number of selected candidates (non-zero only for multi selection)
" reading   - non-zero if the candidate list is still being populated
function! Tapi_NvSetInfo(bufnum, arglist)
  let id = getbufvar(a:bufnum, 'neoview_id')
  if empty(id)
    echoerr "No id found for buf " . a:bufnum
    return
  endif
  if len(a:arglist) != 6
    echoerr "Malformed args, len " . len(a:arglist)
    return
  endif
  call neoview#set_search_info(id, a:arglist[0], a:arglist[1], a:arglist[2],
    \ a:arglist[3], a:arglist[4], a:arglist[5])
endfunction
