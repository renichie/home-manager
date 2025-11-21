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

# immediate write/read of history
if [[ -n "$PROMPT_COMMAND" ]]; then
    PROMPT_COMMAND="history -a; history -n; $PROMPT_COMMAND"
else
    PROMPT_COMMAND="history -a; history -n"
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
#sources /etc/bash.bashrc).
if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
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
    # Attempt to detect which clipboard tool is available
    if command -v pbcopy &>/dev/null; then
        # macOS
        "$@" | pbcopy
    elif command -v xclip &>/dev/null; then
        # Linux with xclip
        "$@" | xclip -selection c
    elif command -v xsel &>/dev/null; then
        # Linux with xsel
        "$@" | xsel --clipboard --input
    elif command -v clip.exe &>/dev/null; then
        # WSL on Windows
        "$@" | clip.exe
    else
        echo "No supported clipboard tool found. Please install pbcopy, xclip, xsel, or run in an environment with 'clip.exe' available." >&2
        return 1
    fi
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
    # Delete branches whose upstream is gone
    git branch -vv \
        | awk '/: gone]/{print $1}' \
        | grep -vE '^(main|master|develop)$' \
        | xargs -r git branch -D

    # Delete branches that have no upstream
    git for-each-ref --format='%(refname:short) %(upstream)' refs/heads \
        | awk '$2=="" {print $1}' \
        | grep -vE '^(main|master|develop)$' \
        | xargs -r git branch -D
}
