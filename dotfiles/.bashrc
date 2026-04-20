# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# reload hotkey service (xremap)
reload-hotkeys() {
    systemctl --user stop xremap.service
    sleep 1
    systemctl --user start xremap.service
}

# If not running interactively, don't do anything
[ -z "$PS1" ] && return


# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "$debian_chroot" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# Alias definitions.
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable color support of ls and also add handy aliases
if [ "$TERM" != "dumb" ] && [ -x /usr/bin/dircolors ]; then
    eval "`dircolors -b`"
    alias ls='ls --color=auto'
fi

parse_git_branch() {
	git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/'
}

eval "$(oh-my-posh init bash --config=$HOME/.poshthemes/theme.omp.json)"

eval "$(atuin init bash --disable-up-arrow)"
eval "$(atuin gen-completions --shell bash)"

# don't put duplicate lines in the history. See bash(1) for more options
export HISTCONTROL=ignoredups
# ... and ignore same successive entries.

# remember (almost) everything
export HISTFILESIZE=5000

# # immediate write/read of history
# if [[ -n "$PROMPT_COMMAND" ]]; then
#     PROMPT_COMMAND="history -a; history -n; $PROMPT_COMMAND"
# else
#     PROMPT_COMMAND="history -a; history -n"
# fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
#sources /etc/bash.bashrc).
if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
fi

# Reuse git's completion for the `g` alias.
if command -v git &>/dev/null; then
    if type _completion_loader &>/dev/null; then
        _completion_loader git
    fi

    if type __git_complete &>/dev/null && type __git_main &>/dev/null; then
        __git_complete g __git_main
    elif type __git_wrap__git_main &>/dev/null; then
        complete -o bashdefault -o default -o nospace -F __git_wrap__git_main g
    fi
fi

if type _tmux &>/dev/null; then
    complete -F _tmux ta
fi


############################# TMP BASH ADDITIONS ##############################
# Will append everything in bashrc-additions for temporary testing
# Only needed in conjunction with .bashrc being managed by nix homemanager
if [ -f ~/.bashrc-additions ]; then
    source ~/.bashrc-additions
fi

############################# OLDSCHOOL PROMPT ################################
# Not used if ohmyposh is installed (TODO: activate conditionally)
#PS1='\[\e[33m\]\u' #username
#PS1=$PS1'\[\e[m\]:\[\e[1;34m\]\h' #':host'
#PS1=$PS1'\[\e[m\]:\[\e[1;34m\][\w]' # path
#PS1=$PS1'\[\e[1;30m\]$(parse_git_branch)' #git branch
#PS1=$PS1'\[\e[m\]> ' #prompt


################################### DEFAULT ALIASES ###################################
alias ll='ls -gGh'
alias lr='ls -lash'
alias la='ls -A'
alias l='ls -CF'

alias hswitch='home-manager switch --flake ~/.config/home-manager#dpc0155 -b bckp'

####################################### KUBECTL #########################################

# Check if kubectl is available
if command -v kubectl &> /dev/null; then
    # Source kubectl completion
    source <(kubectl completion bash)

    # Check if kubecolor is available
    if command -v kubecolor &> /dev/null; then
        # Use kubecolor for the alias
        alias k='kubecolor'
    else
        # Fallback to kubectl
        alias k='kubectl'
    fi

    # Bind kubectl completion to the alias
    complete -o default -F __start_kubectl k
fi


####################################### TFSWITCH  #########################################
export PATH="$HOME/.terraform.versions:$PATH"



####################################### ADDITIONAL CMDS ###################################
# copies the output of the command at $1 to the clipboard
clipc() {
    if [ "$#" -eq 0 ]; then
        echo "Usage: clipc <command> [args...]" >&2
        return 1
    fi

    local -a clipboard_cmd

    # Attempt to detect which clipboard tool is available
    if command -v pbcopy &>/dev/null; then
        # macOS
        clipboard_cmd=(pbcopy)
    elif command -v xclip &>/dev/null; then
        # Linux with xclip
        clipboard_cmd=(xclip -selection c)
    elif command -v xsel &>/dev/null; then
        # Linux with xsel
        clipboard_cmd=(xsel --clipboard --input)
    elif command -v clip.exe &>/dev/null; then
        # WSL on Windows
        clipboard_cmd=(clip.exe)
    else
        echo "No supported clipboard tool found. Please install pbcopy, xclip, xsel, or run in an environment with 'clip.exe' available." >&2
        return 1
    fi

    local quoted_cmd
    printf -v quoted_cmd '%q ' "$@"
    eval "$quoted_cmd" | "${clipboard_cmd[@]}"
}
alias clipcat='clipc cat'


# execute home-manager switch command.
# depending on the machine hostname a different flake will be built.
hm_switch() {
  local host
  host=$(hostname)
  local flake

  case "$host" in
    DPC0155)
      flake="DPC0155"
      ;;
    nyx)
      flake="NYX"
      ;;
    hera)
      flake="HERA"
      ;;
    *)
      echo "Hostname '$host' not recognized. Please update the hm_switch function."
      return 1
      ;;
  esac

  home-manager switch --flake ~/.config/home-manager#$flake -b bckp
}


# ---------------------------- Utility -----------------------------
# Generate a quick 32-char random-ish password (non-cryptographic)
# Example: generate_password
# Note: For stronger passwords, consider `openssl rand -base64 32` if available.
generate_password() { date +%s | sha256sum | base64 | head -c 32 ; echo; }

git-prune-local-branches () {
    local confirmation_mode="all"
    local filter_mode="all"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-confirmation)
                confirmation_mode="none"
                ;;
            --single)
                confirmation_mode="single"
                ;;
            --local)
                if [[ "$filter_mode" == "remote" ]]; then
                    printf 'Options --local and --remote cannot be used together.\n' >&2
                    return 1
                fi
                filter_mode="local"
                ;;
            --remote)
                if [[ "$filter_mode" == "local" ]]; then
                    printf 'Options --local and --remote cannot be used together.\n' >&2
                    return 1
                fi
                filter_mode="remote"
                ;;
            -h|--help)
                cat <<'EOF'
Usage: git-prune-local-branches [--no-confirmation | --single] [--local | --remote]

  --no-confirmation  Delete matching branches without asking for confirmation.
  --single           Ask for confirmation for each branch individually.
  --local            Only include local branches without any upstream configured.
  --remote           Only include local branches whose upstream is gone.
EOF
                return 0
                ;;
            *)
                printf 'Unknown option: %s\n' "$1" >&2
                return 1
                ;;
        esac
        shift
    done

    local use_color=0
    if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
        use_color=1
    fi

    local reset="" red="" green="" yellow="" blue="" bold=""
    if [[ $use_color -eq 1 ]]; then
        reset="$(tput sgr0)"
        red="$(tput setaf 1)"
        green="$(tput setaf 2)"
        yellow="$(tput setaf 3)"
        blue="$(tput setaf 4)"
        bold="$(tput bold)"
    fi

    local current_branch
    current_branch="$(git branch --show-current 2>/dev/null)"

    local candidates=()
    local line branch sha rest upstream track age author subject
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^\*?[[:space:]]*([^[:space:]]+)[[:space:]]+([0-9a-f]+)[[:space:]]+(.*)$ ]]; then
            branch="${BASH_REMATCH[1]}"
            sha="${BASH_REMATCH[2]}"
            rest="${BASH_REMATCH[3]}"
        else
            continue
        fi

        if [[ "$branch" == "main" || "$branch" == "master" || "$branch" == "develop" || "$branch" == "$current_branch" ]]; then
            continue
        fi

        upstream=""
        track=""
        if [[ "$rest" =~ ^\[([^]]+)\][[:space:]]*(.*)$ ]]; then
            local upstream_info
            upstream_info="${BASH_REMATCH[1]}"

            if [[ "$upstream_info" == *": gone" ]]; then
                upstream="${upstream_info%: gone}"
                track="[gone]"
            else
                upstream="${upstream_info%%:*}"
                [[ "$upstream" == "$upstream_info" ]] && upstream="$upstream_info"
                track="[tracked]"
            fi
        fi

        case "$filter_mode" in
            all)
                if [[ "$track" != "[gone]" && -n "$upstream" ]]; then
                    continue
                fi
                ;;
            local)
                if [[ -n "$upstream" ]]; then
                    continue
                fi
                ;;
            remote)
                if [[ "$track" != "[gone]" ]]; then
                    continue
                fi
                ;;
        esac

        age="$(git log -1 --format='%cr' "$branch" 2>/dev/null)"
        author="$(git log -1 --format='%an' "$branch" 2>/dev/null)"
        subject="$(git log -1 --format='%s' "$branch" 2>/dev/null)"
        candidates+=("${branch}|${upstream}|${track}|${age}|${author}|${subject}")
    done < <(git branch -vv --no-color)

    if [[ ${#candidates[@]} -eq 0 ]]; then
        case "$filter_mode" in
            all)
                printf '%sNo local branches with gone or missing upstreams found.%s\n' "$green" "$reset"
                ;;
            local)
                printf '%sNo local branches without upstreams found.%s\n' "$green" "$reset"
                ;;
            remote)
                printf '%sNo local branches with gone upstreams found.%s\n' "$green" "$reset"
                ;;
        esac
        return 0
    fi

    printf '%sBranches selected for deletion (%d):%s\n' "$bold" "${#candidates[@]}" "$reset"
    local preview_entry preview_branch preview_upstream preview_track
    for preview_entry in "${candidates[@]}"; do
        IFS='|' read -r preview_branch preview_upstream preview_track _ <<< "$preview_entry"

        if [[ "$preview_track" == "[gone]" ]]; then
            printf '  %s- %s%s%s %s[gone]%s\n' "$red" "$blue" "$preview_branch" "$reset" "$red" "$reset"
        else
            printf '  %s- %s%s%s %s[no upstream]%s\n' "$yellow" "$blue" "$preview_branch" "$reset" "$yellow" "$reset"
        fi
    done

    local answer
    if [[ "$confirmation_mode" == "all" ]]; then
        printf '%sDelete all listed branches? [y/N]: %s' "$yellow" "$reset"
        read -r answer

        case "$answer" in
            y|Y|yes|YES)
                ;;
            *)
                printf '%sAborted.%s\n' "$blue" "$reset"
                return 0
                ;;
        esac
    fi

    local status
    for entry in "${candidates[@]}"; do
        IFS='|' read -r branch upstream track age author subject <<< "$entry"

        if [[ "$track" == "[gone]" ]]; then
            status="${red}[gone]${reset}"
        elif [[ -z "$upstream" ]]; then
            status="${yellow}[no upstream]${reset}"
        else
            status="${blue}${upstream}${reset}"
        fi

        printf '\n%sBranch:%s %s%s%s\n' "$bold" "$reset" "$blue" "$branch" "$reset"
        if [[ -n "$upstream" ]]; then
            printf '  Upstream: %s (%s)\n' "$upstream" "$status"
        else
            printf '  Upstream: %s\n' "$status"
        fi
        printf '  Last commit: %s\n' "$age"
        printf '  Author: %s\n' "$author"
        printf '  Subject: %s\n' "$subject"

        if [[ "$confirmation_mode" == "single" ]]; then
            printf '%sDelete this branch? [y/N]: %s' "$yellow" "$reset"
            read -r answer

            case "$answer" in
                y|Y|yes|YES)
                    ;;
                *)
                    printf '%sKept:%s %s\n' "$blue" "$reset" "$branch"
                    continue
                    ;;
            esac
        fi

        if git branch -D "$branch"; then
            printf '%sDeleted:%s %s\n' "$green" "$reset" "$branch"
        else
            printf '%sFailed to delete:%s %s\n' "$red" "$reset" "$branch"
        fi
    done
}

_git_prune_local_branches_completion() {
    local cur
    cur="${COMP_WORDS[COMP_CWORD]}"

    local options=(
        --no-confirmation
        --single
        --local
        --remote
        --help
    )

    local used word filtered=()
    for word in "${options[@]}"; do
        used=0
        for ((i = 1; i < COMP_CWORD; i++)); do
            if [[ "${COMP_WORDS[i]}" == "$word" ]]; then
                used=1
                break
            fi
        done

        if [[ $used -eq 0 ]]; then
            filtered+=("$word")
        fi
    done

    COMPREPLY=( $(compgen -W "${filtered[*]}" -- "$cur") )
}

complete -F _git_prune_local_branches_completion git-prune-local-branches
