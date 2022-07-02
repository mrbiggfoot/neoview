" FZF wrappers to be used with neoview.
" Author:  Andrew Pyatkov <mrbiggfoot@gmail.com>
" License: MIT
"------------------------------------------------------------------------------

" Save cpo.
let s:save_cpo = &cpo
set cpo&vim

" Common options to be added to fzf unless 'arg.ignore_common_opt' is set.
if !exists('g:neoview_fzf_common_opt')
  let g:neoview_fzf_common_opt = ''
endif

" Resume-related vars.
let s:last_arg = {}
let s:last_id = 0
let s:last_job_id = 0
let s:last_candidates = ''
let s:history = ''

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
"           See "Default view functions" in autoload/neoview.vim for reference.
"
" opt - a string containing custom fzf command line options. Combined with
"       'g:neoview_fzf_common_opt' unless 'ignore_common_opt' is set.
"
" ignore_common_opt - if true, ignore 'g:neoview_fzf_common_opt'.
"
function! neoview#fzf#run(arg)
  let new_session = v:false
  if a:arg == {}
    if s:last_arg == {}
      echoerr "No neoview session to resume"
      return
    endif
    let arg = s:last_arg
  else
    let arg = a:arg
    let new_session = v:true
  endif

  if !new_session && neoview#is_running(s:last_id)
    " Close the running search.
    if s:last_job_id <= 0
      echoerr "Invalid s:last_job_id " . s:last_job_id
      return
    endif
    let s:ignore_selection = 1
    if has('nvim')
      call chansend(s:last_job_id, "\<CR>")
      let rc = jobwait([s:last_job_id], 3000)
      if rc[0] == -1
        call jobstop(s:last_job_id)
      endif
    else
      call term_sendkeys(s:last_job_id, "\<CR>")
      call term_wait(s:last_job_id)
    endif
    if neoview#is_running(s:last_id)
      echoerr "Failed to stop job " . s:last_job_id
    else
      let s:last_job_id = 0
    endif
    unlet s:ignore_selection
    return
  endif

  let id = neoview#create(
    \ has_key(arg, 'fzf_win') ? arg.fzf_win : '',
    \ has_key(arg, 'preview_win') ? arg.preview_win : '',
    \ has_key(arg, 'view_fn') ? arg.view_fn : '',
    \ has_key(arg, 'tag') ? arg.tag : 'fzf',
    \ function('neoview#adjust_fzf_win_sizes'))
  let s:last_id = id

  " We can't just use stdout because it will contain stuff from fzf interface.
  let out = tempname()

  if new_session
    " Store the arguments in case we need to resume the session later.
    let s:last_arg = arg

    " Store candidates in case we need to resume the session later.
    if s:last_candidates != ''
      call delete(s:last_candidates)
    endif
    let s:last_candidates = tempname()

    " Start new history for the new session.
    if s:history != ''
      call delete(s:history)
    endif
    let s:history = tempname()
  endif

  if has_key(arg, 'ignore_common_opt') && arg.ignore_common_opt
    let fzf_opt = ''
  else
    let fzf_opt = g:neoview_fzf_common_opt
  endif
  if has_key(arg, 'opt')
    let fzf_opt = fzf_opt . ' ' . arg.opt
  endif

  if new_session
    let prefix = has_key(arg, 'source') ?
      \ '(' . arg.source . ')|tee ' . s:last_candidates . '|' : ''
  else
    let prefix = has_key(arg, 'source') ?
      \ 'cat ' . s:last_candidates . '|' : ''
  endif
  if has('nvim')
    let fzf = 'fzf ' . fzf_opt . ' --preview="' . neoview#script_name() . ' ' .
      \ id . ' {}" --preview-window=right:0 --history=' . s:history .
      \ ' --prompt="' . (has_key(arg, 'tag') ? arg.tag : 'fzf') . '> " >' . out
  else
    let fzf = 'fzf ' . fzf_opt . ' --vim --history=' . s:history .
      \ ' --prompt="' . (has_key(arg, 'tag') ? arg.tag : 'fzf') . '> " >' . out
  endif
  let cmd = prefix . fzf

  let opts = { 'id' : id, 'out' : out }
  function! opts.on_exit(job_id, code, ...)
    if a:code == 0 && !exists('s:ignore_selection')
      let output = readfile(self.out)
      call neoview#close(self.id, output)
    else
      call neoview#close(self.id, [])
    endif
    call delete(self.out)
  endfunction

  if has('nvim')
    let s:last_job_id = termopen(cmd, opts)
    call setbufvar('%', 'neoview_id', id)
    if !new_session
      " For some reason, fzf does not react to the keys without the sleep.
      sleep 20m
      call chansend(s:last_job_id, "\<C-p>")
    endif
  else
    call term_start([&shell, &shellcmdflag, cmd],
      \ {'curwin': 1, 'exit_cb': function(opts.on_exit)})
    call setbufvar('%', 'neoview_id', id)
    let s:last_job_id = bufnr('%')
    if !new_session
      sleep 20m
      call term_sendkeys(s:last_job_id, "\<C-p>")
    endif
  endif
endfunction

"------------------------------------------------------------------------------
" Ripgrep source
"------------------------------------------------------------------------------

function! neoview#fzf#ripgrep_arg(pattern, rg_opt)
  let arg = {
    \ 'source' : 'rg --line-number --no-heading --color=always ' . a:rg_opt .
    \            ' ' . a:pattern,
    \ 'opt' : '--ansi ',
    \ 'view_fn' : function('neoview#view_file_line'),
    \ 'tag' : 'Refs'
    \ }
  return arg
endfunction

function! neoview#fzf#ripgrep_files_arg(rg_opt)
  let arg = {
    \ 'source' : 'rg --files --color=never ' . a:rg_opt,
    \ 'view_fn' : function('neoview#view_file'),
    \ 'opt' : '',
    \ 'tag' : 'File'
    \ }
  return arg
endfunction

"------------------------------------------------------------------------------
" Tags source (ctags)
"------------------------------------------------------------------------------

" Search for tagname in the tag files passed in the variable args.
function! neoview#fzf#tags_arg(tagname, ignore_case, ...)
  let src = ''
  let searcher = neoview#ctags_searcher_name() . ' '
  if a:ignore_case
    let searcher = searcher . ' -i '
  endif
  for f in a:000
    let src = src . searcher . a:tagname . ' ' . f . ';'
  endfor
  let arg = {
    \ 'source' : src,
    \ 'opt' : '--ansi --delimiter="\t" --with-nth=3.. ',
    \ 'view_fn' : function('neoview#view_file_excmd'),
    \ 'tag' : 'Ctag'
    \ }
  return arg
endfunction

"------------------------------------------------------------------------------
" Tags source (gtags)
"------------------------------------------------------------------------------

" Search for tagname in the tag DB(s).
" The variable args are passed to 'global' as is.
" 'type' is a string that may contain 'd' and 'r'.
"   d - find definitions (global -d)
"   r - find references (global -rs)
"
" Note that in parallel DBs case some references may be treated as symbols
" without definition due to DB split, so '-rs' is used to find references.
function! neoview#fzf#gtags_arg(db_path, num_instances, type, ...)
  let searcher = neoview#gtags_searcher_name() . ' -n ' . a:num_instances

  let gl_args = ''
  for gl_arg in a:000
    let gl_args = gl_args . ' ' . gl_arg
  endfor

  let src = ''

  if empty(a:type) || matchstr(a:type, 'd') != ''
    let src = searcher . ' -t d ' . a:db_path . ' -d' . gl_args
  endif

  if empty(a:type) || matchstr(a:type, 'r') != ''
    if !empty(src)
      let src = src . ';'
    endif
    let src = src . searcher . ' -t r ' . a:db_path . ' -rs' . gl_args
  endif

  let arg = {
    \ 'source' : src,
    \ 'opt' : '--ansi --delimiter="\t" --with-nth=3.. ',
    \ 'view_fn' : function('neoview#view_file_excmd'),
    \ 'tag' : 'Gtag'
    \ }
  return arg
endfunction

"------------------------------------------------------------------------------
" Buffer tags source
"------------------------------------------------------------------------------

function! neoview#fzf#buf_tags_arg()
  if !filereadable(expand('%'))
    echoerr "File is not saved"
    return
  endif
  let src = neoview#buftag_searcher_name() . ' ' . expand('%')
  let arg = {
    \ 'source' : src,
    \ 'opt' : '--ansi --delimiter="\t" --with-nth=3.. ',
    \ 'view_fn' : function('neoview#view_file_excmd'),
    \ 'tag' : 'BufTag'
    \ }
  return arg
endfunction

"------------------------------------------------------------------------------
" Buffer lines source
"------------------------------------------------------------------------------

" Return ANSI escape code for the group color. Works only for 256 color
" terminal at the moment.
function! s:GroupColor(grp)
  let fgcol = synIDattr(synIDtrans(hlID(a:grp)), 'fg')
  let bgcol = synIDattr(synIDtrans(hlID(a:grp)), 'bg')
  let c = "\033[38;5;" . (empty(fgcol) ? "30" : fgcol) . "m"
  if !empty(bgcol)
    let c = c . "\033[48;5;" . bgcol . "m"
  endif
  return c
endfunction

" Search in the lines of the current buffer.
function! neoview#fzf#buf_lines_arg()
  " Write the lines to a temp file.
  let s:bl_fmt = s:GroupColor("LineNr")
  if line('$') < 100
    let s:bl_fmt = s:bl_fmt . "%2d"
  elseif line('$') < 1000
    let s:bl_fmt = s:bl_fmt . "%3d"
  else
    let s:bl_fmt = s:bl_fmt . "%4d"
  endif
  let s:bl_fmt = s:bl_fmt . "\033[m %s"
  function! FmtLine(key, val)
    return printf(s:bl_fmt, a:key + 1, a:val)
  endfunction
  let lines = map(getline(1, '$'), function('FmtLine'))
  unlet s:bl_fmt
  let tmp = tempname()
  call writefile(lines, tmp)

  " Create the arg.
  let arg = {
    \ 'source' : 'cat ' . tmp,
    \ 'opt' : '--ansi --nth=2.. ',
    \ 'view_fn' : function('neoview#view_buf_line', [ bufnr('%') ]),
    \ 'tag' : 'BufLine'
    \ }
  return arg
endfunction

"------------------------------------------------------------------------------

" Restore cpo.
let &cpo = s:save_cpo
unlet s:save_cpo
