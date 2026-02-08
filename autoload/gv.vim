vim9script
# The MIT License (MIT)
#
# Copyright (c) 2016 Junegunn Choi
# Copyright (c) 2025-2026 Mao-Yining
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

const mapping_helps = "o: open split / O: open tab / gb: GBrowse / q: quit / dd: diff view"

const begin = '^[^0-9]*[0-9]\{4}-[0-9]\{2}-[0-9]\{2}\s\+'

def EchoWarn(message: string)
	echohl WarningMsg | echom "[gv.vim]" message | echohl None
enddef

def EchoShrug()
	EchoWarn('¯\_(ツ)_/¯')
enddef

def GvSha(...args: list<string>): string
	return args->get(0, getline('.'))->matchstr(begin .. '\zs[a-f0-9]\+')
enddef

def Move(flag: string): string
	const [l, c] = searchpos(begin, flag)
	return !empty(l) ? printf('%dG%d|', l, c) : null_string
enddef

def Browse(url: string)
	dist#vim9#Open(b:git_origin .. url)
enddef

def TabNew()
	execute $":{tabpagenr() - 1} .. tabnew"
enddef

def GBrowse(sha: string)
	if empty(sha)
		EchoShrug()
		return
	endif
	execute 'GBrowse' sha
enddef

def Type(visual: bool): tuple<any, any>
	if visual
		const shas = min((line("."), line("v")))->getline(max((line("."), line("v"))))
			->map((_, val) => GvSha(val))->filter((_, val) => !empty(val))
		if len(shas) < 2
			return (0, 0)
		endif
		return ('diff', g:FugitiveShellCommand(['diff', shas[-1], shas[0]]))
	endif

	def HasGitOrigin(): bool
		if !exists('b:git_origin')
			SetGitOrigin()
		endif
		return b:git_origin == null_string ? false : true
	enddef

	const syn = synID(line('.'), col('.'), false)->synIDattr('name')
	if syn == 'gvGitHub' && HasGitOrigin()
		return ('link', '/issues/' .. expand('<cword>')[1 : ])
	elseif syn == 'gvTag' && HasGitOrigin()
		return ('link', '/releases/' .. getline('.')
			->matchstr('(tag: \zs[^ ,)]\+'))
	endif

	const sha = GvSha()
	return empty(sha) ? (0, 0) : ('commit', g:FugitiveFind(sha))
enddef

def Split(tab: bool)
	if tab
		TabNew()
	else
		const w = range(1, winnr('$'))
			->filter((_, val) => val->getwinvar("gv", false))
			->get(0)
		if w > 0
			execute $":{w}wincmd w"
			enew
		else
			vertical botright new
		endif
	endif
	w:gv = true
enddef

def Open(visual: bool, tab = false)
	const [type, target] = Type(visual)

	if empty(type)
		EchoShrug()
		return
	elseif type == 'link'
		Browse(target)
		return
	endif

	Split(tab)
	Scratch()
	if type == 'commit'
		execute 'e' target->escape(' ')
		nnoremap <buffer> gb <Cmd>GBrowse<CR>
	elseif type == 'diff'
		Fill(target)
		setf diff
	endif
	nnoremap <buffer> q <Cmd>close<CR>
	const bang = tab ? '!' : ''
	if exists('#User#GV' .. bang)
		execute 'doautocmd <nomodeline> User GV' .. bang
	endif
	wincmd p
	echo
enddef

def Dot(): string
	const sha = GvSha()
	return empty(sha) ? null_string : $":Git  {sha}\<S-Left>\<Left>"
enddef

def DiffFile(sha: string, file: string)
	execute($":{tabpagenr() - 1} tabnew file [Diff] {sha} - {file}")
	Scratch()
	const current_cmd = g:FugitiveShellCommand(['show', sha .. ':' .. file])
	systemlist(current_cmd)->setline(1)

	execute($"rightbelow vsplit [Diff] {sha}~1 - {file}")
	Scratch()
	const parent_cmd = g:FugitiveShellCommand(['show', sha .. '~1:' .. file])
	systemlist(parent_cmd)->setline(1)

	windo diffthis
	windo setlocal winfixwidth
	windo nnoremap <buffer> q <Cmd>tabclose<CR>

	wincmd p
enddef

def DiffView(sha: string)
	if empty(sha)
		EchoShrug()
		return
	endif

	const files: list<string> = g:FugitiveShellCommand(['show', '--name-only',
		'--pretty=', sha])->systemlist()->filter((_, val) => !empty(val))

	if empty(files)
		EchoWarn('No files modified in this commit')
	elseif len(files) == 1
		DiffFile(sha, files[0])
	else
		files->popup_menu({
			pos: "center",
			title: "Select file to view diff - " .. sha[0 : 7],
			borderchars: get(g:, "popup_borderchars",
				['─', '│', '─', '│', '┌', '┐', '┘', '└']),
			borderhighlight: get(g:, "popup_borderhighlight", ['Normal']),
			highlight: get(g:, "popup_highlight", 'Normal'),
			callback: (id, result) => {
				if result > 0
					const selected_file = files[result - 1]
					DiffFile(sha, selected_file)
				endif
			},
		})
	endif
enddef

def Maps()
	nnoremap <buffer><nowait> q  <Cmd>$wincmd w <Bar> close<CR>
	nnoremap <buffer><nowait> ZZ <Cmd>$wincmd w <Bar> close<CR>
	nnoremap <buffer><nowait> gq <Cmd>$wincmd w <Bar> close<CR>
	nnoremap <buffer><nowait> gb <ScriptCmd>GBrowse(GvSha())<CR>
	nnoremap <buffer><nowait> o  <ScriptCmd>Open(false)<CR>
	xnoremap <buffer><nowait> o  <ScriptCmd>Open(true)<CR>
	nnoremap <buffer><nowait> O  <ScriptCmd>Open(false, true)<CR>
	xnoremap <buffer><nowait> O  <ScriptCmd>Open(true, true)<CR>
	nnoremap <buffer><nowait> dd <ScriptCmd>DiffView(GvSha())<CR>
	nnoremap <buffer><nowait> <CR> <ScriptCmd>Open(false)<CR>
	xnoremap <buffer><nowait> <CR> <ScriptCmd>Open(true)<CR>
	nnoremap <buffer><nowait><expr> .  Dot()
	nnoremap <buffer><nowait><expr> ]] Move('')
	nnoremap <buffer><nowait><expr> ][ Move('')
	nnoremap <buffer><nowait><expr> [[ Move('b')
	nnoremap <buffer><nowait><expr> [] Move('b')
	xnoremap <buffer><nowait><expr> ]] Move('')
	xnoremap <buffer><nowait><expr> ][ Move('')
	xnoremap <buffer><nowait><expr> [[ Move('b')
	xnoremap <buffer><nowait><expr> [] Move('b')

	nnoremap <buffer> <C-N> ]]o
	nnoremap <buffer> <C-P> [[o
	xnoremap <buffer> <C-N> ]]ogv
	xnoremap <buffer> <C-P> [[ogv
enddef

def SetGitOrigin()
	const domain  = exists('g:fugitive_github_domains') ? ['github.com']
		->extend(g:fugitive_github_domains)
		->map((_, val) => val->split("://")[-1]->substitute("/*$", "", "")->escape("."))
		->join('\|') : '.*github.\+'
	# https://  github.com  /  junegunn/gv.vim  .git
	# git@      github.com  :  junegunn/gv.vim  .git
	const pat = '^\(https\?://\|git@\)\(' .. domain .. '\)[:/]\([^@:/]\+/[^@:/]\{-}\)\%(.git\)\?$'
	const origin = g:FugitiveRemoteUrl()->matchlist(pat)
	if !empty(origin)
		b:git_origin = printf('%s%s/%s',
			origin[1] =~ '^http' ? origin[1] : 'https://', origin[2], origin[3])
	else
		b:git_origin = null_string
	endif
enddef

def Scratch()
	setlocal buftype=nofile bufhidden=wipe noswapfile nomodeline
enddef

def Fill(cmd: string)
	setlocal modifiable
	:%delete _
	systemlist(cmd)->setline(1)
	setlocal nomodifiable
enddef

def Tracked(file: string): bool
	system(g:FugitiveShellCommand(['ls-files', '--error-unmatch', file]))
	return !v:shell_error
enddef

def CheckBuffer(current: string)
	if empty(current)
		throw 'untracked buffer'
	elseif !Tracked(current)
		throw current .. ' is untracked'
	endif
enddef

def LogOpts(bang: bool, visual: bool, line1: number, line2: number): tuple<list<string>, list<any>>
	if visual || bang
		const current = expand('%')
		CheckBuffer(current)
		return visual ? ([printf('-L%d,%d:%s', line1, line2, current)], []) : (['--follow'], ['--', current])
	endif
	return (['--graph'], [])
enddef

def List(log_opts: list<string>)
	const default_opts = ['--color=never', '--date=short', '--format=%cd %h%d %s (%an)']
	const git_args = ['log'] + default_opts + log_opts
	const git_log_cmd = g:FugitiveShellCommand(git_args)

	const repo_short_name = g:FugitiveGitDir()->substitute('[\\/]\.git[\\/]\?$', '', '')->fnamemodify(':t')
	const bufname = repo_short_name .. ' ' .. join(log_opts)
	silent exe (bufexists(bufname) ? 'buffer' : 'file') fnameescape(bufname)

	Scratch()
	setlocal nowrap tabstop=8 cursorline nolist iskeyword+=#
	if !exists(':GBrowse')
		doautocmd <nomodeline> User Fugitive
	endif
	Maps()
	setfiletype GV
	echo mapping_helps

	Fill(git_log_cmd)
enddef

def Trim(arg: string): string
	const trimmed = arg->trim()
	return trimmed =~ "^'.*'$" ? trimmed[1 : -2]->substitute("''", '', 'g')
		: trimmed =~ '^".*"$' ? trimmed[1 : -2]->substitute('""', '', 'g')->substitute('\\"', '"', 'g')
		: trimmed->substitute('""\|''''', '', 'g')->substitute('\\ ', ' ', 'g')
enddef

def GvShellwords(arg: string): list<string>
	var words: list<string>
	var contd = false
	for token in arg->split('\%(\%(''\%([^'']\|''''\)\+''\)\|\%("\%(\\"\|[^"]\)\+"\)\|\%(\%(\\ \|\S\)\+\)\)\s*\zs')
		const trimmed = Trim(token)
		if contd
			words[-1] ..= trimmed
		else
			words->add(trimmed)
		endif
		contd = token !~ '\s\+$'
	endfor
	return words
enddef

def SplitPathspec(args: list<string>): tuple<list<string>, list<string>>
	const split = args->index('--')
	if split < 0
		return (args, [])
	elseif split == 0
		return ([], args)
	endif
	return (args[0 : split - 1], args[split :])
enddef

def Gl(buf: number, visual: bool)
	if !exists(':Gllog')
		return
	endif
	tab split
	silent execute visual ? "'<,'>Gllog" : ':0Gllog'
	const win = winnr()
	getloclist(win)->insert({bufnr: buf, text: bufname(buf)})->setloclist(win, 'r')
	setloclist(win, [], 'a', {title: mapping_helps})

	noautocmd b %%

	lopen
	xnoremap <buffer> o <ScriptCmd>Gld(line("v"), line("."))<CR>
	nnoremap <buffer> o <CR><C-W><C-W>
	nnoremap <buffer> O <ScriptCmd>Gld(line("."), line("."))<CR>
	nnoremap <buffer> q <Cmd>tabclose<CR>
	nnoremap <buffer> gq <Cmd>tabclose<CR>
	"Conceal"->matchadd('^fugitive://.\{-}\.git//')
	"Conceal"->matchadd('^fugitive://.\{-}\.git//\x\{7}\zs.\{-}||')
	setlocal concealcursor=nv conceallevel=3 nowrap
enddef

def Gld(start: number, end: number)
	const to   = (start, end)->min()->getline()->split("|")[0]
	const from = (start, end)->max()->getline()->split("|")[0]
	execute $":{tabpagenr() - 1}tabedit" escape(to, ' ')
	if from !=# to
		execute 'vsplit' escape(from, ' ')
		windo diffthis
	endif
enddef

export def GV(bang: bool, visual: bool, line1: number, line2: number, args: string)
	if !exists('g:loaded_fugitive')
		EchoWarn('fugitive not found')
		return
	endif

	if empty(g:FugitiveGitDir())
		EchoWarn('not in git repo')
		return
	endif

	const cd = exists('*haslocaldir') && haslocaldir() ? 'lcd' : 'cd'
	const cwd = getcwd()
	const root = g:FugitiveFind(':/')
	try
		if cwd !=# root
			execute cd root->escape(' ')
		endif
		if args =~ '?$'
			if len(args) > 1
				EchoWarn('invalid arguments')
				return
			endif
			CheckBuffer(expand('%'))
			Gl(bufnr(), visual)
		else
			const [opts1, paths1] = LogOpts(bang, visual, line1, line2)
			const [opts2, paths2] = SplitPathspec(GvShellwords(args))
			const log_opts = opts1 + opts2 + paths1 + paths2
			TabNew()
			List(log_opts)
			g:FugitiveDetect(@#)
		endif
	catch
		EchoWarn(v:exception)
	finally
		if getcwd() !=# cwd
			execute cd cwd->escape(' ')
		endif
	endtry
enddef
# vim:noet ts=4
