#!/usr/bin/env bash
# agent-sandbox.sh — bubblewrap sandbox for AI coding agents (Copilot CLI, Codex, etc.)
#
# Usage:
#   agent-sandbox.sh [OPTIONS] [PROJECT_DIR] [COMMAND [ARGS...]]
#
# Options:
#   -n, --no-net    Disable network (also: NO_NET=1)
#   -h, --help      Show this help
#
# PROJECT_DIR is optional. If the first positional arg is a directory it is
# used as the project; otherwise $PWD is used and all positional args are the
# command. Use -- to unambiguously separate project from command.
#
# Environment variables:
#   NO_NET=1                     Disable network
#   EXTRA_BIND="h:c ..."         Space-separated read-write bind pairs (host:container)
#   EXTRA_RO="h:c ..."           Space-separated read-only bind pairs (host:container)
#   SANDBOX_SETTINGS_DIR=/path   Persistent settings dir (default: ~/.config/agent-sandbox)
#   SANDBOX_STATE_DIR=/path      Persistent state dir (default: ~/.local/state/agent-sandbox)
#   SANDBOX_CLIPBOARD=mode       Clipboard transport: auto|x11|wayland|off (default: auto).
#                                "auto" prefers X11/XWayland because the agents'
#                                Wayland clipboard path fails on compositors
#                                without wlr/ext-data-control (e.g. GNOME), which
#                                breaks image paste.
#
# Examples:
#   agent-sandbox.sh                        # sandbox $PWD, bash
#   agent-sandbox.sh ~/src/myapp           # sandbox that project, bash
#   agent-sandbox.sh ~/src/myapp codex     # sandbox + codex
#   agent-sandbox.sh codex --prompt "..."  # sandbox $PWD + codex (auto-detected)
#   agent-sandbox.sh -n codex              # no network
#   NO_NET=1 agent-sandbox.sh codex        # same via env

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

NO_NET="${NO_NET:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--no-net) NO_NET=1; shift ;;
    -h|--help)   grep '^#' "$0" | sed 's/^# \?//' >&2; exit 0 ;;
    --)          shift; break ;;
    -*)          echo "agent-sandbox: unknown option: $1" >&2; exit 1 ;;
    *)           break ;;
  esac
done

# If the first remaining arg is a directory, treat it as the project.
# Otherwise default to $PWD and treat all remaining args as the command.
if [[ $# -gt 0 && -d "$1" ]]; then
  PROJECT="$(realpath "$1")"
  shift
else
  PROJECT="$(realpath "$PWD")"
fi

CMD=("${@:-bash}")

# ---------------------------------------------------------------------------
# Scratch home — ephemeral, cleaned up on exit
# ---------------------------------------------------------------------------

RUNTIME_BASE="${XDG_RUNTIME_DIR:-/tmp}"

# Garbage-collect scratch homes leaked by earlier runs that were hard-killed
# (SIGKILL, terminal hangup) before their cleanup trap could fire. The owning
# PID is encoded in the directory name; a home is only removed when that PID is
# no longer alive, so concurrent live sandboxes are never touched. Untagged
# legacy dirs (no numeric PID field) are left alone — we never delete a home we
# can't prove is dead.
for stale in "$RUNTIME_BASE"/agent-home.*; do
  [[ -d "$stale" ]] || continue
  stale_pid="${stale##*/agent-home.}"
  stale_pid="${stale_pid%%.*}"
  [[ "$stale_pid" =~ ^[0-9]+$ ]] || continue
  kill -0 "$stale_pid" 2>/dev/null && continue
  rm -rf "$stale"
done

# PID-tagged (agent-home.<pid>.XXXXXX) so the GC above can identify the owner.
SANDBOX_HOME="$(mktemp -d "$RUNTIME_BASE/agent-home.$$.XXXXXX")"

SETTINGS_ROOT="${SANDBOX_SETTINGS_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/agent-sandbox}"
STATE_ROOT="${SANDBOX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/agent-sandbox}"
PERSIST_COPILOT_CONFIG="$SETTINGS_ROOT/copilot/config.json"
PERSIST_COPILOT_HOME="$STATE_ROOT/copilot/home"
PERSIST_CODEX_CONFIG="$SETTINGS_ROOT/codex/config.toml"
PERSIST_CODEX_HOME="$STATE_ROOT/codex/home"
PERSIST_CODEX_XDG_STATE="$STATE_ROOT/codex/xdg-state"
PERSIST_CLAUDE_SETTINGS="$SETTINGS_ROOT/claude/settings.json"
PERSIST_CLAUDE_HOME="$STATE_ROOT/claude/home"
PERSIST_JUNIE_SETTINGS="$SETTINGS_ROOT/junie/settings.json"
PERSIST_JUNIE_HOME="$STATE_ROOT/junie/home"
mkdir -p \
  "$(dirname "$PERSIST_COPILOT_CONFIG")" \
  "$PERSIST_COPILOT_HOME" \
  "$(dirname "$PERSIST_CODEX_CONFIG")" \
  "$PERSIST_CODEX_HOME" \
  "$PERSIST_CODEX_XDG_STATE" \
  "$(dirname "$PERSIST_CLAUDE_SETTINGS")" \
  "$PERSIST_CLAUDE_HOME" \
  "$(dirname "$PERSIST_JUNIE_SETTINGS")" \
  "$PERSIST_JUNIE_HOME"

sync_tree() {
  local src="$1"
  local dest="$2"
  shift 2

  mkdir -p "$dest"
  if command -v rsync &>/dev/null; then
    rsync -a --delete "$@" "$src"/ "$dest"/
    return
  fi

  (
    cd "$src"
    tar -cf - "$@" .
  ) | (
    cd "$dest"
    tar -xf -
  )
}

cleanup() {
  local rc=$?

  # Persist settings separately from session state; auth remains ephemeral and is re-seeded from host each run.
  if [[ -f "$SANDBOX_HOME/.copilot/config.json" ]]; then
    cp "$SANDBOX_HOME/.copilot/config.json" "$PERSIST_COPILOT_CONFIG" || true
  fi
  if [[ -f "$SANDBOX_HOME/.codex/config.toml" ]]; then
    cp "$SANDBOX_HOME/.codex/config.toml" "$PERSIST_CODEX_CONFIG" || true
  fi
  if [[ -f "$SANDBOX_HOME/.claude/settings.json" ]]; then
    cp "$SANDBOX_HOME/.claude/settings.json" "$PERSIST_CLAUDE_SETTINGS" || true
  fi
  if [[ -f "$SANDBOX_HOME/.junie/settings.json" ]]; then
    cp "$SANDBOX_HOME/.junie/settings.json" "$PERSIST_JUNIE_SETTINGS" || true
  fi
  {
    printf 'cleanup_copilot_home_exists=%s\n' "$([[ -d "$SANDBOX_HOME/.copilot" ]] && echo yes || echo no)"
    printf 'cleanup_codex_home_exists=%s\n' "$([[ -d "$SANDBOX_HOME/.codex" ]] && echo yes || echo no)"
    printf 'cleanup_codex_xdg_state_exists=%s\n' "$([[ -d "$SANDBOX_HOME/.local/state/codex" ]] && echo yes || echo no)"
    printf 'cleanup_claude_home_exists=%s\n' "$([[ -d "$SANDBOX_HOME/.claude" ]] && echo yes || echo no)"
    printf 'cleanup_junie_home_exists=%s\n' "$([[ -d "$SANDBOX_HOME/.junie" ]] && echo yes || echo no)"
  } >> "${LOGFILE:-/dev/null}" 2>/dev/null || true
  if [[ -d "$SANDBOX_HOME/.copilot" ]]; then
    sync_tree "$SANDBOX_HOME/.copilot" "$PERSIST_COPILOT_HOME" \
      --exclude config.json \
      --exclude tmp \
      --exclude .tmp || true
  fi
  if [[ -d "$SANDBOX_HOME/.codex" ]]; then
    sync_tree "$SANDBOX_HOME/.codex" "$PERSIST_CODEX_HOME" \
      --exclude auth.json \
      --exclude config.toml \
      --exclude tmp \
      --exclude .tmp || true
  fi
  if [[ -d "$SANDBOX_HOME/.local/state/codex" ]]; then
    sync_tree "$SANDBOX_HOME/.local/state/codex" "$PERSIST_CODEX_XDG_STATE" || true
  fi
  if [[ -d "$SANDBOX_HOME/.claude" ]]; then
    sync_tree "$SANDBOX_HOME/.claude" "$PERSIST_CLAUDE_HOME" \
      --exclude credentials.json \
      --exclude settings.json \
      --exclude tmp \
      --exclude .tmp || true
  fi
  if [[ -d "$SANDBOX_HOME/.junie" ]]; then
    sync_tree "$SANDBOX_HOME/.junie" "$PERSIST_JUNIE_HOME" \
      --exclude settings.json \
      --exclude secure_credentials.json \
      --exclude tmp \
      --exclude .tmp || true
  fi

  rm -rf "$SANDBOX_HOME"
  exit "$rc"
}
trap cleanup EXIT
# Ensure the EXIT cleanup also runs when the script is signalled (terminal
# closed → SIGHUP, kill → SIGTERM, Ctrl-C → SIGINT); each handler just exits,
# firing the single EXIT trap above. SIGKILL can't be trapped — the startup GC
# is the backstop for that case.
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

mkdir -p \
  "$SANDBOX_HOME/.config" \
  "$SANDBOX_HOME/.cache" \
  "$SANDBOX_HOME/.local/state" \
  "$SANDBOX_HOME/.local/share" \
  "$SANDBOX_HOME/.local/bin"

# ---------------------------------------------------------------------------
# Credential seeding — copy only what each agent needs
# ---------------------------------------------------------------------------

# git identity (non-secret)
[[ -f "$HOME/.gitconfig" ]]        && cp "$HOME/.gitconfig"        "$SANDBOX_HOME/.gitconfig"
[[ -f "$HOME/.gitignore_global" ]] && cp "$HOME/.gitignore_global" "$SANDBOX_HOME/.gitignore_global"

# GitHub Copilot CLI — pre-trust /workspace to skip the folder-trust prompt
if [[ -d "$PERSIST_COPILOT_HOME" ]]; then
  mkdir -p "$SANDBOX_HOME/.copilot"
  sync_tree "$PERSIST_COPILOT_HOME" "$SANDBOX_HOME/.copilot" \
    --exclude config.json \
    --exclude tmp \
    --exclude .tmp
fi

COPILOT_SOURCE_CONFIG=""
# Prefer persisted config if it exists and is non-empty
[[ -f "$PERSIST_COPILOT_CONFIG" && -s "$PERSIST_COPILOT_CONFIG" ]] && COPILOT_SOURCE_CONFIG="$PERSIST_COPILOT_CONFIG"
# Fall back to host config
[[ -z "$COPILOT_SOURCE_CONFIG" && -f "$HOME/.copilot/config.json" ]] && COPILOT_SOURCE_CONFIG="$HOME/.copilot/config.json"
if [[ -n "$COPILOT_SOURCE_CONFIG" ]]; then
  mkdir -p "$SANDBOX_HOME/.copilot"
  if command -v jq &>/dev/null; then
    # Strip JS-style comments (lines starting with //) before parsing
    grep -v '^[[:space:]]*//' "$COPILOT_SOURCE_CONFIG" | \
      jq '.trustedFolders = ([.trustedFolders // [], .trusted_folders // []] | flatten | . + ["/workspace"] | unique) | del(.trusted_folders)' \
      > "$SANDBOX_HOME/.copilot/config.json"
  else
    cp "$COPILOT_SOURCE_CONFIG" "$SANDBOX_HOME/.copilot/config.json"
  fi
fi

# Copy permissions config if it exists (tool approvals). Persisted sandbox state wins
# so approvals changed inside the sandbox survive the next run.
if [[ ! -s "$SANDBOX_HOME/.copilot/permissions-config.json" && -f "$HOME/.copilot/permissions-config.json" ]]; then
  mkdir -p "$SANDBOX_HOME/.copilot"
  cp "$HOME/.copilot/permissions-config.json" "$SANDBOX_HOME/.copilot/permissions-config.json"
fi

# Copy settings if they exist. Do not overwrite persisted sandbox login metadata.
if [[ ! -s "$SANDBOX_HOME/.copilot/settings.json" && -f "$HOME/.copilot/settings.json" ]]; then
  mkdir -p "$SANDBOX_HOME/.copilot"
  cp "$HOME/.copilot/settings.json" "$SANDBOX_HOME/.copilot/settings.json"
fi

# Copy GNOME keyring for authentication tokens (read-only to prevent corruption)
if [[ -d "$HOME/.local/share/keyrings" ]]; then
  mkdir -p "$SANDBOX_HOME/.local/share/keyrings"
  cp -r "$HOME/.local/share/keyrings"/* "$SANDBOX_HOME/.local/share/keyrings/" 2>/dev/null || true
fi

# Codex CLI — auth + pre-trust /workspace in config.toml
if [[ -f "$HOME/.codex/auth.json" ]]; then
  mkdir -p "$SANDBOX_HOME/.codex"
  cp "$HOME/.codex/auth.json" "$SANDBOX_HOME/.codex/auth.json"
fi

if [[ -d "$PERSIST_CODEX_HOME" ]]; then
  mkdir -p "$SANDBOX_HOME/.codex"
  sync_tree "$PERSIST_CODEX_HOME" "$SANDBOX_HOME/.codex" \
    --exclude auth.json \
    --exclude config.toml \
    --exclude tmp \
    --exclude .tmp
fi

if [[ -d "$PERSIST_CODEX_XDG_STATE" ]]; then
  mkdir -p "$SANDBOX_HOME/.local/state/codex"
  sync_tree "$PERSIST_CODEX_XDG_STATE" "$SANDBOX_HOME/.local/state/codex"
fi

CODEX_SOURCE_CONFIG=""
[[ -f "$PERSIST_CODEX_CONFIG" ]] && CODEX_SOURCE_CONFIG="$PERSIST_CODEX_CONFIG"
[[ -z "$CODEX_SOURCE_CONFIG" && -f "$HOME/.codex/config.toml" ]] && CODEX_SOURCE_CONFIG="$HOME/.codex/config.toml"
if [[ -n "$CODEX_SOURCE_CONFIG" ]]; then
  mkdir -p "$SANDBOX_HOME/.codex"
  cp "$CODEX_SOURCE_CONFIG" "$SANDBOX_HOME/.codex/config.toml"
fi
if [[ -f "$SANDBOX_HOME/.codex/config.toml" ]] && ! grep -q '"/workspace"' "$SANDBOX_HOME/.codex/config.toml"; then
  printf '\n[projects."/workspace"]\ntrust_level = "trusted"\n' \
    >> "$SANDBOX_HOME/.codex/config.toml"
fi

# Claude Code CLI — auth + settings + pre-trust /workspace
if [[ -f "$HOME/.claude/credentials.json" ]]; then
  mkdir -p "$SANDBOX_HOME/.claude"
  cp "$HOME/.claude/credentials.json" "$SANDBOX_HOME/.claude/credentials.json"
fi

if [[ -d "$PERSIST_CLAUDE_HOME" ]]; then
  mkdir -p "$SANDBOX_HOME/.claude"
  sync_tree "$PERSIST_CLAUDE_HOME" "$SANDBOX_HOME/.claude" \
    --exclude credentials.json \
    --exclude settings.json \
    --exclude tmp \
    --exclude .tmp
fi

CLAUDE_SOURCE_SETTINGS=""
[[ -f "$PERSIST_CLAUDE_SETTINGS" && -s "$PERSIST_CLAUDE_SETTINGS" ]] && CLAUDE_SOURCE_SETTINGS="$PERSIST_CLAUDE_SETTINGS"
[[ -z "$CLAUDE_SOURCE_SETTINGS" && -f "$HOME/.claude/settings.json" ]] && CLAUDE_SOURCE_SETTINGS="$HOME/.claude/settings.json"
if [[ -n "$CLAUDE_SOURCE_SETTINGS" ]]; then
  mkdir -p "$SANDBOX_HOME/.claude"
  if command -v jq &>/dev/null; then
    jq '.allowedTools = ((.allowedTools // []) | . + ["Bash", "Edit", "Write"] | unique) | .trustedDirectories = ((.trustedDirectories // []) | . + ["/workspace"] | unique)' \
      "$CLAUDE_SOURCE_SETTINGS" > "$SANDBOX_HOME/.claude/settings.json"
  else
    cp "$CLAUDE_SOURCE_SETTINGS" "$SANDBOX_HOME/.claude/settings.json"
  fi
fi

# JetBrains Junie CLI — state (sessions, allowlist.json, mcp/, models/,
# agent-skills/) + settings.json. secure_credentials.json is only the fallback
# secret store used when no system keyring is available, so it is re-seeded
# fresh from the host each run (like Claude's credentials.json) rather than
# persisted from the sandbox.
if [[ -d "$PERSIST_JUNIE_HOME" ]]; then
  mkdir -p "$SANDBOX_HOME/.junie"
  sync_tree "$PERSIST_JUNIE_HOME" "$SANDBOX_HOME/.junie" \
    --exclude settings.json \
    --exclude secure_credentials.json \
    --exclude tmp \
    --exclude .tmp
fi

if [[ -f "$HOME/.junie/secure_credentials.json" ]]; then
  mkdir -p "$SANDBOX_HOME/.junie"
  cp "$HOME/.junie/secure_credentials.json" "$SANDBOX_HOME/.junie/secure_credentials.json"
fi

JUNIE_SOURCE_SETTINGS=""
[[ -f "$PERSIST_JUNIE_SETTINGS" && -s "$PERSIST_JUNIE_SETTINGS" ]] && JUNIE_SOURCE_SETTINGS="$PERSIST_JUNIE_SETTINGS"
[[ -z "$JUNIE_SOURCE_SETTINGS" && -f "$HOME/.junie/settings.json" ]] && JUNIE_SOURCE_SETTINGS="$HOME/.junie/settings.json"
if [[ -n "$JUNIE_SOURCE_SETTINGS" ]]; then
  mkdir -p "$SANDBOX_HOME/.junie"
  cp "$JUNIE_SOURCE_SETTINGS" "$SANDBOX_HOME/.junie/settings.json"
fi

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

NET_ARGS=()
[[ "$NO_NET" == "1" ]] && NET_ARGS=(--unshare-net)

# ---------------------------------------------------------------------------
# Extra bind mounts — space-separated host:container pairs, with validation
# ---------------------------------------------------------------------------

EXTRA_BIND_ARGS=()
for pair in ${EXTRA_BIND:-}; do
  host="${pair%%:*}" guest="${pair#*:}"
  if [[ -z "$host" || -z "$guest" || "$host" == "$pair" ]]; then
    echo "agent-sandbox: malformed EXTRA_BIND entry '$pair' (expected host:container)" >&2; exit 1
  fi
  [[ ! -e "$host" ]] && { echo "agent-sandbox: EXTRA_BIND host path not found: '$host'" >&2; exit 1; }
  EXTRA_BIND_ARGS+=(--bind "$host" "$guest")
done

EXTRA_RO_ARGS=()
for pair in ${EXTRA_RO:-}; do
  host="${pair%%:*}" guest="${pair#*:}"
  if [[ -z "$host" || -z "$guest" || "$host" == "$pair" ]]; then
    echo "agent-sandbox: malformed EXTRA_RO entry '$pair' (expected host:container)" >&2; exit 1
  fi
  [[ ! -e "$host" ]] && { echo "agent-sandbox: EXTRA_RO host path not found: '$host'" >&2; exit 1; }
  EXTRA_RO_ARGS+=(--ro-bind "$host" "$guest")
done

# ---------------------------------------------------------------------------
# Standard OS paths (handles distros where /bin, /lib* are symlinks)
# ---------------------------------------------------------------------------

STD_BINDS=()
for p in /usr /bin /sbin /lib /lib32 /lib64 /libx32; do
  [[ -e "$p" ]] && STD_BINDS+=(--ro-bind "$p" "$p")
done

# ---------------------------------------------------------------------------
# /etc — required files as an array (no inline command substitutions)
# ---------------------------------------------------------------------------

ETC_ARGS=(
  --ro-bind /etc/resolv.conf /etc/resolv.conf
  --ro-bind /etc/hosts       /etc/hosts
  --ro-bind /etc/passwd      /etc/passwd
  --ro-bind /etc/group       /etc/group
)
[[ -d /etc/ssl ]]             && ETC_ARGS+=(--ro-bind /etc/ssl             /etc/ssl)
[[ -d /etc/ca-certificates ]] && ETC_ARGS+=(--ro-bind /etc/ca-certificates /etc/ca-certificates)
[[ -f /etc/nsswitch.conf ]]   && ETC_ARGS+=(--ro-bind /etc/nsswitch.conf   /etc/nsswitch.conf)

# ---------------------------------------------------------------------------
# Nix + global tool paths (applied before /home/user is created)
# ---------------------------------------------------------------------------

NIX_ARGS=()
[[ -d /nix ]]                          && NIX_ARGS+=(--ro-bind /nix /nix)
[[ -L /run/current-system ]]           && NIX_ARGS+=(--ro-bind /run/current-system /run/current-system)
[[ -d /nix/var/nix/profiles/per-user ]] && NIX_ARGS+=(--ro-bind /nix/var/nix/profiles/per-user /nix/var/nix/profiles/per-user)
[[ -d /snap ]]                         && NIX_ARGS+=(--ro-bind /snap /snap)

# ---------------------------------------------------------------------------
# Home-relative binds (applied AFTER --dir /home/user)
# ---------------------------------------------------------------------------

HOME_BIND_ARGS=()
[[ -d "$HOME/.nix-profile" ]] && HOME_BIND_ARGS+=(--ro-bind "$HOME/.nix-profile" /home/user/.nix-profile)
[[ -d "$HOME/.local/bin" ]]   && HOME_BIND_ARGS+=(--ro-bind "$HOME/.local/bin"   /home/user/.local/bin)
[[ -d "$HOME/.bun" ]]         && HOME_BIND_ARGS+=(--ro-bind "$HOME/.bun"         /home/user/.bun)
# Junie CLI's ~/.local/bin/junie shim execs the versioned binary from here;
# without it the shim can't find anything to run.
[[ -d "$HOME/.local/share/junie" ]] && HOME_BIND_ARGS+=(--ro-bind "$HOME/.local/share/junie" /home/user/.local/share/junie)
# Playwright browser binaries ($XDG_CACHE_HOME/ms-playwright). Read-only so the
# agent reuses already-downloaded browsers without re-fetching each run, and
# cannot tamper with binaries that also execute host-side. Versions not present
# on the host will fail to install rather than download into the ro mount.
[[ -d "$HOME/.cache/ms-playwright" ]] && HOME_BIND_ARGS+=(--ro-bind "$HOME/.cache/ms-playwright" /home/user/.cache/ms-playwright)
# Vim / Neovim config — read-only so the agent can use the host editor settings.
[[ -f "$HOME/.vimrc" ]]                   && HOME_BIND_ARGS+=(--ro-bind "$HOME/.vimrc"                   /home/user/.vimrc)
[[ -d "$HOME/.vim" ]]                     && HOME_BIND_ARGS+=(--ro-bind "$HOME/.vim"                     /home/user/.vim)
[[ -d "$HOME/.config/nvim" ]]             && HOME_BIND_ARGS+=(--ro-bind "$HOME/.config/nvim"             /home/user/.config/nvim)
# Neovim plugin data — read-only so lazy.nvim reuses host-installed plugins
# instead of cloning everything fresh on every sandbox session.
[[ -d "$HOME/.local/share/nvim" ]]        && HOME_BIND_ARGS+=(--ro-bind "$HOME/.local/share/nvim"        /home/user/.local/share/nvim)

# Keep Git metadata read-only by default while leaving the worktree writable.
PROJECT_GIT_ARGS=()
[[ -d "$PROJECT/.git" ]] && PROJECT_GIT_ARGS=(--ro-bind "$PROJECT/.git" /workspace/.git)

# ---------------------------------------------------------------------------
# PATH inside sandbox
# ---------------------------------------------------------------------------

SANDBOX_PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
[[ -d "$HOME/.bun/bin" ]]         && SANDBOX_PATH="/home/user/.bun/bin:$SANDBOX_PATH"
[[ -d "$HOME/.local/bin" ]]       && SANDBOX_PATH="/home/user/.local/bin:$SANDBOX_PATH"
[[ -d "$HOME/.nix-profile/bin" ]] && SANDBOX_PATH="/home/user/.nix-profile/bin:$SANDBOX_PATH"
[[ -d /snap/bin ]]                && SANDBOX_PATH="$SANDBOX_PATH:/snap/bin"

# GUI/session runtime forwarding. Keep this selective: only session sockets and
# auth that agents need for clipboard, keyring and similar desktop integrations.
SESSION_RUNTIME_ARGS=()
SESSION_ENV_ARGS=()
SESSION_DIRS_CREATED=":"

ensure_runtime_dir() {
  local dir="$1"
  [[ -n "$dir" ]] || return 0
  [[ "$SESSION_DIRS_CREATED" == *":$dir:"* ]] && return 0
  SESSION_RUNTIME_ARGS+=(--dir "$dir")
  SESSION_DIRS_CREATED+="${dir}:"
}

# D-Bus session socket — needed for keyring access (e.g. copilot token via
# libsecret). Only bind it when the socket actually exists; skip silently
# otherwise.
DBUS_ENABLED="no"
if [[ -n "${XDG_RUNTIME_DIR:-}" && -S "${XDG_RUNTIME_DIR}/bus" ]]; then
  ensure_runtime_dir "${XDG_RUNTIME_DIR}"
  SESSION_RUNTIME_ARGS+=(--bind "${XDG_RUNTIME_DIR}/bus" "${XDG_RUNTIME_DIR}/bus")
  SESSION_ENV_ARGS+=(--setenv XDG_RUNTIME_DIR "${XDG_RUNTIME_DIR}")
  SESSION_ENV_ARGS+=(--setenv DBUS_SESSION_BUS_ADDRESS "${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}")
  DBUS_ENABLED="yes"
fi

# Clipboard transport (Wayland vs X11/XWayland).
#
# Agents read the clipboard — including pasted images — through a bundled Rust
# clipboard library (clipboard-rs). On Wayland that library needs the
# wlr-data-control / ext-data-control protocol, which several compositors
# (notably GNOME/Mutter) do not expose in a compatible way, so image paste
# silently fails with "a required Wayland protocol ... is not supported by the
# compositor". XWayland's classic X11 selections work reliably and also carry
# images copied from native Wayland apps, so we prefer X11 for the clipboard
# whenever XWayland is reachable and only fall back to native Wayland when there
# is no X11 display.
#
# Override with SANDBOX_CLIPBOARD=auto|x11|wayland|off (default: auto).
CLIPBOARD_MODE="${SANDBOX_CLIPBOARD:-auto}"
case "$CLIPBOARD_MODE" in
  auto|x11|wayland|off) ;;
  *) echo "agent-sandbox: invalid SANDBOX_CLIPBOARD='$CLIPBOARD_MODE' (expected auto|x11|wayland|off)" >&2; exit 1 ;;
esac

# Probe which transports the host actually exposes.
wl_socket=""
[[ -n "${XDG_RUNTIME_DIR:-}" && -n "${WAYLAND_DISPLAY:-}" && -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]] \
  && wl_socket="${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"

x11_socket=""
if [[ "${DISPLAY:-}" =~ ^:([0-9]+)(\.[0-9]+)?$ ]] && [[ -d /tmp/.X11-unix ]]; then
  display_num="${BASH_REMATCH[1]}"
  [[ -S "/tmp/.X11-unix/X${display_num}" ]] && x11_socket="/tmp/.X11-unix/X${display_num}"
fi

# Resolve the effective transport(s). "auto" prefers X11 when XWayland exists.
USE_WAYLAND="no"
USE_X11="no"
case "$CLIPBOARD_MODE" in
  off)     ;;
  x11)     [[ -n "$x11_socket" ]] && USE_X11="yes" ;;
  wayland) [[ -n "$wl_socket"  ]] && USE_WAYLAND="yes" ;;
  auto)
    if   [[ -n "$x11_socket" ]]; then USE_X11="yes"
    elif [[ -n "$wl_socket"  ]]; then USE_WAYLAND="yes"
    fi ;;
esac

WAYLAND_ENABLED="no"
X11_ENABLED="no"

if [[ "$USE_WAYLAND" == "yes" ]]; then
  # Native Wayland clipboard. /dev/shm is shared so large image buffers can be
  # passed via the wl_shm protocol (shm_open) by Wayland clients.
  ensure_runtime_dir "${XDG_RUNTIME_DIR}"
  SESSION_RUNTIME_ARGS+=(--bind "$wl_socket" "$wl_socket")
  SESSION_ENV_ARGS+=(--setenv XDG_RUNTIME_DIR "${XDG_RUNTIME_DIR}")
  SESSION_ENV_ARGS+=(--setenv WAYLAND_DISPLAY "${WAYLAND_DISPLAY}")
  SESSION_ENV_ARGS+=(--setenv XDG_SESSION_TYPE wayland)
  [[ -d /dev/shm ]] && SESSION_RUNTIME_ARGS+=(--bind /dev/shm /dev/shm)
  WAYLAND_ENABLED="yes"
else
  # Not using native Wayland: actively hide WAYLAND_DISPLAY (inherited from the
  # host env, since bwrap does not --clearenv) so the clipboard library does not
  # attempt — and fail on — the Wayland path.
  SESSION_ENV_ARGS+=(--unsetenv WAYLAND_DISPLAY)
fi

if [[ "$USE_X11" == "yes" ]]; then
  # X11 clipboard access needs the display socket and an auth cookie.
  ensure_runtime_dir /tmp/.X11-unix
  SESSION_RUNTIME_ARGS+=(--ro-bind /tmp/.X11-unix /tmp/.X11-unix)
  SESSION_ENV_ARGS+=(--setenv DISPLAY "${DISPLAY}")
  # clipboard-rs keys off XDG_SESSION_TYPE too, so pin it to x11 when we are not
  # also offering native Wayland.
  [[ "$USE_WAYLAND" == "yes" ]] || SESSION_ENV_ARGS+=(--setenv XDG_SESSION_TYPE x11)
  if [[ -n "${XAUTHORITY:-}" && -f "${XAUTHORITY}" ]]; then
    SESSION_RUNTIME_ARGS+=(--ro-bind "${XAUTHORITY}" /tmp/agent-sandbox.Xauthority)
    SESSION_ENV_ARGS+=(--setenv XAUTHORITY /tmp/agent-sandbox.Xauthority)
  fi
  X11_ENABLED="yes"
fi

# ---------------------------------------------------------------------------
# Session logging
# ---------------------------------------------------------------------------

LOGDIR="${XDG_STATE_HOME:-$HOME/.local/state}/agent-sandbox"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/$(date +%Y%m%d-%H%M%S)-$$.log"

{
  printf 'time=%s\n'    "$(date --iso-8601=seconds)"
  printf 'project=%q\n' "$PROJECT"
  printf 'no_net=%q\n'  "$NO_NET"
  printf 'dbus=%s\n'    "$DBUS_ENABLED"
  printf 'clipboard=%s\n' "$CLIPBOARD_MODE"
  printf 'wayland=%s\n' "$WAYLAND_ENABLED"
  printf 'x11=%s\n'     "$X11_ENABLED"
  printf 'settings_root=%q\n' "$SETTINGS_ROOT"
  printf 'state_root=%q\n' "$STATE_ROOT"
  printf 'cmd='
  printf '%q ' "${CMD[@]}"
  printf '\n'
} >> "$LOGFILE"

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

if [[ "${TRACE_SANDBOX:-0}" == "1" ]]; then
  RUNNER=(strace -ff -s 200
    -o "$LOGDIR/$(date +%Y%m%d-%H%M%S)-$$-trace"
    -e trace=execve,openat,open,creat,unlink,unlinkat,rename,renameat
    bwrap)
  TRACE_ENABLED="yes"
else
  RUNNER=(bwrap)
  TRACE_ENABLED="no"
fi

# GitHub Copilot CLI token. Copilot 1.0.65 keeps its OAuth token in the host
# keyring, which the sandbox can't read, so it starts "Logged out". A
# fine-grained v2 PAT with the "Copilot Requests" permission is Copilot's
# supported headless path (COPILOT_GITHUB_TOKEN). Create the PAT on the GHE host
# and store it (chmod 600) at the path below. It is injected via the inherited
# environment — NOT --setenv — so the secret never lands on the bwrap command
# line (visible in ps / /proc/PID/cmdline); bwrap inherits this process's env
# because the run below does not use --clearenv.
COPILOT_TOKEN_FILE="${COPILOT_TOKEN_FILE:-$SETTINGS_ROOT/copilot/token}"
COPILOT_HOST_FILE="${COPILOT_HOST_FILE:-$SETTINGS_ROOT/copilot/host}"
COPILOT_TOKEN_STATUS="none"
if [[ -f "$COPILOT_TOKEN_FILE" && -s "$COPILOT_TOKEN_FILE" ]]; then
  COPILOT_GITHUB_TOKEN="$(tr -d '\r\n' < "$COPILOT_TOKEN_FILE")"
  export COPILOT_GITHUB_TOKEN
  COPILOT_TOKEN_STATUS="injected"

  # With env-token auth, Copilot validates against github.com and ignores the
  # host in config.json — a GHE data-residency PAT then returns "Bad
  # credentials". COPILOT_GH_HOST points validation at the right host. Resolve
  # it from the environment, a sibling `host` file, or by auto-deriving the
  # *.ghe.com host from config.json. Value must be a bare hostname.
  copilot_host="${COPILOT_GH_HOST:-}"
  [[ -z "$copilot_host" && -f "$COPILOT_HOST_FILE" && -s "$COPILOT_HOST_FILE" ]] \
    && copilot_host="$(tr -d '\r\n' < "$COPILOT_HOST_FILE")"
  [[ -z "$copilot_host" && -f "$HOME/.copilot/config.json" ]] \
    && copilot_host="$(grep -oE '"host":[[:space:]]*"https?://[^"]+"' "$HOME/.copilot/config.json" \
         | grep -oE 'https?://[^"]+' | sed -E 's#https?://##; s#/.*##' \
         | grep -iE '\.ghe\.com$' | head -1 || true)"
  if [[ -n "$copilot_host" ]]; then
    copilot_host="${copilot_host#http://}"; copilot_host="${copilot_host#https://}"; copilot_host="${copilot_host%%/*}"
    export COPILOT_GH_HOST="$copilot_host"
    COPILOT_TOKEN_STATUS="injected (host=$copilot_host)"
  fi
fi

# JetBrains Junie CLI token. Junie authenticates headlessly via JUNIE_API_KEY
# (see `junie --auth` / https://junie.jetbrains.com/cli). Store it (chmod 600)
# at the path below. Injected via the inherited environment — NOT --setenv —
# so the secret never lands on the bwrap command line (visible in ps /
# /proc/PID/cmdline); bwrap inherits this process's env because the run below
# does not use --clearenv.
JUNIE_TOKEN_FILE="${JUNIE_TOKEN_FILE:-$SETTINGS_ROOT/junie/token}"
JUNIE_TOKEN_STATUS="none"
if [[ -f "$JUNIE_TOKEN_FILE" && -s "$JUNIE_TOKEN_FILE" ]]; then
  JUNIE_API_KEY="$(tr -d '\r\n' < "$JUNIE_TOKEN_FILE")"
  export JUNIE_API_KEY
  JUNIE_TOKEN_STATUS="injected"
fi

# Print active runtime settings so it's obvious this is sandboxed.
printf '[agent-sandbox] SANDBOXED RUN active\n' >&2
printf '[agent-sandbox] project=%s\n' "$PROJECT" >&2
printf '[agent-sandbox] workspace=/workspace home=/home/user (ephemeral)\n' >&2
printf '[agent-sandbox] network=%s dbus=%s clipboard=%s wayland=%s x11=%s trace=%s\n' \
  "$([[ "$NO_NET" == "1" ]] && echo off || echo on)" \
  "$DBUS_ENABLED" \
  "$CLIPBOARD_MODE" \
  "$WAYLAND_ENABLED" \
  "$X11_ENABLED" \
  "$TRACE_ENABLED" >&2
printf '[agent-sandbox] settings_root=%s\n' "$SETTINGS_ROOT" >&2
printf '[agent-sandbox] state_root=%s\n' "$STATE_ROOT" >&2
printf '[agent-sandbox] logfile=%s\n' "$LOGFILE" >&2
printf '[agent-sandbox] copilot_token=%s\n' "$COPILOT_TOKEN_STATUS" >&2
printf '[agent-sandbox] junie_token=%s\n' "$JUNIE_TOKEN_STATUS" >&2
printf '[agent-sandbox] cmd=' >&2
printf '%q ' "${CMD[@]}" >&2
printf '\n' >&2

"${RUNNER[@]}" \
  --die-with-parent \
  --new-session \
  --unshare-user \
  --unshare-pid \
  --unshare-ipc \
  --unshare-uts \
  --hostname agent-sandbox \
  "${NET_ARGS[@]}" \
  \
  --proc /proc \
  --dev  /dev \
  --tmpfs /tmp \
  --tmpfs /run \
  "${SESSION_RUNTIME_ARGS[@]}" \
  \
  "${STD_BINDS[@]}" \
  "${ETC_ARGS[@]}" \
  "${NIX_ARGS[@]}" \
  "${EXTRA_RO_ARGS[@]}" \
  \
  --bind "$PROJECT" /workspace \
  "${PROJECT_GIT_ARGS[@]}" \
  --chdir /workspace \
  \
  --dir /home/user \
  --bind "$SANDBOX_HOME" /home/user \
  "${HOME_BIND_ARGS[@]}" \
  "${EXTRA_BIND_ARGS[@]}" \
  \
  --setenv HOME            /home/user \
  --setenv XDG_CONFIG_HOME /home/user/.config \
  --setenv XDG_CACHE_HOME  /home/user/.cache \
  --setenv XDG_STATE_HOME  /home/user/.local/state \
  --setenv XDG_DATA_HOME   /home/user/.local/share \
  --setenv COPILOT_AUTO_UPDATE "${COPILOT_AUTO_UPDATE:-false}" \
  --setenv PATH            "$SANDBOX_PATH" \
  --setenv TERM            "${TERM:-xterm-256color}" \
  --setenv COLORTERM       "${COLORTERM:-truecolor}" \
  "${SESSION_ENV_ARGS[@]}" \
  \
  "${CMD[@]}"
