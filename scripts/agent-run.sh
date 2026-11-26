#!/usr/bin/env bash
# Run a command (typically a coding agent) in its own transient systemd scope
# inside agents.slice, so all agents share one resource budget and the desktop
# keeps priority: agents.slice carries CPUWeight + MemoryHigh/MemoryMax.
#
# Per session there is only a soft brake (MemoryHigh): above it the kernel
# reclaims and throttles the session, nothing gets killed. The hard limit lives
# on agents.slice as a last-resort safety net. OOMPolicy=continue makes sure an
# OOM kill there takes out only the single offending process (typically a test
# worker), not the whole agent session -- systemd's default would stop the unit.
#
# --scope keeps the command in the foreground of the current terminal (TTY,
# signals, argv[0] for tmux window names all unchanged).
#
# Usage: agent-run <command> [args...]
# Env:   AGENT_RUN_MEMORY_HIGH (default 8G) -- per-session soft limit
#        AGENT_RUN_DISABLE=1                -- bypass, exec the command directly
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "usage: agent-run <command> [args...]" >&2
  exit 2
fi

# Already inside agents.slice (e.g. spawned by paseo, or a nested agent-run):
# don't nest scopes, just run.
if [[ ${AGENT_RUN_DISABLE:-0} == 1 ]] || grep -q '/agents\.slice/' /proc/self/cgroup 2>/dev/null; then
  exec "$@"
fi

# No reachable user manager (ssh without lingering session, containers, ...):
# degrade to an unlimited run instead of failing to start the agent.
if ! systemctl --user show-environment >/dev/null 2>&1; then
  exec "$@"
fi

exec systemd-run --user --scope --slice=agents.slice --quiet --collect \
  -p MemoryHigh="${AGENT_RUN_MEMORY_HIGH:-8G}" \
  -p OOMPolicy=continue \
  -- "$@"
