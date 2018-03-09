
" Save cpo.
let s:save_cpo = &cpo
set cpo&vim

" Common vars.
let s:bin_dir = expand('<sfile>:h:h').'/bin/'
let s:preview_script = s:bin_dir.'neoview.py'

" Get preview script name.
function! neoview#script_name()
	return s:preview_script
endfunction

" Open neoview window if required and call preview_fn(context_str).
function! neoview#run(preview_fn, context_str)
	echom 'neoview#run("'.a:preview_fn.'", "'.a:context_str.'")'
endfunction

" Restore cpo.
let &cpo = s:save_cpo
unlet s:save_cpo
