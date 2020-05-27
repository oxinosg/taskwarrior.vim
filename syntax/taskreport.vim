if exists("b:current_syntax")
    finish
endif

if exists('b:task_report_labels')
    syntax match taskwarrior_tablehead /.*\%1l/
endif

for n in b:sline
    execute 'syntax match taskwarrior_selected /.*\%'.n.'l/ contains=ALL'
endfor

if search('[^\x00-\xff]') == 0
    let exp = 'syntax match taskwarrior_%s /\%%>1l\%%%dc.*\%%<%dc/%s'
else
    let exp = 'syntax match taskwarrior_%s /\%%>1l\%%%dv.*\%%<%dv/%s'
endif


if exists('b:task_columns') && exists('b:task_report_columns')
    for i in range(0, len(b:task_report_columns)-1)
        let custom_keywords = ''

        if exists('b:task_columns['.(i+1).']')
          for obj in g:task_keyword_highlight
            if obj['depends'] == b:task_report_columns[i]
              if custom_keywords == ''
                let custom_keywords = ' contains=' . obj['depends'] . '_' . obj['keyword']
              else
                let custom_keywords = custom_keywords . ',' . obj['depends'] . '_' . obj['keyword']
              endif
            endif
          endfor

          execute printf(exp, matchstr(b:task_report_columns[i], '^\w\+') , b:task_columns[i]+1, b:task_columns[i+1]+1, custom_keywords)
        endif
    endfor
endif

for obj in g:task_keyword_highlight
  execute 'syn keyword ' . obj['depends'] . '_' . obj['keyword'] . ' ' . obj['keyword'] . ' contained'
  execute 'hi ' . obj['depends'] . '_' . obj['keyword'] . ' ctermfg=' . obj['color']
endfor

highlight default link taskwarrior_tablehead   Tabline
highlight default link taskwarrior_field       IncSearch
highlight default link taskwarrior_selected    Visual
highlight default link taskwarrior_id          VarId
highlight default link taskwarrior_project     String
highlight default link taskwarrior_status      Include
highlight default link taskwarrior_priority    Class
highlight default link taskwarrior_due         Todo
highlight default link taskwarrior_end         Keyword
highlight default link taskwarrior_description Normal
highlight default link taskwarrior_entry       Special
highlight default link taskwarrior_depends     Todo
highlight default link taskwarrior_tags        Keyword
highlight default link taskwarrior_uuid        VarId
highlight default link taskwarrior_urgency     Todo

let b:current_syntax = 'taskreport'
