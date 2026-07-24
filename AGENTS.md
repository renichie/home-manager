# Repository Guidelines

## Project Structure & Module Organization
This repository manages a Home Manager setup with Nix flakes. `flake.nix` is the entry point and defines host targets such as `DPC0155`, `HERA`, and `NYX`. Shared configuration lives in `environments/base.nix`, while host-specific overlays live in `environments/*.nix` and `system/*.nix`. Shell, Git, Vim, tmux, and app config files are stored in `dotfiles/`. Utility scripts live in `scripts/`, documentation in `docs/`, and visual assets in `themes/`.

## Build, Test, and Development Commands
Use Home Manager commands from the repo root:

```bash
home-manager switch --flake .#HERA -b bckp
home-manager build --flake .#DPC0155
```

`switch` applies a profile to the active machine and keeps a backup. `build` is the safest validation step for changes because it evaluates the flake without replacing the active profile. If your shell config is active, `hm_switch` selects the flake from the hostname automatically.

**Agents: never run `home-manager switch` / `hm_switch` yourself.** Only validate with `home-manager build --flake .#<TARGET>` and leave applying the profile to the user — switching replaces the live home environment and is the user's decision.

## Coding Style & Naming Conventions
Keep Nix files concise and consistent with the existing style: two-space indentation, grouped sections, and trailing semicolons on attributes. Name environment files after the host or scope they configure, for example `dpc0155.nix` or `desktop.hyprland.nix`. Shell code in `dotfiles/.bashrc` and `scripts/*.sh` should favor clear function names, minimal side effects, and brief comments only where behavior is non-obvious.

## Testing Guidelines
There is no dedicated automated test suite in this repository. Validate Nix changes with `home-manager build --flake .#<TARGET>` before switching. For shell and dotfile changes, test the affected command directly after reloading or applying the profile. Document any manual verification steps in the PR when behavior is host-specific.

## Commit & Pull Request Guidelines
Recent history follows short, descriptive subjects, often in a Conventional Commit style such as `feat(sandbox): persist agent stats across sessions`. Prefer that format where it fits. Keep commits focused on one concern. PRs should include a concise summary, the flake target(s) affected, manual verification performed, and screenshots only when changing visible themes or UI-facing config.

## Security & Configuration Tips
Treat machine-specific values carefully. Do not hardcode secrets, tokens, or private paths into shared files. When editing sandbox-related behavior, review [docs/agent-sandboxing.md](/workspace/docs/agent-sandboxing.md) and keep defaults least-privileged.
