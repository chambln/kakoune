define-command \
-params 1.. \
-shell-completion \
-docstring '
    fifo [<switches>] [<arguments>]: execute <arguments> with sh(1)
    asynchronously and follow its output in a fifo buffer
    Switches:
        -name <arg>  name for the fifo buffer
        -readonly    make the buffer readonly once the fifo closes
        -scroll      place the initial cursor so that the fifo will
                     scroll to show new data' \
fifo %{
    evaluate-commands %sh{
        die() {
            printf 'fail async: %s\n' "$@"
            exit 1
        }
        name="*$1*"
        edit='edit!'
        while true; do
            case "$1" in
            -name)
                name="$2"
                shift 2
                ;;
            -readonly)
                readonly='true'
                shift
                ;;
            -scroll)
                edit="$edit $1"
                shift
                ;;
            --)
                shift
                break
                ;;
            -*)
                die "no such option ‘$1’"
                ;;
            *)
                break
                ;;
            esac
        done
        output="$(mktemp -d "${TMPDIR:-/tmp}/kak-async-$1.XXXXXXXX")/fifo"
        mkfifo "$output"
        ( "$@" > "$output" 2>&1 & ) > /dev/null 2>&1 < /dev/null
        printf '%s\n' "
            evaluate-commands -try-client '$kak_opt_toolsclient' %{
                $edit -fifo '$output' '$name'
                hook -always -once buffer BufCloseFifo .* %{
                    set-option buffer readonly ${readonly:-false}
                    evaluate-commands %sh{ rm -r "$(dirname "$output")" }
                }
           }"
    }
}
