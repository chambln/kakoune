declare-option -docstring "name of the client in which documentation is to be displayed" \
    str docsclient

hook -group git-log-highlight global WinSetOption filetype=git-log %{
    add-highlighter window/git-log group
    add-highlighter window/git-log/ regex '^([*|\\ /_.-])*' 0:keyword
    add-highlighter window/git-log/ regex '^( ?[*|\\ /_.-])*\h{,3}(commit )?(\b[0-9a-f]{4,40}\b)' 2:keyword 3:comment
    add-highlighter window/git-log/ regex '^( ?[*|\\ /_.-])*\h{,3}([a-zA-Z_-]+:) (.*?)$' 2:variable 3:value
    add-highlighter window/git-log/ ref diff # highlight potential diffs from the -p option

    hook -once -always window WinSetOption filetype=.* %{ remove-highlighter window/git-log }
}

hook -group git-status-highlight global WinSetOption filetype=git-status %{
    add-highlighter window/git-status group
    add-highlighter window/git-status/ regex '^## ' 0:comment
    add-highlighter window/git-status/ regex '^## (\S*[^\s\.@])' 1:green
    add-highlighter window/git-status/ regex '^## (\S*[^\s\.@])(\.\.+)(\S*[^\s\.@])' 1:green 2:comment 3:red
    add-highlighter window/git-status/ regex '^(##) (No commits yet on) (\S*[^\s\.@])' 1:comment 2:Default 3:green
    add-highlighter window/git-status/ regex '^## \S+ \[[^\n]*ahead (\d+)[^\n]*\]' 1:green
    add-highlighter window/git-status/ regex '^## \S+ \[[^\n]*behind (\d+)[^\n]*\]' 1:red
    add-highlighter window/git-status/ regex '^(?:([Aa])|([Cc])|([Dd!?])|([MUmu])|([Rr])|([Tt]))[ !\?ACDMRTUacdmrtu]\h' 1:green 2:blue 3:red 4:yellow 5:cyan 6:cyan
    add-highlighter window/git-status/ regex '^[ !\?ACDMRTUacdmrtu](?:([Aa])|([Cc])|([Dd!?])|([MUmu])|([Rr])|([Tt]))\h' 1:green 2:blue 3:red 4:yellow 5:cyan 6:cyan
    add-highlighter window/git-status/ regex '^R[ !\?ACDMRTUacdmrtu] [^\n]+( -> )' 1:cyan
    add-highlighter window/git-status/ regex '^\h+(?:((?:both )?modified:)|(added:|new file:)|(deleted(?: by \w+)?:)|(renamed:)|(copied:))(?:.*?)$' 1:yellow 2:green 3:red 4:cyan 5:blue 6:magenta

    hook -once -always window WinSetOption filetype=.* %{ remove-highlighter window/git-status }
}

define-command \
-params .. \
-docstring '
    git [<arguments>]: git utility wrapper
    All the optional arguments are forwarded to the git utility' \
git %{
    evaluate-commands %sh{
        commit() {
            GIT_EDITOR='' EDITOR='' VISUAL='' git commit "$@" > /dev/null 2>&1
            msgfile="$(git rev-parse --git-dir)/COMMIT_EDITMSG"
            printf %s "
                edit '$msgfile'
                hook buffer BufWritePost '.*\Q$msgfile\E' %{
                    evaluate-commands %sh{
                        if git commit -F '$msgfile' --cleanup=strip $* > /dev/null; then
                            printf %s '
                                evaluate-commands -client '$kak_client' %{
                                    echo -markup %{{Information}commit succeeded}
                                }
                                delete-buffer
                            '
                        else
                            printf '
                                evaluate-commands -client %s 'fail commit failed!!!'
                            ' "$kak_client"
                        fi
                    }
                }
            "
        }

        fifo() {
            printf %s "
                evaluate-commands -try-client '$1' %{
                    fifo -name \"*git %arg{1}*\" git %arg{@}
                    set-option buffer filetype '$2'
                }
            "
        }

        case $1 in
            commit) "$@" ;;
            status) fifo jump git-status ;;
            log)    fifo jump git-log ;;
            show)   fifo docs git-log ;;
            *)      fifo docs diff ;;
        esac
    }
}
