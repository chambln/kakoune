# Provides integration of the following tools:
# - gocode for code completion (github.com/nsf/gocode)
# - goimports for code formatting on save 
# - gogetdoc for documentation display and source jump (needs jq) (github.com/zmb3/gogetdoc)
# Needs the following tools in the path:
# - jq for json deserializaton

# Auto-completion
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

decl -hidden str go_complete_tmp_dir
decl -hidden completions gocode_completions

def go-complete -docstring "Complete the current selection with gocode" %{
    %sh{
        dir=$(mktemp -d -t kak-go.XXXXXXXX)
        printf %s\\n "set buffer go_complete_tmp_dir ${dir}"
        printf %s\\n "eval -no-hooks write ${dir}/buf"
    }
    %sh{
        dir=${kak_opt_go_complete_tmp_dir}
        (
            gocode_data=$(gocode -f=godit --in=${dir}/buf autocomplete ${kak_cursor_byte_offset})
            rm -r ${dir}
            column_offset=$(echo "${gocode_data}" | head -n1 | cut -d, -f1)

            header="${kak_cursor_line}.$((${kak_cursor_column} - $column_offset))@${kak_timestamp}"
            compl=$(echo "${gocode_data}" | sed 1d | awk -F ",," '{print $2 "||" $1}' | paste -s -d: -)
            printf %s\\n "eval -client '${kak_client}' %{
                set buffer=${kak_bufname} gocode_completions '${header}:${compl}'
            }" | kak -p ${kak_session}
        ) > /dev/null 2>&1 < /dev/null &
    }
}

def go-enable-autocomplete -docstring "Add gocode completion candidates to the completer" %{
    set window completers "option=gocode_completions:%opt{completers}"
    hook window -group go-autocomplete InsertIdle .* %{ try %{
        exec -draft <a-h><a-k>[\w\.].\z<ret>
        go-complete
    } }
    alias window complete go-complete
}

def go-disable-autocomplete -docstring "Disable gocode completion" %{
    set window completers %sh{ printf %s\\n "'${kak_opt_completers}'" | sed 's/option=gocode_completions://g' }
    rmhooks window go-autocomplete
    unalias window complete go-complete
}

# Auto-format
# ‾‾‾‾‾‾‾‾‾‾‾

decl -hidden str go_format_tmp_dir

def -params ..1 go-format \
    -docstring "go-format [goimports]: custom formatter for go files" %{
    %sh{
        dir=$(mktemp -d -t kak-go.XXXXXXXX)
        printf %s\\n "set buffer go_format_tmp_dir ${dir}"
        printf %s\\n "eval -no-hooks write ${dir}/buf"
    }
    %sh{
        dir=${kak_opt_go_format_tmp_dir}
        if [ "$1" = "1" ]; then
            fmt_cmd="goimports -srcdir '${kak_buffile}'"
        else
            fmt_cmd="gofmt -s"
        fi
        eval "${fmt_cmd} -e -w ${dir}/buf 2> ${dir}/stderr"
        if [ $? ]; then
            cp ${dir}/buf "${kak_buffile}"
        else
            # we should report error if linting isn't active
            printf %s\\n "echo -debug '$(cat ${dir}/stderr)'"
        fi
        rm -r ${dir}
    }
    edit!
}

def go-enable-format-onsave -docstring "Enable formatting on save for go files" %{
    hook buffer -group go-format-onsave BufWritePre .+\.go %{ go-format }
}

def go-enable-format-imports-onsave -docstring "Enable formatting (with goimports) on save for go files" %{
    hook buffer -group go-format-onsave BufWritePre .+\.go %{ go-format 1 }
}

def go-disable-format-onsave -docstring "Disable formatting on save for go files" %{
    rmhooks buffer go-format-onsave
}

# Documentation
# ‾‾‾‾‾‾‾‾‾‾‾‾‾

decl -hidden str go_doc_tmp_dir

# FIXME text escaping
def -hidden -params 1..2 _gogetdoc-cmd %{
   %sh{
        dir=$(mktemp -d -t kak-go.XXXXXXXX)
        printf %s\\n "set buffer go_doc_tmp_dir ${dir}"
        printf %s\\n "eval -no-hooks write ${dir}/buf"
    }
    %sh{
        dir=${kak_opt_go_doc_tmp_dir}
        (
            printf %s\\n "${kak_buffile}" > ${dir}/modified
            cat ${dir}/buf | wc -c >> ${dir}/modified
            cat ${dir}/buf >> ${dir}/modified

            if [ "$2" = "1" ]; then
                args="-json"
            fi
            output=$(cat ${dir}/modified                                                    \
		| gogetdoc $args -pos "${kak_buffile}:#${kak_cursor_byte_offset}" -modified \
		| sed 's/%/%%/g')
            rm -r ${dir}
            printf %s "${output}" | grep -v -q "^gogetdoc: "
            status=$?

            case "$1" in
                "info")
                    if [ ${status} -eq 0 ]; then
                        printf %s\\n "eval -client '${kak_client}' %{
                            info -anchor ${kak_cursor_line}.${kak_cursor_column} %@${output}@
                        }" | kak -p ${kak_session}
                    else
                        msg=$(printf %s "${output}" | cut -d' ' -f2-)
                        printf %s\\n "eval -client '${kak_client}' %{
                            echo '${msg}'
                        }" | kak -p ${kak_session}
                    fi
                    ;;
        	"echo")
                    if [ ${status} -eq 0 ]; then
                        signature=$(printf %s "${output}" | sed -n 3p)
                        printf %s\\n "eval -client '${kak_client}' %{
                            echo '${signature}'
                        }" | kak -p ${kak_session}
                    fi
                    ;;
        	"jump")
                    if [ ${status} -eq 0 ]; then
                        pos=$(printf %s "${output}" | jq -r .pos)
                        file=$(printf %s "${pos}" | cut -d: -f1)
                        line=$(printf %s "${pos}" | cut -d: -f2)
                        col=$(printf %s "${pos}" | cut -d: -f3)
                        printf %s\\n "eval -client '${kak_client}' %{
                            eval -try-client '${kak_opt_jumpclient}' edit -existing ${file} ${line} ${col}
                            try %{ focus '${kak_opt_jumpclient}' }                   
                        }" | kak -p ${kak_session}
                    fi
                    ;;
                *)
                        printf %s\\n "eval -client '${kak_client}' %{
                            echo -error %{unkown command '$1'}
                        }" | kak -p ${kak_session}
                    ;;

            esac
        ) > /dev/null 2>&1 < /dev/null &
    }
}

def go-doc-info -docstring "Show the documention of the symbol under the cursor" %{
    _gogetdoc-cmd "info"
}

def go-print-signature -docstring "Print the signature of the symbol under the cursor" %{
    _gogetdoc-cmd "echo"
}

def go-jump -docstring "Jump to the symbol definition" %{
    _gogetdoc-cmd "jump" 1
}

def go-share-selection -docstring "Share the selection using the Go Playground" %{ %sh{
    snippet_id=$(printf %s\\n "${kak_selection}" | curl -s https://play.golang.org/share --data-binary @-)
    printf "echo https://play.golang.org/p/%s" ${snippet_id} 
} }
