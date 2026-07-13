#!/bin/bash

ASK_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ask"
ASK_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ask"
ASK_CONFIG_FILE="$ASK_CONFIG_DIR/config.json"
ASK_MEMORY_DIR="$ASK_CONFIG_DIR/memories"
ASK_MAX_CONTEXTS=5

ask_init() {
    mkdir -p "$ASK_CONFIG_DIR" "$ASK_CACHE_DIR" "$ASK_MEMORY_DIR"
    if [[ ! -f "$ASK_CONFIG_FILE" ]]; then
        echo '{"default_agent":"claude","current_context":1,"enabled_memories":[],"local_server":{"url":"http://127.0.0.1:8080","model":"unsloth/gemma-4-E2B-it-GGUF:Q4_K_M","n_predict":1024},"local_cli":{"bin":"/home/emkai/src/llama.cpp/build/bin/llama-completion","model":"unsloth/gemma-4-E2B-it-GGUF","n_predict":1024}}' > "$ASK_CONFIG_FILE"
    else
        local tmp
        tmp="$(mktemp)"
        jq '.enabled_memories //= []
            | .local_server //= {"url":"http://127.0.0.1:8080","model":"unsloth/gemma-4-E2B-it-GGUF:Q4_K_M","n_predict":1024}
            | .local_server.model //= "unsloth/gemma-4-E2B-it-GGUF:Q4_K_M"
            | .local_cli //= {"bin":"/home/emkai/src/llama.cpp/build/bin/llama-completion","model":"unsloth/gemma-4-E2B-it-GGUF","n_predict":1024}' \
            "$ASK_CONFIG_FILE" > "$tmp"
        mv "$tmp" "$ASK_CONFIG_FILE"
    fi
}

ask_default_agent() {
    jq -r '.default_agent' "$ASK_CONFIG_FILE"
}

ask_set_default_agent() {
    local agent="$1" tmp
    tmp="$(mktemp)"
    jq --arg a "$agent" '.default_agent = $a' "$ASK_CONFIG_FILE" > "$tmp"
    mv "$tmp" "$ASK_CONFIG_FILE"
}

ask_current_context() {
    local n
    n=$(jq -r '.current_context' "$ASK_CONFIG_FILE")
    if ! [[ "$n" =~ ^[0-9]+$ ]] || (( n < 1 || n > ASK_MAX_CONTEXTS )); then
        n=1
    fi
    echo "$n"
}

ask_context_file() {
    echo "$ASK_CACHE_DIR/context${1}.txt"
}

ask_set_current_context() {
    local n="$1" tmp
    tmp="$(mktemp)"
    jq --argjson c "$n" '.current_context = $c' "$ASK_CONFIG_FILE" > "$tmp"
    mv "$tmp" "$ASK_CONFIG_FILE"
}

# Roll to the next context slot, truncate it, persist to config.
# Echoes the new context number.
ask_roll_context() {
    local current next
    current=$(ask_current_context)
    next=$(( current % ASK_MAX_CONTEXTS + 1 ))
    ask_set_current_context "$next"
    : > "$(ask_context_file "$next")"
    echo "$next"
}

ask_read_context() {
    local file
    file="$(ask_context_file "$1")"
    if [[ -s "$file" ]]; then
        cat "$file"
    fi
}

ask_append_context() {
    local n="$1" question="$2" answer="$3"
    printf 'Question:\n%s\nAnswer:\n%s\n\n' "$question" "$answer" >> "$(ask_context_file "$n")"
}

ask_last_answer() {
    local n file offset="${1:-0}"
    n=$(ask_current_context)
    file="$(ask_context_file "$n")"
    [[ ! -s "$file" ]] && return 0
    awk -v offset="$offset" '
        /^Answer:$/  { capturing=1; idx++; bufs[idx]=""; first=1; next }
        /^Question:$/ { capturing=0 }
        capturing {
            if (first) { bufs[idx] = $0; first = 0 }
            else       { bufs[idx] = bufs[idx] "\n" $0 }
        }
        END {
            target = idx - offset
            if (target < 1) exit 0
            s = bufs[target]
            sub(/\n+$/, "", s)
            if (s != "") print s
        }
    ' "$file"
}

ask_list_contexts() {
    local current n file first marker
    current=$(ask_current_context)
    for (( n=1; n<=ASK_MAX_CONTEXTS; n++ )); do
        file="$(ask_context_file "$n")"
        marker="  "
        (( n == current )) && marker="* "
        if [[ ! -s "$file" ]]; then
            printf '%s%d: (empty)\n' "$marker" "$n"
            continue
        fi
        first=$(awk '/^Question:$/{getline; print; exit}' "$file")
        printf '%s%d: %s\n' "$marker" "$n" "$first"
    done
}

ask_valid_agent() {
    case "$1" in
        claude|gemini|codex|local-server|local-cli) return 0 ;;
        *) return 1 ;;
    esac
}

ask_memory_valid_name() {
    local name="$1"
    if [[ -z "$name" ]] || ! [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "ask: invalid memory name '$name' (expected [a-zA-Z0-9_-]+)" >&2
        return 2
    fi
}

ask_memory_file() {
    echo "$ASK_MEMORY_DIR/$1.md"
}

ask_memory_all() {
    local f
    shopt -s nullglob
    for f in "$ASK_MEMORY_DIR"/*.md; do
        basename "$f" .md
    done
    shopt -u nullglob
}

ask_memory_enabled() {
    local name
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        [[ -f "$(ask_memory_file "$name")" ]] && echo "$name"
    done < <(jq -r '.enabled_memories[]?' "$ASK_CONFIG_FILE")
}

ask_memory_enable() {
    local name="$1" tmp
    tmp="$(mktemp)"
    jq --arg n "$name" \
        '.enabled_memories = ((.enabled_memories // []) | map(select(. != $n)) + [$n])' \
        "$ASK_CONFIG_FILE" > "$tmp"
    mv "$tmp" "$ASK_CONFIG_FILE"
}

ask_memory_disable() {
    local name="$1" tmp
    tmp="$(mktemp)"
    jq --arg n "$name" \
        '.enabled_memories = ((.enabled_memories // []) | map(select(. != $n)))' \
        "$ASK_CONFIG_FILE" > "$tmp"
    mv "$tmp" "$ASK_CONFIG_FILE"
}

ask_memory_concat() {
    local first=1 name content
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        if (( first )); then
            first=0
        else
            printf '\n\n'
        fi
        content="$(cat "$(ask_memory_file "$name")")"
        printf '%s' "$content"
    done < <(ask_memory_enabled)
}

ask_memory_cmd_list() {
    local names=() enabled=() name n marker preview
    while IFS= read -r n; do
        [[ -n "$n" ]] && names+=("$n")
    done < <(ask_memory_all)
    while IFS= read -r n; do
        [[ -n "$n" ]] && enabled+=("$n")
    done < <(ask_memory_enabled)

    if (( ${#names[@]} == 0 )); then
        echo "(no memories — create one with 'ask -m edit <name>')"
        return 0
    fi

    for name in "${names[@]}"; do
        marker="[off]"
        for n in "${enabled[@]}"; do
            [[ "$n" == "$name" ]] && { marker="[on] "; break; }
        done
        preview=$(awk 'NF { sub(/\r$/, ""); print; exit }' "$(ask_memory_file "$name")")
        printf '%s %s: %s\n' "$marker" "$name" "$preview"
    done
}

ask_memory_cmd_edit() {
    local name="${1-}" file
    ask_memory_valid_name "$name" || return $?
    file="$(ask_memory_file "$name")"
    [[ -f "$file" ]] || : > "$file"
    "${EDITOR:-nvim}" "$file"
}

ask_memory_cmd_rm() {
    local name="${1-}" file reply
    ask_memory_valid_name "$name" || return $?
    file="$(ask_memory_file "$name")"
    [[ -f "$file" ]] || { echo "ask: no such memory '$name'" >&2; return 2; }
    read -rp "Delete memory '$name'? [y/N] " reply
    if [[ ! "$reply" =~ ^[yY]$ ]]; then
        echo "aborted"
        return 0
    fi
    rm -f "$file"
    ask_memory_disable "$name"
    echo "removed '$name'"
}

ask_memory_cmd_on() {
    local name="${1-}"
    ask_memory_valid_name "$name" || return $?
    [[ -f "$(ask_memory_file "$name")" ]] || {
        echo "ask: no such memory '$name' (use 'ask -m edit $name' to create)" >&2
        return 2
    }
    ask_memory_enable "$name"
    echo "enabled '$name'"
}

ask_memory_cmd_off() {
    local name="${1-}"
    ask_memory_valid_name "$name" || return $?
    ask_memory_disable "$name"
    echo "disabled '$name'"
}

ask_memory_cmd_show() {
    local name="${1-}" file out
    if [[ -z "$name" ]]; then
        out="$(ask_memory_concat)"
        [[ -n "$out" ]] && printf '%s\n' "$out"
        return 0
    fi
    ask_memory_valid_name "$name" || return $?
    file="$(ask_memory_file "$name")"
    [[ -f "$file" ]] || { echo "ask: no such memory '$name'" >&2; return 2; }
    cat "$file"
}

ask_memory_main() {
    local verb="${1:-list}"
    (( $# > 0 )) && shift
    case "$verb" in
        list) ask_memory_cmd_list "$@" ;;
        edit) ask_memory_cmd_edit "$@" ;;
        rm)   ask_memory_cmd_rm   "$@" ;;
        on)   ask_memory_cmd_on   "$@" ;;
        off)  ask_memory_cmd_off  "$@" ;;
        show) ask_memory_cmd_show "$@" ;;
        *)    echo "ask: unknown memory verb '$verb' (expected list|edit|rm|on|off|show)" >&2
              return 2 ;;
    esac
}

ask_invoke_agent() {
    local agent="$1" prompt="$2" show_thought="${3:-0}"
    case "$agent" in
        claude)
            if (( show_thought == 1 )); then
                local resp thinking text
                resp=$(claude -p --effort high --output-format stream-json --verbose "$prompt")
                thinking=$(printf '%s\n' "$resp" | jq -rs \
                    '[.[] | select(.type=="assistant") | .message.content[]? | select(.type=="thinking") | .thinking] | map(select(. != "")) | join("\n\n")')
                text=$(printf '%s\n' "$resp" | jq -rs \
                    '[.[] | select(.type=="result") | .result] | join("")')
                if [[ -n "$thinking" ]]; then
                    printf '<|channel>%s<channel|>%s\n' "$thinking" "$text"
                else
                    printf '%s\n' "$text"
                fi
            else
                claude -p "$prompt"
            fi
            ;;
        gemini) gemini -p "$prompt" ;;
        codex) codex exec --skip-git-repo-check --json "$prompt" \
           | jq -r 'select(.type=="item.completed" and .item.type=="agent_message") | .item.text' ;;
        local-server)
            local url model n_predict resp content reasoning
            url=$(jq -r '.local_server.url' "$ASK_CONFIG_FILE")
            model=$(jq -r '.local_server.model // ""' "$ASK_CONFIG_FILE")
            n_predict=$(jq -r '.local_server.n_predict' "$ASK_CONFIG_FILE")
            if [[ -z "$model" ]]; then
                echo "ask: local_server.model not set in $ASK_CONFIG_FILE" >&2
                return 2
            fi
            resp=$(curl -fsS -X POST "$url/v1/chat/completions" \
                -H 'Content-Type: application/json' \
                -d "$(jq -n --arg p "$prompt" --arg m "$model" --argjson n "$n_predict" \
                    '{model:$m, max_tokens:$n, stop:["\nQuestion:"], messages:[{role:"user",content:$p}]}')")
            content=$(printf '%s' "$resp" | jq -r '.choices[0].message.content // ""')
            reasoning=$(printf '%s' "$resp" | jq -r '.choices[0].message.reasoning_content // ""')
            if [[ -n "$reasoning" ]]; then
                printf '<|channel>%s<channel|>%s\n' "$reasoning" "$content"
            else
                printf '%s\n' "$content"
            fi
            ;;
        local-cli)
            local bin model n_predict flag
            bin=$(jq -r '.local_cli.bin' "$ASK_CONFIG_FILE")
            model=$(jq -r '.local_cli.model' "$ASK_CONFIG_FILE")
            n_predict=$(jq -r '.local_cli.n_predict' "$ASK_CONFIG_FILE")
            if [[ -z "$model" ]]; then
                echo "ask: local_cli.model not set in $ASK_CONFIG_FILE" >&2
                return 2
            fi
            # Absolute path → local GGUF (-m); org/repo → HuggingFace (-hf).
            if [[ "$model" == /* ]]; then
                flag="-m"
            elif [[ "$model" == */* ]]; then
                flag="-hf"
            else
                flag="-m"
            fi
            "$bin" "$flag" "$model" -p "$prompt" -n "$n_predict" \
                   --single-turn --no-display-prompt --jinja 2>/dev/null \
              | sed 's/ \[end of text\]//g'
            ;;
        *) echo "ask: unknown agent '$agent'" >&2; return 2 ;;
    esac
}

# Strip reasoning channel blocks (e.g. Gemma's <|channel>thought ... <channel|>)
# from stdin; everything else passes through unchanged.
ask_strip_reasoning() {
    awk '
        /<\|channel>/ { in_thought=1 }
        in_thought {
            if (match($0, /<channel\|>/)) {
                print substr($0, RSTART + RLENGTH)
                in_thought=0
            }
            next
        }
        { print }
    '
}

# Replace channel markers with ANSI dim/reset so reasoning prints in grey.
# Disables color when stdout isn't a TTY (e.g. piped or redirected).
ask_color_reasoning() {
    local dim="" reset_seq
    if [[ -t 1 ]]; then
        dim=$'\033[2m'
        reset_seq=$'\033[0m\n\n'
    else
        reset_seq=$'\n\n'
    fi
    awk -v dim="$dim" -v reset="$reset_seq" '
        {
            gsub(/<\|channel>/, dim)
            gsub(/<channel\|>/, reset)
            print
        }
    '
}

# ask_run <agent> <new_context: 0|1> <skip_memory: 0|1> <show_thought: 0|1> <question>
# Prints the answer to stdout; appends Q/A to the active context file.
ask_run() {
    local agent="$1" new_context="$2" skip_memory="$3" show_thought="$4" question="$5"
    local ctx prompt existing memory="" answer saved

    if (( new_context == 1 )); then
        ctx=$(ask_roll_context)
    else
        ctx=$(ask_current_context)
        touch "$(ask_context_file "$ctx")"
    fi

    existing="$(ask_read_context "$ctx")"
    if (( skip_memory == 0 )); then
        memory="$(ask_memory_concat)"
    fi
    prompt=""
    if [[ -n "$memory" ]]; then
        prompt+="$memory"$'\n\n'
    fi
    if [[ -n "$existing" ]]; then
        prompt+="$existing"$'\n'
    fi
    prompt+="Question:"$'\n'"$question"$'\n'"Answer:"$'\n'

    answer="$(ask_invoke_agent "$agent" "$prompt" "$show_thought")"
    saved="$(printf '%s\n' "$answer" | ask_strip_reasoning)"
    if (( show_thought == 1 )); then
        printf '%s\n' "$answer" | ask_color_reasoning
    else
        printf '%s\n' "$saved"
    fi
    ask_append_context "$ctx" "$question" "$saved"
}

ask_usage() {
    cat <<EOF
Usage: ask [-a AGENT] [-A AGENT] [-n] [-c N] [-l] [-r] [-t] [-M] [-h] <question...>
       ... | ask [options]      (question read from stdin when no args given)
       ask -m [VERB] [args]     (manage memories; see Memory below)

  -a AGENT   Use AGENT for this call (claude|gemini|codex|local-server|local-cli)
  -A AGENT   Set AGENT as the default (persisted) and use it for this call
  -n         Start a new context (rolls through 1..$ASK_MAX_CONTEXTS)
  -c N       Switch to context N (1..$ASK_MAX_CONTEXTS) and use it for this call
  -l         List all contexts with their first question ('*' marks current)
  -r [N]     Print the Nth-previous answer from the current context
             (0 or omitted = latest, 1 = answer before latest, ...)
  -t         Show the model's reasoning channel in the output (off by default)
  -m         Enter memory-management mode (see Memory below)
  -M         Bypass memories for this call only (does not change enabled_memories)
  -h         Show this help

Memory:
  -m                   List memories with on/off state
  -m list              Alias for bare -m
  -m edit <name>       Create (if missing) and edit memory in \${EDITOR:-nvim}
  -m rm <name>         Delete memory (prompts for confirmation)
  -m on <name>         Enable memory (prepended to every prompt)
  -m off <name>        Disable memory
  -m show [<name>]     Print one memory, or all enabled concatenated

Local LLM (llama.cpp):
  local-server   POST to a running llama-server /completion
                 Config keys: .local_server.url, .local_server.model,
                              .local_server.n_predict
                 .model must match a server-side alias (see GET /v1/models)
  local-cli      Spawn llama-completion per call
                 Config keys: .local_cli.bin, .local_cli.model, .local_cli.n_predict
                 .model accepts absolute paths (-> -m) or HF repos like
                 'unsloth/gemma-4-E2B-it-GGUF' (-> -hf)

Config:   $ASK_CONFIG_FILE
Context:  $ASK_CACHE_DIR/context{1..$ASK_MAX_CONTEXTS}.txt
Memories: $ASK_MEMORY_DIR/<name>.md
EOF
}

# ask_main "$@" — full CLI entrypoint: parse args, validate, run.
ask_main() {
    ask_init

    local agent="" set_default=0 new_context=0 pick_context="" memory_mode=0 skip_memory=0 show_thought=0 opt
    local OPTIND=1

    while getopts ":a:A:c:nlrthmM" opt; do
        case "$opt" in
            a) agent="$OPTARG" ;;
            A) agent="$OPTARG"; set_default=1 ;;
            c) pick_context="$OPTARG" ;;
            n) new_context=1 ;;
            l) ask_list_contexts; return 0 ;;
            r)
                local r_off=0 r_next
                eval "r_next=\${$OPTIND-}"
                if [[ "$r_next" =~ ^[0-9]+$ ]]; then
                    r_off=$r_next
                    OPTIND=$((OPTIND + 1))
                fi
                ask_last_answer "$r_off"
                return 0 ;;
            t) show_thought=1 ;;
            m) memory_mode=1 ;;
            M) skip_memory=1 ;;
            h) ask_usage; return 0 ;;
            \?) echo "ask: unknown option -$OPTARG" >&2; ask_usage >&2; return 2 ;;
            :)  echo "ask: option -$OPTARG requires an argument" >&2; return 2 ;;
        esac
    done
    shift $((OPTIND - 1))

    if (( memory_mode == 1 )); then
        ask_memory_main "$@"
        return $?
    fi

    [[ -z "$agent" ]] && agent="$(ask_default_agent)"

    if ! ask_valid_agent "$agent"; then
        echo "ask: unknown agent '$agent' (expected claude|gemini|codex|local-server|local-cli)" >&2
        return 2
    fi

    if [[ -n "$pick_context" ]]; then
        if (( new_context == 1 )); then
            echo "ask: -c and -n are mutually exclusive" >&2
            return 2
        fi
        if ! [[ "$pick_context" =~ ^[0-9]+$ ]] || (( pick_context < 1 || pick_context > ASK_MAX_CONTEXTS )); then
            echo "ask: -c requires 1..$ASK_MAX_CONTEXTS (got '$pick_context')" >&2
            return 2
        fi
        ask_set_current_context "$pick_context"
    fi

    if (( set_default == 1 )); then
        ask_set_default_agent "$agent"
    fi

    local question=""
    if (( $# > 0 )); then
        question="$*"
    elif [[ ! -t 0 ]]; then
        question="$(cat)"
        question="${question%$'\n'}"
    fi

    if [[ -z "$question" || "$question" =~ ^[[:space:]]+$ ]]; then
        if (( set_default == 1 )); then
            echo "ask: default agent set to '$agent'"
        fi
        if [[ -n "$pick_context" ]]; then
            echo "ask: switched to context $pick_context"
            return 0
        fi
        if (( set_default == 1 )); then
            return 0
        fi
        echo "ask: no question given" >&2
        ask_usage >&2
        return 2
    fi

    ask_run "$agent" "$new_context" "$skip_memory" "$show_thought" "$question"
}
