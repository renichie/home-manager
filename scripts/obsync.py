#!/usr/bin/env python3
"""
obsync - Obsidian Vault Settings Sync Tool
==========================================
Copies selected settings from a source vault to a target vault
using a feature whitelist. Each feature is self-contained.

Usage:
    obsync.py SOURCE TARGET [FEATURE ...] [options]
    obsync.py --list
    obsync.py --interactive SOURCE TARGET

Examples:
    obsync.py ~/vaults/main ~/vaults/work vim hotkeys theme
    obsync.py ~/vaults/main ~/vaults/work --all
    obsync.py ~/vaults/main ~/vaults/work plugin:dataview plugin:templater-obsidian
    obsync.py --list
"""

import argparse
import json
import shutil
import sys
from pathlib import Path


# ─────────────────────────────────────────────────────────────────────────────
# Feature registry
# Each feature is a dict with:
#   description  : human-readable explanation
#   tags         : list of category tags for grouping in --list
#   handler      : callable(src_obs, dst_obs, dry_run) -> list[str]  (log lines)
# ─────────────────────────────────────────────────────────────────────────────

FEATURES: dict = {}


def feature(fid: str, description: str, tags: list[str]):
    """Decorator to register a feature handler."""
    def decorator(fn):
        FEATURES[fid] = {
            "description": description,
            "tags": tags,
            "handler": fn,
        }
        return fn
    return decorator


# ─── Helpers ─────────────────────────────────────────────────────────────────

def read_json(path: Path) -> dict | list:
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {}


def write_json(path: Path, data, dry_run: bool) -> str:
    if not dry_run:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return f"  write  {path}"


def copy_file(src: Path, dst: Path, dry_run: bool) -> str:
    if not dry_run:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
    return f"  copy   {src}  →  {dst}"


def copy_dir(src: Path, dst: Path, dry_run: bool) -> list[str]:
    logs = []
    if not src.exists():
        return [f"  skip   {src}  (not found)"]
    if not dry_run:
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
    logs.append(f"  copydir {src}  →  {dst}")
    return logs


def merge_json_keys(src_path: Path, dst_path: Path, keys: list[str], dry_run: bool) -> list[str]:
    """Copy only specific top-level keys from src JSON into dst JSON."""
    src_data = read_json(src_path)
    dst_data = read_json(dst_path)
    if not src_data:
        return [f"  skip   {src_path}  (not found)"]
    for key in keys:
        if key in src_data:
            dst_data[key] = src_data[key]
    return [write_json(dst_path, dst_data, dry_run)]


def enable_community_plugin(plugin_id: str, dst_obs: Path, dry_run: bool) -> list[str]:
    """Ensure plugin_id is in community-plugins.json of the target vault."""
    cp_path = dst_obs / "community-plugins.json"
    enabled: list = read_json(cp_path) if cp_path.exists() else []
    if not isinstance(enabled, list):
        enabled = []
    if plugin_id not in enabled:
        enabled.append(plugin_id)
        return [write_json(cp_path, enabled, dry_run)]
    return [f"  skip   {plugin_id} already enabled in community-plugins.json"]


# ─── Feature handlers ─────────────────────────────────────────────────────────

@feature("vim",
         "Vim keybindings: enables vim mode in app.json, installs obsidian-vimrc-support plugin, copies .obsidian.vimrc",
         ["editing", "keybindings"])
def feat_vim(src_obs: Path, dst_obs: Path, dry_run: bool) -> list[str]:
    logs = ["[vim]"]
    src_vault = src_obs.parent
    dst_vault = dst_obs.parent

    # 1. Enable vimMode in app.json
    logs += merge_json_keys(src_obs / "app.json", dst_obs / "app.json", ["vimMode"], dry_run)

    # 2. Enable the vimrc-support community plugin
    plugin_id = "obsidian-vimrc-support"
    logs += enable_community_plugin(plugin_id, dst_obs, dry_run)

    # 3. Copy plugin folder if present
    src_plugin = src_obs / "plugins" / plugin_id
    dst_plugin = dst_obs / "plugins" / plugin_id
    if src_plugin.exists():
        logs += copy_dir(src_plugin, dst_plugin, dry_run)
    else:
        logs.append(f"  skip   plugin folder {src_plugin} not found — install manually")

    # 4. Copy .obsidian.vimrc
    vimrc = src_vault / ".obsidian.vimrc"
    if vimrc.exists():
        logs.append(copy_file(vimrc, dst_vault / ".obsidian.vimrc", dry_run))
    else:
        logs.append("  skip   .obsidian.vimrc not found in source vault root")

    return logs


@feature("theme",
         "Color theme: copies cssTheme + theme (dark/light) from appearance.json and the matching theme folder",
         ["appearance"])
def feat_theme(src_obs: Path, dst_obs: Path, dry_run: bool) -> list[str]:
    logs = ["[theme]"]
    src_app = read_json(src_obs / "appearance.json")
    theme_name = src_app.get("cssTheme", "")

    # Merge only theme keys
    logs += merge_json_keys(
        src_obs / "appearance.json",
        dst_obs / "appearance.json",
        ["cssTheme", "theme"],
        dry_run,
    )

    # Copy theme folder
    if theme_name:
        src_theme_dir = src_obs / "themes" / theme_name
        dst_theme_dir = dst_obs / "themes" / theme_name
        logs += copy_dir(src_theme_dir, dst_theme_dir, dry_run)
    else:
        logs.append("  info   no community theme set (using default Obsidian theme)")

    return logs


@feature("appearance",
         "Full appearance settings: accent color, font size, native menus, line width, and more (includes theme + snippets list)",
         ["appearance"])
def feat_appearance(src_obs: Path, dst_obs: Path, dry_run: bool) -> list[str]:
    logs = ["[appearance]"]
    src_data = read_json(src_obs / "appearance.json")
    if not src_data:
        return logs + ["  skip   appearance.json not found in source"]

    # Copy whole appearance.json
    dst_obs.mkdir(parents=True, exist_ok=True)
    logs.append(write_json(dst_obs / "appearance.json", src_data, dry_run))

    # Also copy all referenced themes
    for theme_name in _list_themes(src_obs):
        src_t = src_obs / "themes" / theme_name
        dst_t = dst_obs / "themes" / theme_name
        logs += copy_dir(src_t, dst_t, dry_run)

    return logs


def _list_themes(obs: Path) -> list[str]:
    themes_dir = obs / "themes"
    if themes_dir.exists():
        return [d.name for d in themes_dir.iterdir() if d.is_dir()]
    return []


@feature("snippets",
         "CSS snippets: copies all CSS files from .obsidian/snippets/ and preserves the enabled-snippets list",
         ["appearance"])
def feat_snippets(src_obs: Path, dst_obs: Path, dry_run: bool) -> list[str]:
    logs = ["[snippets]"]
    src_snippets = src_obs / "snippets"
    dst_snippets = dst_obs / "snippets"

    if not src_snippets.exists():
        return logs + ["  skip   no snippets folder in source"]

    if not dry_run:
        dst_snippets.mkdir(parents=True, exist_ok=True)

    for css_file in src_snippets.glob("*.css"):
        logs.append(copy_file(css_file, dst_snippets / css_file.name, dry_run))

    # Preserve enabledCssSnippets list in appearance.json
    logs += merge_json_keys(
        src_obs / "appearance.json",
        dst_obs / "appearance.json",
        ["enabledCssSnippets"],
        dry_run,
    )
    return logs


@feature("hotkeys",
         "Custom keyboard shortcuts (hotkeys.json)",
         ["keybindings"])
def feat_hotkeys(src_obs: Path, dst_obs: Path, dry_run: bool) -> list[str]:
    logs = ["[hotkeys]"]
    src_path = src_obs / "hotkeys.json"
    if not src_path.exists():
        return logs + ["  skip   hotkeys.json not found in source"]
    dst_obs.mkdir(parents=True, exist_ok=True)
    logs.append(copy_file(src_path, dst_obs / "hotkeys.json", dry_run))
    return logs


@feature("core-plugins",
         "Enabled/disabled built-in Obsidian plugins (daily notes, backlinks, canvas, etc.)",
         ["plugins"])
def feat_core_plugins(src_obs: Path, dst_obs: Path, dry_run: bool) -> list[str]:
    logs = ["[core-plugins]"]
    src_path = src_obs / "core-plugins.json"
    if not src_path.exists():
        return logs + ["  skip   core-plugins.json not found in source"]
    logs.append(copy_file(src_path, dst_obs / "core-plugins.json", dry_run))
    return logs


@feature("community-plugins",
         "All enabled community plugins: copies community-plugins.json and every plugin folder",
         ["plugins"])
def feat_community_plugins(src_obs: Path, dst_obs: Path, dry_run: bool) -> list[str]:
    logs = ["[community-plugins]"]
    src_cp = src_obs / "community-plugins.json"
    if not src_cp.exists():
        return logs + ["  skip   community-plugins.json not found in source"]

    enabled: list = json.loads(src_cp.read_text())
    logs.append(copy_file(src_cp, dst_obs / "community-plugins.json", dry_run))

    for pid in enabled:
        src_plugin = src_obs / "plugins" / pid
        dst_plugin = dst_obs / "plugins" / pid
        if src_plugin.exists():
            logs += copy_dir(src_plugin, dst_plugin, dry_run)
        else:
            logs.append(f"  skip   plugin folder '{pid}' not in source (install manually)")

    return logs


@feature("daily-notes",
         "Daily notes settings: folder, template path, date format, autorun (daily-notes.json)",
         ["workflow"])
def feat_daily_notes(src_obs: Path, dst_obs: Path, dry_run: bool) -> list[str]:
    logs = ["[daily-notes]"]
    src_path = src_obs / "daily-notes.json"
    if not src_path.exists():
        return logs + ["  skip   daily-notes.json not found in source"]
    logs.append(copy_file(src_path, dst_obs / "daily-notes.json", dry_run))
    return logs


@feature("templates",
         "Templates folder setting (templates.json)",
         ["workflow"])
def feat_templates(src_obs: Path, dst_obs: Path, dry_run: bool) -> list[str]:
    logs = ["[templates]"]
    src_path = src_obs / "templates.json"
    if not src_path.exists():
        return logs + ["  skip   templates.json not found in source"]
    logs.append(copy_file(src_path, dst_obs / "templates.json", dry_run))
    return logs


@feature("graph",
         "Graph view settings: colors, forces, node/link sizes, display options (graph.json)",
         ["appearance", "workflow"])
def feat_graph(src_obs: Path, dst_obs: Path, dry_run: bool) -> list[str]:
    logs = ["[graph]"]
    src_path = src_obs / "graph.json"
    if not src_path.exists():
        return logs + ["  skip   graph.json not found in source"]
    logs.append(copy_file(src_path, dst_obs / "graph.json", dry_run))
    return logs


@feature("app-settings",
         "Core app behavior: markdown link format, attachment folder, tab size, line length, spellcheck, etc. (app.json)",
         ["editing", "workflow"])
def feat_app_settings(src_obs: Path, dst_obs: Path, dry_run: bool) -> list[str]:
    logs = ["[app-settings]"]
    src_path = src_obs / "app.json"
    if not src_path.exists():
        return logs + ["  skip   app.json not found in source"]
    # Copy everything except vimMode (use the 'vim' feature for that)
    src_data = read_json(src_path)
    src_data.pop("vimMode", None)
    dst_data = read_json(dst_obs / "app.json")
    dst_data.update(src_data)
    logs.append(write_json(dst_obs / "app.json", dst_data, dry_run))
    return logs


@feature("bookmarks",
         "Bookmarked files, searches, and headings (bookmarks.json)",
         ["workflow"])
def feat_bookmarks(src_obs: Path, dst_obs: Path, dry_run: bool) -> list[str]:
    logs = ["[bookmarks]"]
    src_path = src_obs / "bookmarks.json"
    if not src_path.exists():
        return logs + ["  skip   bookmarks.json not found in source"]
    logs.append(copy_file(src_path, dst_obs / "bookmarks.json", dry_run))
    return logs


@feature("canvas",
         "Canvas default settings (canvas.json)",
         ["workflow"])
def feat_canvas(src_obs: Path, dst_obs: Path, dry_run: bool) -> list[str]:
    logs = ["[canvas]"]
    src_path = src_obs / "canvas.json"
    if not src_path.exists():
        return logs + ["  skip   canvas.json not found in source"]
    logs.append(copy_file(src_path, dst_obs / "canvas.json", dry_run))
    return logs


@feature("backlink",
         "Backlinks panel settings (backlink.json)",
         ["workflow"])
def feat_backlink(src_obs: Path, dst_obs: Path, dry_run: bool) -> list[str]:
    logs = ["[backlink]"]
    src_path = src_obs / "backlink.json"
    if not src_path.exists():
        return logs + ["  skip   backlink.json not found in source"]
    logs.append(copy_file(src_path, dst_obs / "backlink.json", dry_run))
    return logs


@feature("page-preview",
         "Hover page preview settings (page-preview.json)",
         ["workflow"])
def feat_page_preview(src_obs: Path, dst_obs: Path, dry_run: bool) -> list[str]:
    logs = ["[page-preview]"]
    src_path = src_obs / "page-preview.json"
    if not src_path.exists():
        return logs + ["  skip   page-preview.json not found in source"]
    logs.append(copy_file(src_path, dst_obs / "page-preview.json", dry_run))
    return logs


@feature("command-palette",
         "Pinned and hidden commands in the command palette (command-palette.json)",
         ["workflow"])
def feat_command_palette(src_obs: Path, dst_obs: Path, dry_run: bool) -> list[str]:
    logs = ["[command-palette]"]
    src_path = src_obs / "command-palette.json"
    if not src_path.exists():
        return logs + ["  skip   command-palette.json not found in source"]
    logs.append(copy_file(src_path, dst_obs / "command-palette.json", dry_run))
    return logs


# ─── Dynamic plugin: feature ──────────────────────────────────────────────────

def handle_single_plugin(plugin_id: str, src_obs: Path, dst_obs: Path, dry_run: bool) -> list[str]:
    """Copy a single plugin by ID and enable it in community-plugins.json."""
    logs = [f"[plugin:{plugin_id}]"]
    src_plugin = src_obs / "plugins" / plugin_id
    if not src_plugin.exists():
        return logs + [f"  skip   plugin folder '{plugin_id}' not found in source"]

    dst_plugin = dst_obs / "plugins" / plugin_id
    logs += copy_dir(src_plugin, dst_plugin, dry_run)
    logs += enable_community_plugin(plugin_id, dst_obs, dry_run)
    return logs


# ─── CLI ──────────────────────────────────────────────────────────────────────

SENSIBLE_DEFAULTS = [
    "vim",
    "theme",
    "hotkeys",
    "snippets",
    "core-plugins",
    "community-plugins",
    "app-settings",
]

TAG_ORDER = ["appearance", "editing", "keybindings", "plugins", "workflow"]


def print_feature_list():
    by_tag: dict[str, list] = {t: [] for t in TAG_ORDER}
    for fid, meta in FEATURES.items():
        for tag in meta["tags"]:
            by_tag.setdefault(tag, []).append((fid, meta["description"]))

    print("obsync — available features\n")
    for tag in TAG_ORDER:
        entries = by_tag.get(tag, [])
        if not entries:
            continue
        print(f"  {'─' * 60}")
        print(f"  {tag.upper()}")
        print(f"  {'─' * 60}")
        for fid, desc in entries:
            marker = " *" if fid in SENSIBLE_DEFAULTS else "  "
            print(f"{marker} {fid:<22} {desc}")
        print()

    print("  plugin:<id>            Copy a single community plugin by its folder name")
    print()
    print(f"  * = included in --sensible  ({', '.join(SENSIBLE_DEFAULTS)})")
    print()
    print("  Special flags:")
    print("    --all          Copy all features above")
    print("    --sensible     Copy the starred features")
    print("    --dry-run      Show what would be copied without making changes")
    print("    --interactive  Prompt for each feature interactively")


def interactive_select(src_obs: Path, dst_obs: Path) -> list[str]:
    print("\nobsync — interactive feature selection")
    print(f"  source: {src_obs.parent}")
    print(f"  target: {dst_obs.parent}")
    print()
    selected = []
    for fid, meta in FEATURES.items():
        default = "y" if fid in SENSIBLE_DEFAULTS else "n"
        prompt = f"  [{default.upper()}/{('n' if default == 'y' else 'Y')}] {fid}: {meta['description']}\n  > "
        try:
            answer = input(prompt).strip().lower() or default
        except (EOFError, KeyboardInterrupt):
            print("\nAborted.")
            sys.exit(1)
        if answer in ("y", "yes"):
            selected.append(fid)
    return selected


def resolve_features(requested: list[str]) -> list[str]:
    """Expand --all / --sensible tokens and validate feature names."""
    resolved = []
    errors = []
    for name in requested:
        if name == "--all" or name == "all":
            resolved.extend(FEATURES.keys())
        elif name == "--sensible" or name == "sensible":
            resolved.extend(SENSIBLE_DEFAULTS)
        elif name.startswith("plugin:"):
            resolved.append(name)
        elif name in FEATURES:
            resolved.append(name)
        else:
            errors.append(name)
    if errors:
        print(f"obsync: unknown feature(s): {', '.join(errors)}", file=sys.stderr)
        print("Run 'obsync.py --list' to see available features.", file=sys.stderr)
        sys.exit(1)
    # deduplicate preserving order
    seen = set()
    return [f for f in resolved if not (f in seen or seen.add(f))]


def run_features(features: list[str], src_obs: Path, dst_obs: Path, dry_run: bool):
    if dry_run:
        print("obsync [DRY RUN] — no files will be modified\n")
    else:
        print("obsync — copying settings\n")

    print(f"  source: {src_obs.parent}")
    print(f"  target: {dst_obs.parent}")
    print()

    for fid in features:
        if fid.startswith("plugin:"):
            plugin_id = fid[len("plugin:"):]
            logs = handle_single_plugin(plugin_id, src_obs, dst_obs, dry_run)
        else:
            logs = FEATURES[fid]["handler"](src_obs, dst_obs, dry_run)
        for line in logs:
            print(line)
        print()

    if dry_run:
        print("Dry run complete. Use without --dry-run to apply changes.")
    else:
        print("Done.")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="obsync.py",
        description="Copy Obsidian settings from one vault to another using a feature whitelist.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
features (use --list for full descriptions):
  vim              hotkeys        snippets       theme
  appearance       core-plugins   community-plugins
  daily-notes      templates      graph          app-settings
  bookmarks        canvas         backlink       page-preview
  command-palette  plugin:<id>

special values:
  all              select all features
  sensible         select the recommended subset

examples:
  %(prog)s ~/main ~/work vim hotkeys theme
  %(prog)s ~/main ~/work sensible --dry-run
  %(prog)s ~/main ~/work plugin:dataview plugin:templater-obsidian
  %(prog)s --interactive ~/main ~/work
  %(prog)s --list
        """,
    )
    p.add_argument("--list", "-l", action="store_true", help="List all available features and exit")
    p.add_argument("--interactive", "-i", action="store_true", help="Interactively select features to copy")
    p.add_argument("--dry-run", "-n", action="store_true", help="Show what would happen without making changes")
    p.add_argument("source", nargs="?", metavar="SOURCE", help="Path to the source vault")
    p.add_argument("target", nargs="?", metavar="TARGET", help="Path to the target vault")
    p.add_argument("features", nargs="*", metavar="FEATURE", help="Features to copy (or 'all' / 'sensible')")
    return p


def main():
    parser = build_parser()
    args = parser.parse_args()

    if args.list:
        print_feature_list()
        sys.exit(0)

    if not args.source or not args.target:
        parser.print_help()
        sys.exit(0)

    src_vault = Path(args.source).expanduser().resolve()
    dst_vault = Path(args.target).expanduser().resolve()

    for vault, label in [(src_vault, "source"), (dst_vault, "target")]:
        if not vault.is_dir():
            print(f"obsync: {label} vault not found: {vault}", file=sys.stderr)
            sys.exit(1)

    src_obs = src_vault / ".obsidian"
    dst_obs = dst_vault / ".obsidian"

    if not src_obs.is_dir():
        print(f"obsync: no .obsidian folder in source vault: {src_vault}", file=sys.stderr)
        sys.exit(1)

    if args.interactive:
        features = interactive_select(src_obs, dst_obs)
        if not features:
            print("No features selected.")
            sys.exit(0)
    elif args.features:
        features = resolve_features(args.features)
    else:
        print("obsync: no features specified. Use --list to see options or --interactive to select.\n")
        parser.print_usage()
        sys.exit(1)

    run_features(features, src_obs, dst_obs, args.dry_run)


if __name__ == "__main__":
    main()
