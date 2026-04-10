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
# Shell functions (not aliases) so arguments pass through cleanly.
# Usage: copilot / codex (sandboxed yolo by default), or *-vanilla for host.
sbx()              { ~/.local/bin/agent-sandbox.sh "$PWD" "$@"; }
sbx-copilot()      { ~/.local/bin/agent-sandbox.sh "$PWD" copilot "$@"; }
sbx-copilot-yolo() { ~/.local/bin/agent-sandbox.sh "$PWD" copilot --allow-all "$@"; }
sbx-codex()        { ~/.local/bin/agent-sandbox.sh "$PWD" codex "$@"; }
sbx-codex-yolo()   { ~/.local/bin/agent-sandbox.sh "$PWD" codex --full-auto "$@"; }
sbx-nonet()        { NO_NET=1 ~/.local/bin/agent-sandbox.sh "$PWD" "$@"; }
copilot()          { sbx-copilot-yolo "$@"; }
codex()            { sbx-codex-yolo "$@"; }
copilot-vanilla()  { command copilot "$@"; }
codex-vanilla()    { command codex "$@"; }

# --------------------------- Navigation WORK -------------------------
alias sdkdir='cd ~/projects/sdk'
alias sdkui='cd ~/projects/sdkui'
alias docs='cd ~/projects/sdk/docs'
alias vault='cd ~/documents/obsidian-vaults/work-main'
alias vault-priv='cd ~/.sync/share-documentations/main'

