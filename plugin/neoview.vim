" Neovim plugin for showing preview in a neovim window.
" Author:  Andrew Pyatkov <mrbiggfoot@gmail.com>
" License: MIT
"------------------------------------------------------------------------------

function! Tapi_SetPreview(bufnum, arglist)
  let id = getbufvar(a:bufnum, 'neoview_id')
  if empty(id)
    echoerr "No id found for buf " . a:bufnum
    return
  endif
  call neoview#update(id, a:arglist[0])
endfunction

function! Tapi_ResizeSearchWin(bufnum, arglist)
  let id = getbufvar(a:bufnum, 'neoview_id')
  if empty(id)
    echoerr "No id found for buf " . a:bufnum
    return
  endif
  for nr in range(1, winnr('$'))
    if getwinvar(nr, 'neoview_s') == id
      let h0 = getwinvar(nr, 'neoview_h0', 1000)
      let h = min([h0, a:arglist[0] + 2])
      let cur = winnr()
      exec nr . 'wincmd w'
      exec 'resize ' . h
      exec cur . 'wincmd w'
      return
    endif
  endfor
endfunction
