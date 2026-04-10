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

SANDBOX_HOME="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/agent-home.XXXXXX")"

SETTINGS_ROOT="${SANDBOX_SETTINGS_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/agent-sandbox}"
PERSIST_COPILOT_CONFIG="$SETTINGS_ROOT/copilot/config.json"
PERSIST_CODEX_CONFIG="$SETTINGS_ROOT/codex/config.toml"
mkdir -p "$(dirname "$PERSIST_COPILOT_CONFIG")" "$(dirname "$PERSIST_CODEX_CONFIG")"

cleanup() {
  local rc=$?

  # Persist only settings files; auth remains ephemeral and is re-seeded from host each run.
  if [[ -f "$SANDBOX_HOME/.copilot/config.json" ]]; then
    cp "$SANDBOX_HOME/.copilot/config.json" "$PERSIST_COPILOT_CONFIG" || true
  fi
  if [[ -f "$SANDBOX_HOME/.codex/config.toml" ]]; then
    cp "$SANDBOX_HOME/.codex/config.toml" "$PERSIST_CODEX_CONFIG" || true
  fi

  rm -rf "$SANDBOX_HOME"
  exit "$rc"
}
trap cleanup EXIT

mkdir -p \
  "$SANDBOX_HOME/.config" \
  "$SANDBOX_HOME/.cache" \
  "$SANDBOX_HOME/.local/share" \
  "$SANDBOX_HOME/.local/bin"

# ---------------------------------------------------------------------------
# Credential seeding — copy only what each agent needs
# ---------------------------------------------------------------------------

# git identity (non-secret)
[[ -f "$HOME/.gitconfig" ]]        && cp "$HOME/.gitconfig"        "$SANDBOX_HOME/.gitconfig"
[[ -f "$HOME/.gitignore_global" ]] && cp "$HOME/.gitignore_global" "$SANDBOX_HOME/.gitignore_global"

# GitHub Copilot CLI — pre-trust /workspace to skip the folder-trust prompt
COPILOT_SOURCE_CONFIG=""
[[ -f "$PERSIST_COPILOT_CONFIG" ]] && COPILOT_SOURCE_CONFIG="$PERSIST_COPILOT_CONFIG"
[[ -z "$COPILOT_SOURCE_CONFIG" && -f "$HOME/.copilot/config.json" ]] && COPILOT_SOURCE_CONFIG="$HOME/.copilot/config.json"
if [[ -n "$COPILOT_SOURCE_CONFIG" ]]; then
  mkdir -p "$SANDBOX_HOME/.copilot"
  if command -v jq &>/dev/null; then
    jq '.trusted_folders = ([.trusted_folders // []] | flatten | . + ["/workspace"] | unique)' \
      "$COPILOT_SOURCE_CONFIG" > "$SANDBOX_HOME/.copilot/config.json"
  else
    cp "$COPILOT_SOURCE_CONFIG" "$SANDBOX_HOME/.copilot/config.json"
  fi
fi

# Codex CLI — auth + pre-trust /workspace in config.toml
if [[ -f "$HOME/.codex/auth.json" ]]; then
  mkdir -p "$SANDBOX_HOME/.codex"
  cp "$HOME/.codex/auth.json" "$SANDBOX_HOME/.codex/auth.json"
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

# ---------------------------------------------------------------------------
# PATH inside sandbox
# ---------------------------------------------------------------------------

SANDBOX_PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
[[ -d "$HOME/.bun/bin" ]]         && SANDBOX_PATH="/home/user/.bun/bin:$SANDBOX_PATH"
[[ -d "$HOME/.local/bin" ]]       && SANDBOX_PATH="/home/user/.local/bin:$SANDBOX_PATH"
[[ -d "$HOME/.nix-profile/bin" ]] && SANDBOX_PATH="/home/user/.nix-profile/bin:$SANDBOX_PATH"
[[ -d /snap/bin ]]                && SANDBOX_PATH="$SANDBOX_PATH:/snap/bin"

# D-Bus session socket — needed for keyring access (e.g. copilot token via libsecret).
# Only bind it when the socket actually exists; skip silently otherwise.
DBUS_ARGS=()
if [[ -n "${XDG_RUNTIME_DIR:-}" && -S "${XDG_RUNTIME_DIR}/bus" ]]; then
  DBUS_ARGS+=(--dir "${XDG_RUNTIME_DIR}")
  DBUS_ARGS+=(--bind "${XDG_RUNTIME_DIR}/bus" "${XDG_RUNTIME_DIR}/bus")
  DBUS_ARGS+=(--setenv XDG_RUNTIME_DIR "${XDG_RUNTIME_DIR}")
  DBUS_ARGS+=(--setenv DBUS_SESSION_BUS_ADDRESS "${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}")
fi
DBUS_ENABLED="no"
[[ ${#DBUS_ARGS[@]} -gt 0 ]] && DBUS_ENABLED="yes"

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
  printf 'settings_root=%q\n' "$SETTINGS_ROOT"
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

# Print active runtime settings so it's obvious this is sandboxed.
printf '[agent-sandbox] SANDBOXED RUN active\n' >&2
printf '[agent-sandbox] project=%s\n' "$PROJECT" >&2
printf '[agent-sandbox] workspace=/workspace home=/home/user (ephemeral)\n' >&2
printf '[agent-sandbox] network=%s dbus=%s trace=%s\n' \
  "$([[ "$NO_NET" == "1" ]] && echo off || echo on)" \
  "$DBUS_ENABLED" \
  "$TRACE_ENABLED" >&2
printf '[agent-sandbox] settings_root=%s\n' "$SETTINGS_ROOT" >&2
printf '[agent-sandbox] logfile=%s\n' "$LOGFILE" >&2
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
  "${DBUS_ARGS[@]}" \
  \
  "${STD_BINDS[@]}" \
  "${ETC_ARGS[@]}" \
  "${NIX_ARGS[@]}" \
  "${EXTRA_RO_ARGS[@]}" \
  \
  --bind "$PROJECT" /workspace \
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
  --setenv XDG_DATA_HOME   /home/user/.local/share \
  --setenv PATH            "$SANDBOX_PATH" \
  --setenv TERM            "${TERM:-xterm-256color}" \
  --setenv COLORTERM       "${COLORTERM:-truecolor}" \
  \
  "${CMD[@]}"
