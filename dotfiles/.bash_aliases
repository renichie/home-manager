# ----------------------------- Misc ---------------------------------
alias grep='grep --color=always'
alias hgrep='history | grep'
alias hg='history | grep'
alias hs='history'
alias reload='source ~/.bashrc'
alias loc=tokei
alias kctx='kubectx'
alias open=xdg-open

# ------------------------------ Git ---------------------------------
alias g='git'
alias got='git'
alias gut='git'
alias gst='git status'
alias ga='git add'
alias gca='git commit --amend'
alias gcane='git commit --amend --no-edit'
alias gfa='git fetch --all'
alias glg='git lg1 --all'
alias gdc='git diff --cached'
# gitall() -> siehe .bash_functions

# ------------------------------ Tmux --------------------------------
alias ta='tmux attach-session -t'
alias tshared='tmux -S /var/tmux/socket attach'
alias tls='tmux ls'

# --------------------------- Navigation ------------------------------
alias cd..='cd ..'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ......='cd ../../../../..'

# ------------------------- AI Agent Sandbox --------------------------
# sbx*, *-sandboxed, copilot() -> siehe .bash_functions

# --------------------------- Navigation WORK -------------------------
alias sdkdir='cd ~/projects/sdk'
alias sdkui='cd ~/projects/sdk-core/sdkui'
alias docs='cd ~/projects/sdk/sdk-docs'
alias vault='cd ~/documents/obsidian-vaults/work-main'
alias vault-priv='cd ~/.sync/share-documentations/main'
