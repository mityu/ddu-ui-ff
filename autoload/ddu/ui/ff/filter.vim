function ddu#ui#ff#filter#_open(name, input, parent_id, changed_params, params) abort
  if !'s:filter_bufnr'->exists()
    " NOTE: Filter buffer must be unique
    let s:filter_bufnr = bufadd('ddu-ff-filter')
  endif

  const ids = s:filter_bufnr->win_findbuf()
  if !empty(ids)
    call win_gotoid(ids[0])

    if a:changed_params
      " NOTE: Need redraw filter window
      close!
      call s:init_buffer(a:name, a:params)
    else
      call cursor('$'->line(), 0)
    endif
  else
    call s:init_buffer(a:name, a:params)
  endif

  if !&l:modifiable
    " NOTE: Something wrong.  Close UI window.
    call ddu#util#print_error('Failed to open filter window.')
    call ddu#ui_sync_action(a:name, 'quit')
    return -1
  endif

  " Set the current input
  if '$'->getline() ==# ''
    call setline('$', a:input)
  else
    call append('$', a:input)
  endif

  call cursor('$'->line(), 0)

  augroup ddu-ff-filter
    autocmd!
  augroup END

  " Disable backspace eol.
  let s:save_backspace = &backspace
  set backspace-=eol

  " Disable whichwrap.
  let s:save_whichwrap = &whichwrap
  set whichwrap=

  autocmd ddu-ff-filter WinClosed,BufLeave <buffer> ++once
        \ : let &backspace = s:save_backspace
        \ | let &whichwrap = s:save_whichwrap

  if !has('nvim') && a:params.split ==# 'floating'
    " Vim's popup does not support enter the window
    autocmd ddu-ff-filter WinClosed <buffer>
          \ call ddu#ui#do_action('quit')
  endif

  " NOTE: prompt must set after cursor move
  if a:params.prompt !=# ''
    setlocal signcolumn=yes
    call s:init_prompt(a:params.prompt,
          \ a:params.highlights->get('prompt', 'Special'))
  else
    setlocal signcolumn=no
  endif

  " NOTE: startinsert! does not work in resume or autoAction
  if mode() ==# 'n'
    call feedkeys('.'->getline() ==# '' ? 'i' : 'A', 'ni')
  else
    startinsert!
  endif

  if 'g:ddu#ui#ff#_save_title'->exists()
    call ddu#ui#ff#_set_title(a:parent_id->winbufnr(), a:parent_id)

    autocmd ddu-ff-filter WinEnter,BufEnter <buffer>
          \ call ddu#ui#ff#_set_title(
          \   g:ddu#ui#ff#_filter_parent_winid->winbufnr(),
          \   g:ddu#ui#ff#_filter_parent_winid)
  endif

  let s:filter_prev_input = '.'->getline()
  let s:filter_updatetime = a:params.filterUpdateTime
  let g:ddu#ui#ff#_filter_parent_winid = a:parent_id

  autocmd ddu-ff-filter
        \ InsertEnter,TextChangedI,TextChangedP,TextChanged,InsertLeave
        \ <buffer> call s:check_update()

  return s:filter_bufnr
endfunction

function ddu#ui#ff#filter#_floating(bufnr, parent, params) abort
  const is_floating =
        \ a:params.split ==# 'floating'
        \ || a:params.filterSplitDirection ==# 'floating'

  if !has('nvim') || !is_floating
    return
  endif

  let row = a:params.filterFloatingPosition ==# 'bottom'
        \ ? a:parent->winheight() : -1
  " NOTE: "floatingBorder" may be array.
  " "!=#" does not work for array.
  if a:params.floatingBorder isnot# 'none'
    " Calc border offset
    if a:params.filterFloatingPosition ==# 'top'
      let row -= 2
    else
      let row += 2
    endif
  endif

  if a:params.split ==# 'floating'
    let row += a:params.winRow
    const col = a:params.winCol
  else
    const winpos = a:parent->win_screenpos()
    let row += winpos[0] - 1
    const col = winpos[1] - 1
  endif

  " NOTE: relative: win does not work for resume feature
  let params = #{
        \   relative: 'editor',
        \   row: row,
        \   col: col,
        \   width: a:params.winWidth,
        \   height: 1,
        \   border: a:params.floatingBorder,
        \   title: a:params.filterFloatingTitle,
        \   title_pos: a:params.filterFloatingTitlePos,
        \ }
  if !has('nvim-0.9.0')
    call remove(params, 'title')
    call remove(params, 'title_pos')
  endif

  if a:bufnr->bufwinid() > 0
    call nvim_win_set_config(a:bufnr->bufwinid(), params)
    const id = a:bufnr->bufwinid()
  else
    " statusline must be set for floating window
    const statusline = &l:statusline
    const id = nvim_open_win(a:bufnr, v:true, params)
    call setwinvar(id, '&statusline', statusline)
  endif

  const highlight = a:params.highlights->get('floating', 'NormalFloat')
  const floating_highlight = a:params.highlights->get(
        \ 'floatingBorder', 'FloatBorder')
  call setwinvar(id, '&winhighlight',
        \ 'Normal:' .. highlight .. ',FloatBorder:' .. floating_highlight)

  if '+winfixbuf'->exists()
    call setwinvar(id, '&winfixbuf', v:true)
  endif
endfunction

function s:init_buffer(name, params) abort
  const is_floating =
        \ a:params.split ==# 'floating'
        \ || a:params.filterSplitDirection ==# 'floating'

  if has('nvim') && is_floating
    call ddu#ui#ff#filter#_floating(s:filter_bufnr, win_getid(), a:params)
  else
    const direction = is_floating ?
          \ 'belowright' : a:params.filterSplitDirection
    silent execute direction 'sbuffer' s:filter_bufnr
  endif

  let b:ddu_ui_name = a:name

  setlocal bufhidden=hide
  setlocal buftype=nofile
  setlocal colorcolumn=
  setlocal foldcolumn=0
  setlocal nobuflisted
  setlocal nofoldenable
  setlocal nolist
  setlocal nomodeline
  setlocal nonumber
  setlocal norelativenumber
  setlocal nospell
  setlocal noswapfile
  setlocal nowrap
  setlocal winfixheight
  if '+statuscolumn'->exists()
    setlocal statuscolumn=
  endif

  resize 1

  setfiletype ddu-ff-filter

  const highlight = a:params.highlights->get('filterText', '')
  if highlight !=# ''
    execute 'highlight link FilterText' highlight
    syntax match FilterText '^.*$'
  endif
endfunction

let s:prompt_name = 'ddu_ui_ff_filter_prompt'
function s:init_prompt(prompt, highlight_prompt) abort
  call sign_define(s:prompt_name, #{
        \   text: a:prompt->strwidth() > 2 ? '>' : a:prompt,
        \   texthl: a:highlight_prompt,
        \ })

  call s:update_prompt()

  augroup ddu-ff-filter
    autocmd TextChangedI,TextChangedP,TextChanged <buffer>
          \ : if s:prev_lnum != '$'->line()
          \ |   call s:update_prompt()
          \ | endif
  augroup END
endfunction
function s:update_prompt() abort
  const id = 2000
  call sign_unplace('', #{
        \   id: id,
        \   buffer: '%'->bufnr(),
        \ })
  call sign_place(id, '', s:prompt_name, '%'->bufnr(), #{
        \   lnum: '.'->line(),
        \ })
  let s:prev_lnum = '$'->line()
endfunction

function s:check_update() abort
  if s:filter_updatetime > 0
    call ddu#ui#ff#_stop_debounce_timer('s:debounce_filter_update_timer')

    let s:debounce_filter_update_timer = timer_start(
          \ s:filter_updatetime, { -> s:check_redraw() })
  else
    call s:check_redraw()
  endif
endfunction
function s:check_redraw() abort
  const input = '.'->getline()

  if &l:filetype !=# 'ddu-ff-filter' || input ==# s:filter_prev_input
    return
  endif

  let s:filter_prev_input = input

  call ddu#redraw(b:ddu_ui_name, #{ input: input })
endfunction
