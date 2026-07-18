# Copilot Instructions

This is a **Nix Home Manager** configuration repository managing dotfiles and packages across multiple Linux machines via a single flake.

## Applying Changes

```bash
# Apply config for the current host (auto-detects hostname)
hm_switch

# Apply for a specific host manually
home-manager switch --flake .#<HOST> -b bckp
```

Defined hosts: `DPC0155` (Ubuntu/work), `HERA` (Linux), `NYX` (Manjaro/desktop).

## Architecture

```
flake.nix               # Entry point — wires hosts to module stacks
environments/
  base.nix              # Packages and dotfiles shared by ALL hosts
  <host>.nix            # Host-specific additions/overrides
system/
  ubuntu.nix            # Ubuntu-specific: nixGL wrapping, GTK theme, PATH fixup
  manjaro.nix           # Manjaro-specific: same pattern, no nixGL
dotfiles/               # Actual config files symlinked into $HOME
themes/
  posh/                 # oh-my-posh themes (active: pure.omp.json)
  k9s/skins/            # k9s color skins
scripts/
  agent-sandbox.sh      # bubblewrap sandbox for AI agents
```

The module stack per host is `base.nix` + `system/<os>.nix` (optional) + `environments/<host>.nix`, composed in `flake.nix`.

## Key Conventions

### nixGL wrapping (Ubuntu only)
Electron apps (obsidian, vscode, teams-for-linux) crash on Ubuntu without GPU API wrapping. `system/ubuntu.nix` exposes an `ubuntuElectron` module argument containing `nixGLCommand` and `wrapCommandPackage`. Both `base.nix` and environment files accept `ubuntuElectron ? null` and conditionally wrap packages:

```nix
{ config, lib, pkgs, ubuntuElectron ? null, ... }:
let
  myPkg = if ubuntuElectron == null then pkgs.myapp
          else ubuntuElectron.wrapCommandPackage { ... };
```

Non-Ubuntu hosts pass `null` implicitly since `system/ubuntu.nix` is not in their module stack.

### Priority overrides
- `lib.mkForce` in `base.nix` for dotfiles that must not be overridden by any environment.
- `lib.mkDefault` for files that environments may legitimately override (e.g., oh-my-posh theme).

### Dotfile management
All dotfiles live in `dotfiles/` and are declared in `base.nix` under `home.file`. They are symlinked into `$HOME` by Home Manager. To add a temporary/experimental snippet to `.bashrc` without modifying the managed file, put it in `~/.bashrc-additions` (sourced at the end of `.bashrc`).

### Adding packages
- **Shared across all machines** → `environments/base.nix` under `home.packages`
- **Host-specific** → the matching `environments/<host>.nix`
- **Unfree packages** → add to the `allowUnfreePredicate` list in `base.nix`

### Xremap (keyboard remapping)
Config lives in `dotfiles/xremap.config.yaml` and is read inline into the flake. To reload after editing:

```bash
reload-hotkeys   # or: systemctl --user restart xremap.service
```

## AI Agent Sandbox

Default shell behavior (from `dotfiles/.bash_aliases`):

```bash
copilot                 # host copilot (no sandbox)
codex                   # host codex (no sandbox)
junie                   # host junie (no sandbox)
copilot-sandboxed       # sandboxed + --allow-all
codex-sandboxed         # sandboxed + --dangerously-bypass-approvals-and-sandbox
junie-sandboxed         # sandboxed + --brave
```

Additional helpers:

```bash
sbx                      # open sandboxed bash in $PWD
sbx-copilot              # run GitHub Copilot CLI sandboxed
sbx-copilot-yolo         # copilot --allow-all
sbx-codex                # run Codex sandboxed
sbx-codex-yolo           # codex --full-auto
sbx-nonet [cmd...]       # any command, no network access
```

The sandbox (implemented in `scripts/agent-sandbox.sh`) uses `bwrap` to isolate the agent: it mounts the project at `/workspace`, uses a temporary `/home/user`, and supports network isolation via `--unshare-net` / `NO_NET=1`.

Persistent agent settings from sandbox sessions (for example model/default selection) are synced to:

```bash
~/.config/agent-sandbox/codex/config.toml
~/.config/agent-sandbox/copilot/config.json
```

On Ubuntu 24.04+, AppArmor must allow `bwrap` user namespaces:

```bash
sudo cp ~/.config/home-manager/scripts/bwrap-apparmor.profile /etc/apparmor.d/bwrap
sudo apparmor_parser -r /etc/apparmor.d/bwrap
sudo aa-status | rg bwrap
```
