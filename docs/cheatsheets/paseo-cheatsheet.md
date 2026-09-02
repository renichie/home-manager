# Paseo Cheatsheet

## Daemon (systemd, DPC0155)

```bash
systemctl --user status paseo.service
systemctl --user restart paseo.service
systemctl --user stop paseo.service
journalctl --user -u paseo.service -f
tail -f ~/.paseo/daemon.log
```

## Daemon (paseo)

```bash
paseo status
paseo daemon status
paseo daemon restart
paseo daemon stop
paseo daemon reload
paseo daemon pair
paseo daemon set-password
paseo start --foreground --listen 127.0.0.1:6767 --web-ui --no-relay
paseo onboard
```

## Web UI

```bash
xdg-open http://127.0.0.1:6767
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:6767/
```

## Agenten starten

```bash
paseo run "<prompt>"
paseo run -d "<prompt>"
paseo run --provider claude "<prompt>"
paseo run --provider codex/gpt-5.4 "<prompt>"
paseo run --model claude-sonnet-4-20250514 "<prompt>"
paseo run --mode plan "<prompt>"
paseo run --title "<titel>" "<prompt>"
paseo run --cwd ~/.config/home-manager "<prompt>"
paseo run --env KEY=value "<prompt>"
paseo run --image ./shot.png "<prompt>"
```

## Agenten im Worktree

```bash
paseo run --new-workspace worktree --worktree-mode branch-off --new-branch feat/x "<prompt>"
paseo run --new-workspace worktree --worktree-mode branch-off --base main --new-branch feat/x "<prompt>"
paseo run --new-workspace worktree --worktree-mode checkout-branch --branch feat/x "<prompt>"
paseo run --new-workspace worktree --worktree-mode checkout-pr --pr-number 42 "<prompt>"
paseo run --new-workspace local "<prompt>"
paseo run --workspace <workspace-id> "<prompt>"
```

## Agenten verwalten

```bash
paseo ls
paseo ls -a
paseo ls -g
paseo ls --json
paseo ls --label key=value
paseo inspect <id>
paseo attach <id>
paseo send <id> "<prompt>"
paseo send <id> --prompt-file ./task.md
paseo send <id> --no-wait "<prompt>"
paseo wait <id>
paseo wait <id> --timeout 600
paseo stop <id>
paseo stop --all
paseo stop --cwd ~/projekt
paseo archive <id>
paseo archive <id> --force
paseo delete <id>
paseo delete --all
```

## Logs

```bash
paseo logs <id>
paseo logs <id> -f
paseo logs <id> --tail 50
paseo logs <id> --filter tools
paseo logs <id> --filter text
paseo logs <id> --filter errors
paseo logs <id> --filter permissions
paseo logs <id> --since 2026-09-02T08:00:00Z
```

## Agent (erweitert)

```bash
paseo agent mode <id> <mode>
paseo agent reload <id>
paseo agent update <id>
paseo agent detach <id>
paseo agent open <id>
paseo import <session-id> --provider claude
paseo clone <owner/repo> --dir ~/workspace
```

## Permissions

```bash
paseo permit ls
paseo permit allow <agent>
paseo permit allow <agent> <req_id>
paseo permit deny <agent> <req_id>
```

## Provider

```bash
paseo provider ls
paseo provider models claude
paseo provider diagnostic claude
paseo provider diagnostic codex
```

## Projekte & Workspaces

```bash
paseo project ls
paseo project create ~/.config/home-manager
paseo project rename <project-id> "<name>"
paseo project delete <project-id>
paseo workspace ls
paseo workspace create
paseo workspace rename <workspace-id> "<titel>"
paseo workspace archive <workspace-id>
```

## Terminals

```bash
paseo terminal ls
paseo terminal create
paseo terminal capture <terminal-id>
paseo terminal send-keys <terminal-id> "<keys>"
paseo terminal kill <terminal-id>
```

## Scripts

```bash
paseo script ls
paseo script start <name>
paseo script stop <name>
```

## Schedules

```bash
paseo schedule ls
paseo schedule create --every 1h "<prompt>"
paseo schedule create --cron '0 7 * * 1-5' --timezone Europe/Berlin "<prompt>"
paseo schedule create --every 30m --run-now --max-runs 10 "<prompt>"
paseo schedule inspect <id>
paseo schedule logs <id>
paseo schedule pause <id>
paseo schedule resume <id>
paseo schedule run-once <id>
paseo schedule update <id>
paseo schedule delete <id>
```

## Remote-Daemon

```bash
paseo ls --host 192.168.1.10:6767
paseo ls --host tcp://truenas:6767
paseo ls --host ssh://bernd@hera
paseo run --host ssh://bernd@hera --cwd ~/projekt "<prompt>"
```

## Ausgabeformat

```bash
paseo ls --json
paseo -o json ls
paseo -o yaml ls
paseo -q ls
paseo --no-headers ls
paseo --no-color ls
```

## Plugins

```bash
paseo plugin ls
paseo plugin install <dir|git-url>
paseo plugin status
paseo plugin update <id>
paseo plugin enable <id>
paseo plugin disable <id>
paseo plugin logs <id>
paseo plugin remove <id>
```

## Nix / home-manager (dieses Repo)

```bash
home-manager build --flake .#DPC0155 --no-out-link
home-manager switch --flake .#DPC0155
git add pkgs/paseo
nix build --impure --no-link --print-out-paths --expr 'let f = builtins.getFlake (toString ./.); p = import f.inputs.nixpkgs { system = "x86_64-linux"; }; in p.callPackage ./pkgs/paseo { }'
```

## Version anheben

```bash
cd pkgs/paseo
npm install --package-lock-only --ignore-scripts @getpaseo/cli@<version>
nix run nixpkgs#prefetch-npm-deps -- package-lock.json
```
