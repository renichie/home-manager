# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
[ -z "$PS1" ] && return

# don't put duplicate lines in the history. See bash(1) for more options
export HISTCONTROL=ignoredups
# ... and ignore same sucessive entries.

# remember (almost) everything
export HISTFILESIZE=5000

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

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
#sources /etc/bash.bashrc).
if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
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


################################### ALIASES ###################################
alias ll='ls -gGh'
alias lr='ls -lash'
alias la='ls -A'
alias l='ls -CF'

alias gdc='git diff --cached'
alias kctx='kubectx'
alias sdkdir='cd ~/projects/sdk'
alias sdkui='cd ~/projects/sdkui'
alias docs='cd ~/projects/sdk/docs'
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

# reload hotkey service
reload-hotkeys() {
    systemctl --user stop xremap.service
    systemctl --user start xremap.service
}

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
