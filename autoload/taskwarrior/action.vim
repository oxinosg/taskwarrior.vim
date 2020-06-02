function! taskwarrior#action#new()
  let l:add_args = taskwarrior#data#get_args('add')
  if l:add_args != "\<ESC>"
    call taskwarrior#system_call('', 'add', l:add_args, 'echo')
  endif
endfunction

function! taskwarrior#action#set_done()
  call taskwarrior#system_call(taskwarrior#data#get_uuid(), ' done', '', 'silent')
endfunction

function! taskwarrior#action#urgency() abort
  let cc   = taskwarrior#data#current_column()
  let udas = split(system(g:tw_cmd.' _udas'), '\n')
  let cmap = { 'start' : 'active',
        \ 'entry' : 'age',
        \ 'depends' : 'blocked',
        \ 'parent' : 'blocking',
        \ 'wait' : 'waiting',
        \ 'description' : 'annotations'
        \ }
  let isuda = 0
  if has_key(cmap, cc)
    let cc = cmap[cc]
  elseif index(['due', 'priority', 'project', 'tags', 'scheduled']
        \ , cc) == -1
    if index(udas, cc) == -1
      call taskwarrior#sort#by_arg('urgency-')
      return
    else
      let isuda = 1
    endif
  endif
  let rcfile = $HOME.'/.taskrc'
  if filereadable(rcfile)
    let cv = taskwarrior#data#get_value_by_column(line('.'), cc)
    let option = isuda ? 'urgency.uda.'.cc.'.coefficient' :
          \ 'urgency.'.cc.'.coefficient'
    if len(cv)
      let ctag = expand('<cword>')
      if cc == 'tags' && index(split(cv), ctag) != -1
        let option = 'urgency.user.tag.'.ctag.'.coefficient'
      elseif cc == 'project' && cv =~ '^[^ \t%\\*]\+$'
        let pl = split(cv, '\.')
        let idx = index(pl, expand('<cword>'))
        let option = 'urgency.user.project.'.
              \ join(pl[0:idx], '.').'.coefficient'
      elseif isuda && cv =~ '^\w\+$'
        let option = 'urgency.uda.'.cc.'.'.cv.'.coefficient'
      endif
    endif
    let default_raw = split(system(g:tw_cmd.' _get rc.'.option), '\n')
    let default     = len(default_raw) ? default_raw[0] : '0'
    let new         = input(option.' : ', default)
    let lines       = readfile(rcfile)
    let index       = match(lines, option)
    if str2float(new) == str2float(default)
    elseif str2float(new) == 0
      call filter(lines, 'v:val !~ option')
    elseif index == -1
      call add(lines, option.'='.new)
    else
      let lines[index] = option.'='.new
    endif
    call writefile(lines, rcfile)
  endif
  call taskwarrior#sort#by_arg('urgency-')
  execute 'normal! :\<Esc>'
endfunction

" modify items under cursor or the whole item
function! taskwarrior#action#modify(mode)
  let uuid = taskwarrior#data#get_uuid()

  if uuid == ''
    return
  endif

  if a:mode == 'current' " modify current item under cursor
    let field = taskwarrior#data#current_column()
    if index(['id', 'uuid', 'status', 'urgency', 'entry'], field) != -1 " these items should not be modified
      return
    else
      let l:args = taskwarrior#data#get_args('modify', [field])
      if l:args != "\<ESC>"
        call taskwarrior#system_call(uuid, 'modify', l:args, 'silent')
      endif
    endif

  else " modify the whole item
    let l:args = taskwarrior#data#get_args('modify')
    if l:args != "\<ESC>"
      call taskwarrior#system_call(uuid, 'modify', l:args, 'echo')
    endif
  endif

endfunction

function! taskwarrior#action#delete()
  let uuid = taskwarrior#data#get_uuid()
  if uuid == ''
    call taskwarrior#action#annotate('del')
  else
    let ccol = taskwarrior#data#current_column()
    if index(['project', 'tags', 'due', 'priority', 'start', 'depends'], ccol) != -1
      call system(g:tw_cmd.' '.uuid.' del rc.confirmation=no')
    else
      if confirm("Delete task ".uuid."?", "&Yes\n&No", 1) == 1
        call system(g:tw_cmd.' '.uuid.' del rc.confirmation=no')
      endif
    endif
  endif
  call taskwarrior#refresh()
endfunction

function! taskwarrior#action#annotate(op)
  let ln = line('.')
  let offset = -1
  while ln > 1 && taskwarrior#data#get_uuid(ln) == ''
    let ln -= 1
    let offset += 1
  endwhile
  let uuid = taskwarrior#data#get_uuid(ln)
  if uuid == ''
    return
  endif
  if a:op == 'add'
    let annotation = input('new annotation:', '', 'file')
    call taskwarrior#system_call(uuid, ' annotate ', annotation, 'silent')
  elseif a:op == 'del'
    let annotation = input('annotation pattern to delete:')
    call taskwarrior#system_call(uuid, ' denotate ', annotation, 'silent')
  elseif offset >= 0
    let taskobj = taskwarrior#data#get_query(uuid)
    if exists('taskobj.annotations[offset].description')
      let file = substitute(taskobj.annotations[offset].description, '\s*\/\s*', '/', 'g')
      let file = escape(file, ' ')
      let ft = 'text'
      if executable('file')
        let ft = system('file '.file)[:-2]
      endif
      if ft =~ 'text$'
        execute 'e '.file
      elseif ft !~ '(No such file or directory)' || file =~ '[a-z]*:\/\/[^ >,;]*'
        if executable('xdg-open')
          call system('xdg-open '.file.'&')
        elseif executable('open')
          call system('open '.file.'&')
        endif
      endif
    endif
  endif
endfunction

function! taskwarrior#action#filter()
  let column = taskwarrior#data#current_column()
  if index(['project', 'tags', 'status', 'priority'], column) != -1 && line('.') > 1
    let filter = substitute(substitute(taskwarrior#data#get_args('modify', [column]), 'tags:', '+', ''), '\v^\s*\+(\s|$)', '', '')
  elseif column =~ '\v^(entry|end|due)$'
    let filter = column.'.before:'.input(column.'.before:', taskwarrior#data#get_value_by_column('.', column))
  elseif column == 'description'
    let filter = 'description:'.input('description:', taskwarrior#data#get_value_by_column('.', column) )
  else
    let filter = input('new filter:', b:filter, 'customlist,taskwarrior#complete#filter')
  endif
  let filter = substitute(filter, 'status:\(\s\|$\)', 'status.any: ', 'g')
  if filter != b:filter
    let b:filter = filter
    let b:hist = 1
    call taskwarrior#list()
  endif
endfunction

function! taskwarrior#action#command()
  if len(b:selected) == 0
    let filter = taskwarrior#data#get_uuid()
  else
    let filter = join(b:selected, ',')
  endif
  let command = input(g:tw_cmd.' '.filter.':', '', 'customlist,taskwarrior#complete#command')
  if index(g:task_all_commands, b:command) == -1
    return
  endif
  call taskwarrior#system_call(filter, command, '', 'interactive')
endfunction

function! taskwarrior#action#report()
  let command = input('new report:', g:task_report_name, 'customlist,taskwarrior#complete#report')
  if index(g:task_report_command, command) != -1 && command != b:command
    let b:command = command
    let b:hist = 1
    call taskwarrior#list()
  endif
endfunction

function! taskwarrior#action#paste()
  if len(b:selected) == 0
    return
  elseif len(b:selected) < 3
    call taskwarrior#system_call(join(b:selected, ','), 'duplicate', '', 'echo')
  else
    call taskwarrior#system_call(join(b:selected, ','), 'duplicate', '', 'interactive')
  endif
endfunction

function! taskwarrior#action#columns_format_change(direction)
  let ccol     = taskwarrior#data#current_column()
  if !exists('g:task_columns_format[ccol]')
    return
  endif
  let clist    = g:task_columns_format[ccol]
  if len(clist) == 1
    return
  endif
  let ccol_ful = b:task_report_columns[taskwarrior#data#current_index()]
  let ccol_sub = matchstr(ccol_ful, '\.\zs.*')
  let rcl      = matchstr(b:rc, 'rc\.report\.'.b:command.'\.columns.\zs\S*')
  " let dfl      = system('task _get -- rc.report.'.b:command.'.columns')[0:-2]
  let dfl      = matchstr(system(g:tw_cmd.' show | '.g:tw_grep.' report.'.b:command.'.columns')[0:-2], '\S*$')
  let index    = index(clist, ccol_sub)
  let index    = index == -1 ? 0 : index
  if a:direction == 'left'
    let index -= 1
  else
    let index += 1
    if index == len(clist)
      let index = 0
    endif
  endif
  let newsub = index == 0 ? '' : '.'.clist[index]
  let b:rc .= ' rc.report.'.b:command.'.columns:'.
        \ substitute(
        \   rcl == '' ? dfl : rcl,
        \   '[=:,]\zs'.ccol_ful.'\ze\(,\|$\)',
        \   ccol.newsub, ''
        \ )
  let b:hist = 1
  call taskwarrior#list()
endfunction

function! taskwarrior#action#date(count)
  let ccol = taskwarrior#data#current_column()
  if index(['due', 'end', 'entry'], ccol) == -1
    return
  endif
  setlocal modifiable
  if exists('g:loaded_speeddating')
    call speeddating#increment(a:count)
  elseif a:count > 0
    execute 'normal! '.a:count.''
  else
    execute 'normal! '.-a:count.''
  endif
  let b:ct = taskwarrior#data#get_uuid()
  call taskwarrior#system_call(b:ct, 'modify', ccol.':'.taskwarrior#data#get_value_by_column('.', ccol, 'temp'), 'silent')
endfunction

function! taskwarrior#action#visual(action) range
  let line1 = getpos("'<")[1]
  let line2 = getpos("'>")[1]
  let fil = []
  let lin = []
  for l in range(line1, line2)
    let uuid = taskwarrior#data#get_uuid(l)
    if uuid !~ '^\s*$'
      let fil += [uuid]
      let lin += [l]
    endif
  endfor
  let filter = join(fil, ',')
  if a:action == 'done'
    call taskwarrior#system_call(filter, 'done', '', 'interactive')
  elseif a:action == 'delete'
    call taskwarrior#system_call(filter, 'delete', '', 'interactive')
  elseif a:action == 'info'
    call taskinfo#init('information', filter, split(system(g:tw_cmd.' information '.filter), '\n'))
  elseif a:action == 'select'
    for var in fil
      let index = index(b:selected, var)
      if index == -1
        let b:selected += [var]
        let b:sline += [lin[index(fil, var)]]
      else
        call remove(b:selected, index)
        call remove(b:sline, index)
      endif
    endfor
    let b:sstring = join(b:selected, ' ')
    setlocal syntax=taskreport
  endif
endfunction

function! taskwarrior#action#move_cursor(direction, mode)
  let ci = taskwarrior#data#current_index()
  if ci == -1 || (ci == 0 && a:direction == 'left') || (ci == len(b:task_columns)-1 && a:direction == 'right')
    return
  endif
  if a:direction == 'left'
    call search('\%'.(b:task_columns[ci-1]+1).'v', 'be')
  else
    call search('\%'.(b:task_columns[ci+1]+1).'v', 'e')
  endif
  if a:mode == 'skip' && taskwarrior#data#get_value_by_index('.', taskwarrior#data#current_index()) =~ '^\s*$'
    call taskwarrior#action#move_cursor(a:direction, 'skip')
  endif
endfunction

function! taskwarrior#action#undo()
  if has("gui_running")
    if exists('g:task_gui_term') && g:task_gui_term == 1
      !g:tw_cmd undo
    elseif executable('xterm')
      silent !xterm -e 'task undo'
    elseif executable('urxvt')
      silent !urxvt -e task undo
    elseif executable('gnome-terminal')
      silent !gnome-terminal -e 'task undo'
    endif
  else
    sil !clear
    execute '!'.g:tw_cmd.' undo rc.confirmation=no'
  endif
  call taskwarrior#refresh()
endfunction

function! taskwarrior#action#clear_completed()
  !g:tw_cmd status:completed delete
  call taskwarrior#refresh()
endfunction

function! taskwarrior#action#sync(action)
  execute '!'.g:tw_cmd.' '.a:action.' '
  call taskwarrior#refresh()
endfunction

function! taskwarrior#action#select()
  let uuid = taskwarrior#data#get_uuid()
  if uuid == ''
    return
  endif
  let index = index(b:selected, uuid)
  if index == -1
    let b:selected += [uuid]
    let b:sline += [line('.')]
  else
    call remove(b:selected, index)
    call remove(b:sline, index)
  endif
  let b:sstring = join(b:selected, ' ')
  setlocal syntax=taskreport
endfunction

function! taskwarrior#action#show_info(...)
  if a:0 > 0
    let command = 'info'
    let filter = a:1
  else
    let ccol = taskwarrior#data#current_column()
    let dict = { 'project': 'projects',
          \ 'tags': 'tags',
          \ 'id': 'stats',
          \ 'depends': 'blocking',
          \ 'recur': 'recurring',
          \ 'due': 'overdue',
          \ 'wait': 'waiting',
          \ 'urgency': 'ready',
          \ 'entry': 'history.monthly',
          \ 'end': 'history.monthly'}
    let command = get(dict, ccol, 'summary')
    let uuid = taskwarrior#data#get_uuid()
    if uuid !~ '^\s*$'
      let command = substitute(command, '\v(summary|stats)', 'information', '')
      let filter = taskwarrior#data#get_uuid()
    else
      let filter = b:filter
    endif
  endif
  call taskinfo#init(command, filter, split(system(g:tw_cmd.' '.command.' '.filter), '\n'))
endfunction

function! taskwarrior#action#handle_click()
  let ln = line('.')
  let l:uuid = taskwarrior#data#get_uuid(ln)

  if l:uuid == ''
    return
  endif

  let l:field = taskwarrior#data#current_column()
  if index(['id', 'uuid'], l:field) != -1
      call taskwarrior#action#show_info()
  elseif l:field == 'description'
    let l:value = taskwarrior#data#get_value_by_column('.', l:field)
    let l:prompt = input(l:field . ': ', l:value)

    if l:prompt ==  ""
      echo "\<cr>"."modification cancelled."
      return 
    else
      call taskwarrior#system_call(uuid, 'modify', ' ' . l:field . '="' . l:prompt . '"', 'silent')
      echo "\<cr>" . "modification completed"
    endif
  else
    let l:udaNames = system(g:tw_cmd.' _udas')
    let l:filterableNames = split(l:udaNames, '\n') + ['status', 'project']
    if index(l:filterableNames, l:field) != -1
      let l:fieldFilter = l:field . ':' . taskwarrior#data#get_value_by_column('.', l:field)
      if index(split(b:filter, ' '), l:fieldFilter) != -1
        let b:filter = substitute(b:filter, l:fieldFilter, '', 'g')
        let b:hist = 1
        call taskwarrior#list()
      else
        let b:filter = b:filter . ' ' . l:fieldFilter
        let b:hist = 1
        call taskwarrior#list()
      endif
    endif
    return
  endif
endfunction

function! taskwarrior#action#_add_task(f)
  execute  ':TW ' . taskwarrior#data#get_uuid() . ' modify ' . s:attributeKey .  ':' . a:f
endfunction

function! taskwarrior#action#_select_value(f)
  let l:values = system(g:tw_cmd . ' _show | grep uda.' . a:f . '.values | cut -f2- -d =')
  if l:values != ""
    let s:attributeKey = a:f
    let l:attributeValues = split(l:values, ',')
    call fzf#run({ 'source': l:attributeValues,
        \ 'options': '+m -d "\t" --with-nth 1,4.. -n 1 --tiebreak=index',
        \ 'down':    '40%',
        \ 'sink': function('taskwarrior#action#_add_task') })
  endif
endfunction

function! taskwarrior#action#add_attribute()
  let l:udaNames = system(g:tw_cmd.' _udas')
  " let l:filterableNames = add(split(l:udaNames, '\n'), 'priority')
  let l:filterableNames = split(l:udaNames, '\n')
  call fzf#run({ 'source': l:filterableNames, 
        \ 'options': '+m -d "\t" --with-nth 1,4.. -n 1 --tiebreak=index',
        \ 'down':    '40%',
        \ 'sink': function('taskwarrior#action#_select_value') })
endfunction

function! taskwarrior#action#remove_attribute()
  let l:field = taskwarrior#data#current_column()
  let l:udaNames = system(g:tw_cmd.' _udas')
  let l:filterableNames = split(l:udaNames, '\n')
  if index(l:filterableNames, l:field) != -1
    execute  ':TW ' . taskwarrior#data#get_uuid() . ' modify ' . l:field . '='
  endif
endfunction

function! taskwarrior#action#generate_report()
  if g:task_auto_generate_reports
    let l:path = finddir('.git/..', expand('%:p').';')
    if (l:path != '')
      let l:name = split(l:path, '/')

      if (len(name) > 0)
        let l:label_command = system(g:tw_cmd . ' _show | grep "report.minimal.labels"')
        let l:label_command = substitute(l:label_command, 'report.minimal.labels=ID,', 'report.minimal.labels=', 'g')
        let l:label_command = split(l:label_command, '\n')[0]

        let l:column_command = system(g:tw_cmd . ' _show | grep "report.minimal.columns"')
        let l:column_command = substitute(l:column_command, 'report.minimal.columns=id,', 'report.minimal.columns=', 'g')
        let l:column_command = split(l:column_command, '\n')[0]

        let l:command = g:tw_cmd . ' rc.' . l:label_command . ' rc.' . l:column_command  . ' rc.defaultwidth=999 rc.report.minimal.filter="(status:pending or status:completed)" minimal project:' . l:name[-1]
        let l:report = system(l:command)
        let l:report = split(l:report, '\n')
        let l:column_sizes = system(l:command . ' 2>/dev/null | sed -n 3p')
        let l:column_sizes = split(l:column_sizes, ' ')

        let l:val = ""
        for l:line in l:report[0:-7]
          let l:start_pos = 0

          for l:size in l:column_sizes[0:-1]
            let l:val = l:val . '| ' .  strcharpart(strpart(l:line, 0), start_pos, len(l:size)) . ' '
            let l:start_pos = l:start_pos + len(l:size) + 1
          endfor

          let l:val = l:val . '\n'
        endfor

        let l:execute = system('printf "<!-- This is an autogenerated report -->\n\n' . l:val. '" > ' . l:path . '/report.md')

        echo 'Report generated at `' . l:path . '/report.md' . '`'
      endif
    endif
  else
    echo 'Generation of reports is disabled'
  endif
endfunction

" update project config to add column/label to report of project udas
function! taskwarrior#action#update_project_config()
  let l:path = finddir('.git/..', expand('%:p').';')
  if (l:path != '')
    let l:minimal_label = system(g:tw_cmd . ' _show | grep minimal.labels')
    let l:minimal_columns = system(g:tw_cmd . ' _show | grep minimal.columns')
    let l:udas = system(g:tw_cmd . ' _udas')
    let l:uda_list = split(l:udas, '\n')
    let l:modified = 0

    for l:uda in l:uda_list
      if stridx(l:minimal_columns, l:uda) == -1
        let l:minimal_columns = substitute(l:minimal_columns, ',description', ',' . l:uda . ',description' ,'g')
        let l:minimal_columns = split(l:minimal_columns, '\n')[0]
        let l:modified = 1
      endif

      let l:uda_label = system(g:tw_cmd . ' _show | grep uda.' . l:uda . '.label= | cut -f2 -d"="')
      let l:uda_label = split(l:uda_label, '\n')[0]

      if stridx(l:minimal_label, l:uda_label) == -1
        let l:minimal_label = substitute(l:minimal_label, ',Description', ',' . l:uda_label . ',Description' ,'g')
        let l:minimal_label = split(l:minimal_label, '\n')[0]
        let l:modified = 1
      endif
    endfor

    if l:modified == 1
      let l:label_exists = system('grep -i report.minimal.labels= ' . l:path . '/.vim_taskrc')
      let l:columns_exists = system('grep -i report.minimal.columns= ' . l:path . '/.vim_taskrc')

      if l:label_exists == ''
        call system('echo "\n' . l:minimal_label . '" &>> ' . l:path . '/.vim_taskrc')
      else
        echo 'sed -i -e "s/report.minimal.labels=.*/' . l:minimal_label . '/g" "' . l:path . '/.vim_taskrc"'
        call system('sed -i -e "s/report.minimal.labels=.*/' . l:minimal_label . '/g" "' . l:path . '/.vim_taskrc"')
      endif

      if l:columns_exists == ''
        call system('echo "\n' . l:minimal_columns . '" &>> ' . l:path . '/.vim_taskrc')
      else
        call system('sed -i -e "s/report.minimal.columns=.*/' . l:minimal_columns . '/g" "' . l:path . '/.vim_taskrc"')
      endif
    endif
  endif
endfunction

function! taskwarrior#action#create_project_config()
  let l:path = finddir('.git/..', expand('%:p').';')
  if (l:path != '')
    let l:name = split(l:path, '/')

    if empty(glob(l:path . '/.vim_taskrc'))
      call system('echo -e "include ~/.taskrc \n" >> ' . l:path . '/.vim_taskrc')
      
      echo "File created: " . l:path . '/.vim_taskrc'
    endif
  endif
endfunction

" TODO in case project name contains special characters i.e. `-` report fails
" TODO in case uda is same as project, report fails
function! taskwarrior#action#add_project_uda()
  let l:path = finddir('.git/..', expand('%:p').';')
  if (l:path != '')
    let l:key = input('Enter uda key: ')
    let l:label = input('Enter uda label: ')
    let l:values = input('Enter uda values separated by comma: ')

    if l:key != '' && l:label != '' && l:values != ''
      call taskwarrior#action#create_project_config()

      call system('echo "\nuda.' . l:key . '.type=string\nuda.' . l:key . '.label=' . l:label . '\nuda.' . l:key . '.values=' . l:values . '" &>> ' . l:path . '/.vim_taskrc')

      let g:tw_cmd = 'TASKRC=' . l:path . '/.vim_taskrc ' . split(g:tw_cmd, " ")[-1]

      call taskwarrior#action#update_project_config()
      echo 'Done!'
    endif
  endif
endfunction
