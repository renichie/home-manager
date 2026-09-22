#!/usr/bin/env python3
"""Overview of AI agent quotas/credits across the providers used on this host.

Every provider is normalised to the same view: percent *remaining*, plus the
absolute remaining/total pair where the provider exposes one, the reset time,
and the scope the number applies to.

A provider only shows up if it looks configured on this machine (its auth file
or cache exists, or its CLI is on PATH) -- a host that only has Claude Code
never sees Copilot/Codex/JetBrains rows at all, rather than an "error" row for
tools that were simply never installed here.

Providers and where the numbers come from:

  copilot   GitHub Copilot premium interactions, via `gh api /copilot_internal/user`.
            Uses the gh token from the system keyring, so it follows whatever host
            `gh` is logged in to (here: a GHE enterprise). Live.

  codex     ChatGPT/Codex rate-limit windows, via the undocumented endpoint
            https://chatgpt.com/backend-api/wham/usage, authenticated with the
            OAuth access token the Codex CLI stores in ~/.codex/auth.json. Live,
            but the token is short-lived: running `codex` once refreshes it.
            Only reports percentages, no absolute counts.

  claude    Claude subscription utilization (the same numbers `/usage` shows
            in-session), via https://api.anthropic.com/api/oauth/usage with the
            OAuth token from ~/.claude/.credentials.json. Live, percentages only.
            Reports the 5h window, since that is the one that actually stops a
            session mid-flight; the 7d window rides along in parentheses next
            to it rather than as its own row. The endpoint rate-limits hard,
            see AI_CREDITS_TTL.

  junie     JetBrains AI credits. The live number comes from Junie CLI's own
            session logs (~/.junie/sessions/*/events.jsonl), which get a fresh
            balance appended after every completed model call regardless of
            whether an IDE is open. No network call. The total pool size comes
            from the IDE's cache at
            ~/.config/JetBrains/<IDE>/options/AIAssistantQuotaManager2.xml,
            which changes far less often than the balance does. If no Junie
            CLI session ever logged a balance, this falls back to that same
            IDE cache for the remaining figure too -- in which case it really
            is only a last-known value, not live.

  anthropic Anthropic API key throughput limits, from the anthropic-ratelimit-*
            response headers. There is no balance endpoint for a normal
            sk-ant-api key (the Admin API needs an sk-ant-admin key), and the
            headers only appear on a real /v1/messages call. That call is
            billable (a fraction of a cent), so this provider is opt-in via
            --probe-api and never runs during a background refresh.

Modes:
  ai-credits                 fetch everything live, print a table, update the cache
  ai-credits --json          same, but emit JSON
  ai-credits --refresh       fetch silently and update the cache (background use)
  ai-credits --prompt        print the cached one-liner, never touches the network

The cache lives in $XDG_CACHE_HOME/ai-credits.{json,prompt}. The .prompt file is
a pre-rendered string so the shell can read it with builtins only, without
paying for a Python startup on every prompt.
"""

from __future__ import annotations

import argparse
import datetime
import glob
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor

HOME = os.path.expanduser("~")
CACHE_DIR = os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache")
CACHE_JSON = os.path.join(CACHE_DIR, "ai-credits.json")
CACHE_PROMPT = os.path.join(CACHE_DIR, "ai-credits.prompt")
CACHE_BACKOFF = os.path.join(CACHE_DIR, "ai-credits.backoff.json")
# How long a last-known-good figure may stand in for a failed fetch. A quota
# only moves when the agent is used, so a slightly old number beats no number.
STALE_MAX = float(os.environ.get("AI_CREDITS_STALE_MAX", 3600))

HTTP_TIMEOUT = 8

# Thresholds on percent remaining, driving both table and prompt colour.
WARN_PCT = 30.0
CRIT_PCT = 10.0

RESET = "\033[0m"
DIM = "\033[2m"
# One palette for both renderers, so a severity looks identical in the table and
# in the prompt. Nord, matching themes/posh/pure.omp.json. "none" means "could
# not be read" and must stay visually distinct from a healthy quota.
PALETTE = {"ok": "#A3BE8C", "warn": "#EBCB8B", "crit": "#BF616A", "none": "#6C6C6C"}
OMP = PALETTE
ANSI = {
    key: "\033[38;2;{};{};{}m".format(*(int(hex_[i : i + 2], 16) for i in (1, 3, 5)))
    for key, hex_ in PALETTE.items()
}

DASH = "\u2014"
BAR_FULL, BAR_EMPTY = "\u25b0", "\u25b1"
# Cells in the table gauge and in the much narrower prompt gauge.
TABLE_CELLS = 10
PROMPT_CELLS = int(os.environ.get("AI_CREDITS_PROMPT_CELLS", "4"))
# Width-stable placeholder for a provider that could not be read, so the prompt
# does not jitter and an outage cannot be mistaken for an empty quota.
PROMPT_UNKNOWN = "\u00b7"


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------


def http_json(url: str, headers: dict[str, str]) -> tuple[int, dict | None, float]:
    """GET a JSON document. Returns (status, parsed_body_or_None, retry_after).

    retry_after is the server's Retry-After in seconds, 0 when absent.
    """
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            return resp.status, json.loads(resp.read() or b"null"), 0.0
    except urllib.error.HTTPError as exc:
        try:
            retry = float(exc.headers.get("Retry-After") or 0)
        except (TypeError, ValueError):
            retry = 0.0
        return exc.code, None, retry
    except Exception:
        return 0, None, 0.0


def backoff_left(key: str) -> float:
    """Seconds still to wait before hitting `key`'s endpoint again."""
    store = read_json(CACHE_BACKOFF) or {}
    return max(0.0, float(store.get(key) or 0) - time.time())


def set_backoff(key: str, seconds: float) -> None:
    store = read_json(CACHE_BACKOFF) or {}
    store[key] = time.time() + seconds
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        tmp = f"{CACHE_BACKOFF}.{os.getpid()}"
        with open(tmp, "w") as fh:
            json.dump(store, fh)
        os.replace(tmp, CACHE_BACKOFF)
    except OSError:
        pass


def read_json(path: str) -> dict | None:
    try:
        with open(path, "rb") as fh:
            return json.load(fh)
    except Exception:
        return None


def rel_time(epoch: float | None) -> str:
    """Render an absolute epoch as a short 'in 6d' / 'in 4h' / 'in 12m'."""
    if not epoch:
        return ""
    delta = epoch - time.time()
    if delta <= 0:
        return "now"
    if delta >= 86400:
        return f"in {delta / 86400:.0f}d"
    if delta >= 3600:
        return f"in {delta / 3600:.0f}h"
    return f"in {delta / 60:.0f}m"


def rel_age(epoch: float) -> str:
    """Render how long ago an epoch was, as '6d' / '4h' / '12m'."""
    delta = max(0.0, time.time() - epoch)
    if delta >= 86400:
        return f"{delta / 86400:.0f}d"
    if delta >= 3600:
        return f"{delta / 3600:.0f}h"
    return f"{delta / 60:.0f}m"


def reverse_lines(path: str, chunk_size: int = 65536):
    """Yield a text file's lines back to front, without loading it all into memory.

    Junie's session logs are JSON-Lines and can run to tens of megabytes; the
    only thing ever needed from them is the most recent match for something, so
    reading forward and keeping the last hit would mean scanning the whole file
    every time. This walks backwards in fixed-size chunks instead, stopping as
    soon as the caller has what it needs.
    """
    with open(path, "rb") as fh:
        fh.seek(0, os.SEEK_END)
        pos = fh.tell()
        trailing = b""
        while pos > 0:
            read_size = min(chunk_size, pos)
            pos -= read_size
            fh.seek(pos)
            chunk = fh.read(read_size) + trailing
            lines = chunk.split(b"\n")
            trailing = lines[0]
            for line in reversed(lines[1:]):
                if line:
                    yield line.decode("utf-8", "replace")
        if trailing:
            yield trailing.decode("utf-8", "replace")


def iso_to_epoch(value: str | None) -> float | None:
    if not value:
        return None
    text = value.replace("Z", "+00:00")
    try:
        return datetime.datetime.fromisoformat(text).timestamp()
    except ValueError:
        pass
    try:
        return time.mktime(time.strptime(text, "%Y-%m-%d"))
    except ValueError:
        return None


def group(value: float, decimals: int = 0) -> str:
    """Thousands-separated number, German style."""
    return f"{value:,.{decimals}f}".replace(",", "#").replace(".", ",").replace("#", ".")


def result(
    key: str,
    label: str,
    short: str,
    state: str,
    *,
    pct: float | None = None,
    remaining: float | None = None,
    total: float | None = None,
    reset: float | None = None,
    scope: str = "",
    note: str = "",
    in_prompt: bool = True,
) -> dict:
    """Uniform provider record.

    pct is always *percent remaining*, and remaining/total are absolute counts in
    the same direction. Providers that only expose percentages leave them None.
    state is 'ok' or 'error'; on error only `note` carries meaning. in_prompt is
    False for figures that are not a credit balance and would only add noise to
    the prompt.
    """
    return {
        "key": key,
        "label": label,
        "short": short,
        "state": state,
        "pct": pct,
        "remaining": remaining,
        "total": total,
        "reset": reset,
        "scope": scope,
        "note": note,
        "in_prompt": in_prompt,
        "fetched_at": time.time(),
        "stale": False,
    }


def gauge(pct: float, cells: int) -> str:
    """Render percent remaining as a bar.

    Rounds half up to the nearest cell: at the prompt's five-cell resolution,
    truncating would draw 35% as one cell out of five and 99% as four. One cell
    stays lit while anything at all is left, so an empty bar means empty rather
    than merely low — the colour already carries the "low" signal.
    """
    filled = 0 if pct <= 0 else max(1, min(cells, int(pct / 100 * cells + 0.5)))
    return BAR_FULL * filled + BAR_EMPTY * (cells - filled)


def severity(entry: dict) -> str:
    if entry["state"] != "ok" or entry["pct"] is None:
        return "none"
    if entry["pct"] < CRIT_PCT:
        return "crit"
    if entry["pct"] < WARN_PCT:
        return "warn"
    return "ok"


# --------------------------------------------------------------------------
# providers
# --------------------------------------------------------------------------


def fetch_copilot() -> dict:
    label, short = "Copilot", "cp"
    try:
        proc = subprocess.run(
            ["gh", "api", "/copilot_internal/user"],
            capture_output=True,
            text=True,
            timeout=HTTP_TIMEOUT + 4,
        )
    except FileNotFoundError:
        return result("copilot", label, short, "error", note="gh not installed")
    except subprocess.TimeoutExpired:
        return result("copilot", label, short, "error", note="gh timed out")
    if proc.returncode != 0:
        hint = proc.stderr.strip().splitlines()[-1] if proc.stderr.strip() else "gh api failed"
        return result("copilot", label, short, "error", note=hint[:80])

    body = json.loads(proc.stdout)
    quota = (body.get("quota_snapshots") or {}).get("premium_interactions") or {}
    reset = iso_to_epoch(body.get("quota_reset_date"))
    plan = body.get("copilot_plan")
    note = f"plan: {plan}" if plan else ""

    if quota.get("unlimited"):
        return result(
            "copilot", label, short, "ok",
            pct=100.0, reset=reset, scope="premium interactions (unlimited)", note=note,
        )
    return result(
        "copilot", label, short, "ok",
        pct=quota.get("percent_remaining"),
        remaining=quota.get("remaining"),
        total=quota.get("entitlement"),
        reset=reset,
        scope="premium interactions",
        note=note,
    )


def fetch_codex() -> dict:
    label, short = "Codex", "cx"
    auth = read_json(os.path.join(HOME, ".codex", "auth.json"))
    tokens = (auth or {}).get("tokens") or {}
    access, account = tokens.get("access_token"), tokens.get("account_id")
    if not access:
        return result("codex", label, short, "error", note="not logged in (run `codex login`)")

    status, body, retry_after = http_json(
        "https://chatgpt.com/backend-api/wham/usage",
        {"Authorization": f"Bearer {access}", "chatgpt-account-id": account or ""},
    )
    if status in (401, 403):
        return result("codex", label, short, "error", note="token expired (run `codex` once)")
    if status != 200 or not body:
        return result("codex", label, short, "error", note=f"HTTP {status or 'unreachable'}")

    windows = [
        win
        for name in ("primary_window", "secondary_window")
        if (win := (body.get("rate_limit") or {}).get(name))
    ]
    if not windows:
        return result("codex", label, short, "error", note="no rate limit data")

    # The binding constraint is whichever window is closest to exhaustion.
    tightest = max(windows, key=lambda w: w.get("used_percent") or 0)
    hours = (tightest.get("limit_window_seconds") or 0) / 3600
    span = f"{hours / 24:.0f}d" if hours >= 24 else f"{hours:.0f}h"

    notes = []
    plan = body.get("plan_type")
    if plan:
        notes.append(f"plan: {plan}")
    credits = body.get("credits") or {}
    if credits.get("unlimited"):
        notes.append("credits: unlimited")
    elif credits.get("balance") is not None:
        notes.append(f"credits: {credits['balance']}")

    return result(
        "codex", label, short, "ok",
        pct=100.0 - float(tightest.get("used_percent") or 0),
        reset=tightest.get("reset_at"),
        scope=f"{span} window",
        note=" \u00b7 ".join(notes),
    )


# Claude reports one quota per rate-limit window. Only the 5h window becomes
# this provider's pct/reset/severity, since that is the one that actually
# stops a session mid-flight; the 7d window is folded into the note instead of
# getting its own row, so it cannot be mistaken for the binding constraint.
def fetch_claude() -> dict:
    label, short = "Claude", "cc"
    creds = read_json(os.path.join(HOME, ".claude", ".credentials.json"))
    oauth = (creds or {}).get("claudeAiOauth") or {}
    token = oauth.get("accessToken")
    if not token:
        return result("claude", label, short, "error", note="not logged in (run `claude`)")

    # This endpoint rate-limits hard (429 with Retry-After around 260s) and the
    # prompt refreshes on every agent command, so honour the cooldown instead of
    # walking into it. Failing fast here lets collect() fall back to the last
    # good figure rather than blanking the segment.
    wait = backoff_left("claude")
    if wait:
        return result("claude", label, short, "error", note=f"rate limited, retry in {wait / 60:.0f}m")

    status, body, retry_after = http_json(
        "https://api.anthropic.com/api/oauth/usage",
        {
            "Authorization": f"Bearer {token}",
            "anthropic-version": "2023-06-01",
            "anthropic-beta": "oauth-2025-04-20",
        },
    )
    if status == 429:
        set_backoff("claude", retry_after or 300)
        return result("claude", label, short, "error", note="rate limited")
    if status in (401, 403):
        return result("claude", label, short, "error", note="token expired (run `claude` once)")
    if status != 200 or not body:
        return result("claude", label, short, "error", note=f"HTTP {status or 'unreachable'}")

    five = body.get("five_hour") or {}
    seven = body.get("seven_day") or {}
    util5 = five.get("utilization")
    if util5 is None:
        return result("claude", label, short, "error", note="no usage data")

    notes = []
    plan = oauth.get("subscriptionType")
    if plan:
        notes.append(f"plan: {plan}")
    util7 = seven.get("utilization")
    if util7 is not None:
        notes.append(f"7d left: {100.0 - float(util7):.0f}%")

    return result(
        "claude", label, short, "ok",
        pct=100.0 - float(util5),
        reset=iso_to_epoch(five.get("resets_at")),
        scope="5h window",
        note=" \u00b7 ".join(notes),
    )


# The IDE's XML and Junie CLI's session logs both store quota in the same
# internal raw unit, not the "credits" the IDE's own panels (Junie's License &
# quota tab, the AI Assistant balance) show. Empirically the ratio is fixed at
# 128000 raw units per credit -- checked by comparing the XML's available/
# maximum against the credit balance Junie displayed at the same instant
# (6,370,803.36 raw / 128000 = 49.77, matching the panel to the cent). Without
# dividing out, the table shows numbers a thousand times too large.
JUNIE_RAW_UNITS_PER_CREDIT = 128000
# How many of the most-recently-touched session logs to check for a live
# balance before giving up on it. Bounds the work on hosts with a long Junie
# history; a session nobody has touched in days cannot hold the newest figure.
JUNIE_SESSION_SCAN_LIMIT = 8
# How far to walk backwards into a single session log looking for a quota
# entry before moving on. Long stretches of pure chat/tool-call events without
# a completed model call are normal; this just stops a pathological file (one
# that never logged a quota at all) from being read in full every refresh.
JUNIE_LINE_SCAN_LIMIT = 20000


def _junie_xml_info() -> dict | None:
    """Total credit pool (plus a last-known remaining/mtime as fallback), read
    from AI Assistant's own cache. This file is only rewritten while an IDE is
    running, so `remaining`/`mtime` here can be badly stale if quota was spent
    through Junie CLI instead -- kept only as the total-pool source and as a
    fallback for hosts with no Junie CLI session logs to read a live balance
    from at all.
    """
    pattern = os.path.join(
        HOME, ".config", "JetBrains", "*", "options", "AIAssistantQuotaManager2.xml"
    )
    files = sorted(glob.glob(pattern), key=os.path.getmtime)
    if not files:
        return None
    path = files[-1]
    try:
        root = ET.parse(path).getroot()
        # The IDE stores JSON inside XML attributes; ElementTree unescapes for us.
        options = {
            opt.get("name"): json.loads(opt.get("value") or "null") for opt in root.iter("option")
        }
        quota = options.get("quotaInfo") or {}
        tariff = quota.get("tariffQuota") or quota
        # Careful: "current" is the amount *consumed*, "available" is what is
        # left. They always sum to "maximum", and "current" grows as spent.
        total = float(tariff["maximum"])
        remaining = float(tariff["available"])
    except Exception:
        return None
    if total <= 0:
        return None
    return {
        "total": total / JUNIE_RAW_UNITS_PER_CREDIT,
        "remaining": remaining / JUNIE_RAW_UNITS_PER_CREDIT,
        "source": path.split(os.sep)[-3],
        "mtime": os.path.getmtime(path),
        "next_refill": iso_to_epoch((options.get("nextRefill") or {}).get("next")),
    }


def _completion_quota(event: object) -> tuple[float, float] | None:
    """Dig a `completion.quota.balanceLeft` (raw units) + `endedAtMs` out of one
    decoded Junie session-log line, wherever it is nested in that event's shape.
    """
    if isinstance(event, dict):
        completion = event.get("completion")
        if isinstance(completion, dict):
            quota = completion.get("quota")
            if isinstance(quota, dict) and "balanceLeft" in quota:
                try:
                    return float(completion.get("endedAtMs") or 0), float(quota["balanceLeft"])
                except (TypeError, ValueError):
                    pass
        for value in event.values():
            found = _completion_quota(value)
            if found:
                return found
    elif isinstance(event, list):
        for value in event:
            found = _completion_quota(value)
            if found:
                return found
    return None


def _junie_live_balance() -> tuple[float, float, str] | None:
    """Most recent credit balance Junie CLI logged after finishing a model call,
    across every session on this host (started from the IDE or the CLI, does
    not matter -- both append to the same session log format). Updates on every
    completion, so it stays live even while no IDE is open. Returns
    (credits_remaining, ended_at_epoch, session_name), or None if nothing
    turned up within the scan limits above.
    """
    pattern = os.path.join(HOME, ".junie", "sessions", "*", "events.jsonl")
    files = sorted(glob.glob(pattern), key=os.path.getmtime, reverse=True)
    best = None
    for path in files[:JUNIE_SESSION_SCAN_LIMIT]:
        try:
            for scanned, line in enumerate(reverse_lines(path), start=1):
                if scanned > JUNIE_LINE_SCAN_LIMIT:
                    break
                if "balanceLeft" not in line:
                    continue
                try:
                    event = json.loads(line)
                except (json.JSONDecodeError, ValueError):
                    continue
                found = _completion_quota(event)
                if not found:
                    continue
                ended_ms, raw = found
                ended_at = ended_ms / 1000
                if best is None or ended_at > best[1]:
                    session = os.path.basename(os.path.dirname(path))
                    best = (raw / JUNIE_RAW_UNITS_PER_CREDIT, ended_at, session)
                break  # first match walking backwards is this file's latest
        except OSError:
            continue
    return best


def fetch_junie() -> dict:
    label, short = "JetBrains AI", "jb"
    xml_info = _junie_xml_info()
    live = _junie_live_balance()
    if live is None and xml_info is None:
        return result("junie", label, short, "error", note="no quota data found")

    total = xml_info["total"] if xml_info else None
    reset = xml_info["next_refill"] if xml_info else None

    if live is not None:
        remaining, ended_at, session = live
        notes = [f"live \u00b7 session {session}"]
        if time.time() - ended_at > 3600:
            notes.append(f"last completion {rel_age(ended_at)} ago")
    else:
        # No Junie CLI session log had a quota entry at all (e.g. this host
        # only ever used AI Assistant inside the IDE) -- fall back to the old
        # IDE-cache value, same as before this live path existed.
        remaining = xml_info["remaining"]
        notes = [f"from {xml_info['source']} (IDE cache, not live)"]
        if time.time() - xml_info["mtime"] > 3600:
            notes.append(f"cached {rel_age(xml_info['mtime'])} ago")

    return result(
        "junie", label, short, "ok",
        pct=remaining / total * 100 if total else None,
        remaining=remaining,
        total=total,
        reset=reset,
        scope="credits",
        note=" \u00b7 ".join(notes),
    )


def fetch_anthropic_api() -> dict:
    """Throughput limits for the raw API key. Costs one minimal billable request."""
    label, short = "Anthropic API", "an"
    auth = read_json(os.path.join(HOME, ".local", "share", "opencode", "auth.json")) or {}
    key = ((auth.get("anthropic") or {}).get("key")) or os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        return result("anthropic", label, short, "error", note="no API key found")

    model = os.environ.get("AI_CREDITS_PROBE_MODEL", "claude-haiku-4-5")
    payload = json.dumps(
        {"model": model, "max_tokens": 1, "messages": [{"role": "user", "content": "."}]}
    ).encode()
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=payload,
        method="POST",
        headers={
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            headers = dict(resp.headers)
    except urllib.error.HTTPError as exc:
        # A 429 still carries the rate limit headers, which is exactly the
        # interesting case; anything else without them is a real failure.
        headers = dict(exc.headers or {})
        if not headers.get("anthropic-ratelimit-tokens-limit"):
            return result("anthropic", label, short, "error", note=f"HTTP {exc.code}")
    except Exception as exc:
        return result("anthropic", label, short, "error", note=str(exc)[:80])

    try:
        total = float(headers["anthropic-ratelimit-tokens-limit"])
        remaining = float(headers["anthropic-ratelimit-tokens-remaining"])
    except (KeyError, ValueError):
        return result("anthropic", label, short, "error", note="no rate limit headers")

    return result(
        "anthropic", label, short, "ok",
        pct=remaining / total * 100 if total else None,
        remaining=remaining,
        total=total,
        reset=iso_to_epoch(headers.get("anthropic-ratelimit-tokens-reset")),
        scope="tokens/min",
        note="throughput only, not spend",
        in_prompt=False,
    )


# --------------------------------------------------------------------------
# collection + rendering
# --------------------------------------------------------------------------


def keep_last_good(entry: dict, previous: dict[str, dict]) -> dict:
    """Substitute the previous good reading for a failed fetch.

    A failed fetch says nothing about the quota, so blanking the segment throws
    away the only information we have. The stand-in is refused once it is older
    than STALE_MAX, or once its own reset time has passed -- past that point the
    window has rolled over and the number is provably wrong rather than merely
    old.
    """
    if entry["state"] == "ok":
        return entry
    old = previous.get(entry["key"])
    if not old or old.get("state") != "ok" or old.get("pct") is None:
        return entry
    age = time.time() - (old.get("fetched_at") or 0)
    if age > STALE_MAX or (old.get("reset") and old["reset"] < time.time()):
        return entry
    revived = dict(old)
    revived["stale"] = True
    notes = [n for n in (old.get("note") or "").split(" \u00b7 ") if n and not n.startswith("cached ")]
    notes.append(f"cached {rel_age(old['fetched_at'])} ago, {entry['note']}")
    revived["note"] = " \u00b7 ".join(notes)
    return revived


def collect(probe_api: bool) -> dict:
    # Detection over always-firing: a machine that only has Claude Code should
    # never see "error" rows for Copilot/Codex/JetBrains, it should see nothing
    # for them, same as if the option had never existed on this host.
    candidates = [
        (shutil.which("gh") is not None, fetch_copilot),
        (os.path.exists(os.path.join(HOME, ".codex", "auth.json")), fetch_codex),
        (os.path.exists(os.path.join(HOME, ".claude", ".credentials.json")), fetch_claude),
        (bool(glob.glob(os.path.join(
            HOME, ".config", "JetBrains", "*", "options", "AIAssistantQuotaManager2.xml"
        )) or glob.glob(os.path.join(HOME, ".junie", "sessions", "*", "events.jsonl"))), fetch_junie),
    ]
    fetchers = [fn for installed, fn in candidates if installed]
    if probe_api:
        fetchers.append(fetch_anthropic_api)
    if not fetchers:
        return {"updated_at": int(time.time()), "providers": []}
    with ThreadPoolExecutor(max_workers=len(fetchers)) as pool:
        results = pool.map(lambda fn: fn(), fetchers)
        # A fetcher may report several independent quotas, so it is allowed to
        # return a list instead of a single dict.
        entries = [e for r in results for e in (r if isinstance(r, list) else [r])]
    previous = {e["key"]: e for e in (read_json(CACHE_JSON) or {}).get("providers", [])}
    entries = [keep_last_good(e, previous) for e in entries]
    return {"updated_at": int(time.time()), "providers": entries}


def render_prompt(data: dict) -> str:
    """One-liner for oh-my-posh: a gauge of remaining quota per provider."""
    chunks = []
    for entry in data["providers"]:
        if not entry.get("in_prompt", True):
            continue
        if entry["state"] != "ok" or entry["pct"] is None:
            bar = PROMPT_UNKNOWN * PROMPT_CELLS
        else:
            bar = gauge(entry["pct"], PROMPT_CELLS)
        colour = OMP[severity(entry)]
        text = f"{entry['short']} {bar}"
        chunks.append(f"<{colour}>{text}</>" if colour else text)
    return " ".join(chunks)


def render_table(data: dict, colour: bool) -> str:
    def paint(text: str, code: str) -> str:
        return f"{code}{text}{RESET}" if colour and code else text

    rows = []
    for entry in data["providers"]:
        if entry["state"] != "ok" or entry["pct"] is None:
            rows.append((entry, "", "", DASH, DASH, entry["note"] or "unavailable"))
            continue
        pct = entry["pct"]
        if entry["remaining"] is not None and entry["total"]:
            # Junie's credits are fractional (e.g. 49.77 of 140.62); everything
            # else here is a whole-number entitlement, so only credits need decimals.
            decimals = 2 if entry["key"] == "junie" else 0
            absolute = f"{group(entry['remaining'], decimals)} / {group(entry['total'], decimals)}"
        else:
            absolute = DASH
        scope = entry["scope"]
        if entry["note"]:
            scope = f"{scope} ({entry['note']})" if scope else f"({entry['note']})"
        rows.append((
            entry,
            f"{pct:5.1f}%",
            gauge(pct, TABLE_CELLS),
            absolute,
            rel_time(entry["reset"]) or DASH,
            scope,
        ))

    headers = ("PROVIDER", "LEFT", "", "REMAINING / TOTAL", "RESET", "SCOPE")
    cells = [[e["label"], *rest] for e, *rest in rows]
    widths = [max(len(h), *(len(row[i]) for row in cells)) for i, h in enumerate(headers)]

    def line(values, codes=None):
        out = []
        last = len(values) - 1
        for i, value in enumerate(values):
            padded = value if i == last else value.ljust(widths[i])
            out.append(paint(padded, codes[i]) if codes and codes[i] else padded)
        return "  ".join(out).rstrip()

    lines = [paint(line(headers), DIM if colour else "")]
    for (entry, *rest), row in zip(rows, cells):
        code = ANSI[severity(entry)] if colour else ""
        lines.append(line(row, ["", code, code, "", "", DIM if colour else ""]))

    age = int(time.time()) - data["updated_at"]
    footer = f"updated {age}s ago" if age > 5 else "just now"
    lines.append(paint(f"\n{footer}", DIM if colour else ""))
    return "\n".join(lines)


def write_cache(data: dict) -> None:
    os.makedirs(CACHE_DIR, exist_ok=True)
    for path, payload in (
        (CACHE_JSON, json.dumps(data)),
        # "<epoch> <string>" so the shell can parse it with a single `read`.
        (CACHE_PROMPT, f"{data['updated_at']} {render_prompt(data)}"),
    ):
        tmp = f"{path}.tmp.{os.getpid()}"
        with open(tmp, "w") as fh:
            fh.write(payload + "\n")
        os.replace(tmp, path)


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="ai-credits",
        description="Show remaining AI agent quota across Copilot, Codex, Claude and JetBrains AI.",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--json", action="store_true", help="emit JSON instead of a table")
    mode.add_argument("--refresh", action="store_true", help="update the cache silently")
    mode.add_argument("--prompt", action="store_true", help="print the cached one-liner, no network")
    parser.add_argument(
        "--probe-api",
        action="store_true",
        help="also check the Anthropic API key rate limits (sends one minimal billable request)",
    )
    parser.add_argument("--no-color", action="store_true", help="disable ANSI colour")
    args = parser.parse_args()

    if args.prompt:
        data = read_json(CACHE_JSON)
        if data:
            print(render_prompt(data))
        return 0

    data = collect(probe_api=args.probe_api and not args.refresh)
    write_cache(data)

    if args.refresh:
        return 0
    if args.json:
        print(json.dumps(data, indent=2))
        return 0

    colour = not args.no_color and sys.stdout.isatty()
    print(render_table(data, colour))
    if not args.probe_api:
        hint = "Anthropic API key: use --probe-api (sends one minimal billable request)"
        print(f"{DIM}{hint}{RESET}" if colour else hint)
    return 0


if __name__ == "__main__":
    sys.exit(main())
