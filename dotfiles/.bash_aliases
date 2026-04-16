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
gitall() {
  case "${1:-}" in
    -h|--help|"")
      cat <<'EOF'
gitall - führt einen beliebigen git-Befehl in allen Git-Repositories unterhalb
des aktuellen Verzeichnisses aus.

Verwendung:
  gitall <git-subcommand> [args...]
EOF
      [ -z "${1:-}" ] && return 1 || return 0
      ;;
  esac

  find . -type d -name .git -prune | while read -r gitdir; do
    repo="${gitdir%/.git}"
    printf '===== %s =====\n' "$repo"
    git -C "$repo" --no-pager -c color.ui=always "$@"
    printf '\n'
  done
}

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
alias sdkui='cd ~/projects/sdk-core/sdkui'
alias docs='cd ~/projects/sdk/sdk-docs'
alias vault='cd ~/documents/obsidian-vaults/work-main'
alias vault-priv='cd ~/.sync/share-documentations/main'

