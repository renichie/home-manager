# AI Agent Sandboxing mit Bubblewrap

Dieses Setup isoliert KI-Coding-Agenten (GitHub Copilot CLI, OpenAI Codex, Claude Code, JetBrains Junie CLI) auf dem Linux-Desktop mit [bubblewrap](https://github.com/containers/bubblewrap) — demselben Sandboxing-Mechanismus, den Flatpak verwendet.

## Warum überhaupt sandboxen?

KI-Agenten führen Shellbefehle aus, lesen und schreiben Dateien und sprechen mit externen APIs. Wenn man sie ohne Einschränkung im echten `$HOME` laufen lässt, können sie:

- Configs, Credentials oder SSH-Keys lesen, die nichts mit dem Projekt zu tun haben
- Versehentlich Dateien außerhalb des Repos überschreiben
- Im Hintergrund beliebige Netzwerkverbindungen aufbauen

Der Sandbox-Ansatz hier setzt auf **defense in depth** für den normalen Dev-Workflow — kein Fullhardening, aber ein deutlich reduzierter Blast Radius.

## Was der Sandbox macht (und was nicht)

**Was eingeschränkt wird:**

| Bereich | Verhalten im Sandbox |
|---|---|
| Dateisystem | Nur das aktuelle Repo ist beschreibbar (unter `/workspace`); `.git/` wird standardmäßig read-only übermountet |
| Home-Verzeichnis | Temporäres Scratch-Home, wird nach der Session gelöscht |
| Credentials | Nur explizit kopierte Auth-Dateien sichtbar (kein `$HOME`) |
| Prozesse | Eigener PID-Namespace — Agent sieht keine Host-Prozesse |
| Hostname | Immer `agent-sandbox`, nie der echte Hostname |
| Netzwerk | Optional abschaltbar mit `NO_NET=1` oder `-n` |

**Was nicht verhindert wird:**

- Fast alles innerhalb von `/workspace` kann der Agent lesen, schreiben und löschen; `.git/` ist standardmäßig read-only
- Bei aktivem Netzwerk kann der Agent externe APIs erreichen (notwendig für Modellanfragen)
- Kernel-Exploits / Container-Escapes (dafür bräuchte man gVisor oder MicroVMs)

**Fazit:** Gut gegen versehentlichen Blast Radius. Kein Schutz gegen einen destruktiven Agenten innerhalb des Repos.

## Technischer Aufbau

```
┌─────────────────────────────────────────────────────┐
│  Host                                               │
│                                                     │
│  bwrap (user namespace + mount namespace)           │
│  ┌───────────────────────────────────────────────┐  │
│  │  Sandbox                                      │  │
│  │                                               │  │
│  │  /workspace  →  ~/projects/myapp  (rw)        │  │
│  │  /home/user  →  /tmp/agent-home.XXXX (rw)    │  │
│  │  /usr, /nix  →  Host (ro)                    │  │
│  │  /etc/...    →  Host (ro, minimaler Subset)  │  │
│  │                                               │  │
│  │  copilot / codex / claude / junie              │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

Bubblewrap erstellt beim Start einen frischen **Mount-Namespace**: Nur die explizit gebundenen Pfade existieren im Sandbox. Alles andere — der echte `$HOME`, andere Projekte, SSH-Keys, Browser-Profile — ist schlicht nicht sichtbar.

Kurz gesagt funktioniert es so:

- `agent-sandbox.sh` startet `bwrap` mit eigenen User/PID/IPC/UTS-Namespaces.
- Das Projekt wird als `/workspace` read-write gemountet; `.git/` wird standardmäßig read-only übermountet. Systempfade (`/usr`, `/nix`, Teile von `/etc`) sind ebenfalls nur read-only.
- Der Agent läuft mit einem temporären `/home/user`; nach Ende wird dieses gelöscht (außer persistente Settings unter `~/.config/agent-sandbox/`).
- Lokale Desktop-Session-Sockets werden gezielt durchgereicht: D-Bus für Keyring-Zugriff sowie die Zwischenablage (standardmäßig X11/XWayland, siehe Abschnitt „Clipboard / Bild-Paste“) nur dann, wenn die zugehörigen lokalen Sockets tatsächlich existieren.

Das Scratch-Home wird mit `mktemp -d` erstellt. Beim Exit werden temporäre Daten gelöscht; Agent-Settings werden separat persistent gespeichert. Es enthält nur:

- `.gitconfig` und `.gitignore_global` (nicht-sensitiv)
- Genau die benötigten Agent-Dateien (Copilot: `~/.copilot/config.json`, Codex: `~/.codex/auth.json` + `~/.codex/config.toml`, Claude: `~/.claude/credentials.json` + `~/.claude/settings.json`, Junie: `~/.junie/settings.json` + optional `~/.junie/secure_credentials.json`)
- Eine modifizierte Config mit `/workspace` als vertrauenswürdigem Ordner (damit der Trust-Dialog nicht bei jedem Start erscheint)

Settings und lokaler Session-State aus Sandbox-Sessions werden nach `~/.config/agent-sandbox/` bzw. `~/.local/state/agent-sandbox/` synchronisiert und beim nächsten Start wieder geladen.

## Voraussetzungen

### Ubuntu 24.04+: AppArmor-Profil erforderlich

Ubuntu 24.04 blockiert standardmäßig die Erstellung von User-Namespaces durch unprivilegierte Prozesse (`apparmor_restrict_unprivileged_userns=1`). Ohne Ausnahme schlägt `bwrap` mit `Permission denied` fehl.

Einmalige Installation (erfordert `sudo`):

```bash
sudo cp ~/.config/home-manager/scripts/bwrap-apparmor.profile /etc/apparmor.d/bwrap
sudo apparmor_parser -r /etc/apparmor.d/bwrap
```

`apparmor_parser -r` lädt/ersetzt das Profil. Nach Änderungen am Profil einfach erneut ausführen.

Optionale Verifikation:

```bash
sudo aa-status | rg bwrap
```

Das Profil erlaubt ausschließlich `/usr/bin/bwrap` das Erstellen von User-Namespaces — die systemweite Einschränkung bleibt für alle anderen Prozesse aktiv.

### Optional: `/run/user/$UID` vergrößern

Das Scratch-Home des Sandbox (`/home/user`) liegt auf der tmpfs unter `$XDG_RUNTIME_DIR` (`/run/user/$UID`). Diese ist standardmäßig auf 10 % des RAM begrenzt (z. B. ~3,2 GB bei 32 GB). Alle `$HOME`-Schreibzugriffe im Sandbox — pnpm-/npm-Store, Playwright-Browser-Extraktion, Build-Caches — teilen sich diesen Platz und können bei größeren Installationen volllaufen. Die inneren tmpfs (`/tmp`, `/run`, `/dev/shm`) sind davon unabhängig bereits 16 GB groß; das Limit greift nur am Scratch-Home.

Einmalige Vergrößerung auf 8 GB (erfordert `sudo` + erneutes Login):

```bash
sudo install -Dm644 ~/.config/home-manager/scripts/logind-runtime-size.conf \
  /etc/systemd/logind.conf.d/10-runtime-size.conf
```

Danach **vollständig ausloggen und wieder einloggen** (oder rebooten), damit `/run/user/$UID` neu gemountet wird. Ein bloßes `systemctl restart systemd-logind` remountet eine bereits aktive Session nicht. Verifikation nach dem Re-Login:

```bash
df -h /run/user/$UID
```

## Verwendung

Nach `hm_switch` stehen folgende Shell-Funktionen zur Verfügung:

```bash
copilot                # Host-Copilot ohne Sandbox
codex                  # Host-Codex ohne Sandbox
junie                  # Host-Junie ohne Sandbox
copilot-sandboxed      # Sandbox + --allow-all
codex-sandboxed        # Sandbox + --dangerously-bypass-approvals-and-sandbox, aber .git/ read-only
junie-sandboxed        # Sandbox + --brave (Brave Mode, keine Approval-Prompts)
sbx                    # Sandbox für $PWD, interaktive Bash
sbx-copilot            # Copilot CLI im Sandbox
sbx-copilot-yolo       # Copilot mit --allow-all (kein Confirmation-Prompt)
sbx-codex              # Codex CLI im Sandbox
sbx-codex-yolo         # Codex mit --dangerously-bypass-approvals-and-sandbox
sbx-junie              # Junie CLI im Sandbox
sbx-junie-yolo         # Junie mit --brave (Brave Mode)
sbx-nonet              # Sandbox ohne Netzwerkzugriff
```

Das Projekt wird immer aus dem aktuellen Arbeitsverzeichnis (`$PWD`) genommen.

Argumente werden durchgereicht:

```bash
copilot-sandboxed --resume        # Copilot-Session fortsetzen (sandboxed yolo)
codex-sandboxed --prompt "..."    # Direkt einen Prompt übergeben (sandboxed yolo)
junie-sandboxed --resume          # Junie-Session fortsetzen (sandboxed, Brave Mode)
copilot --resume                  # Host-Copilot ohne Sandbox
codex --prompt "..."              # Host-Codex ohne Sandbox
junie --resume                    # Host-Junie ohne Sandbox
sbx -n codex                      # Codex ohne Netz (explizit)
```

Persistente Settings und lokaler Agent-State:

```bash
~/.config/agent-sandbox/codex/config.toml
~/.config/agent-sandbox/copilot/config.json
~/.config/agent-sandbox/claude/settings.json
~/.config/agent-sandbox/junie/settings.json
~/.local/state/agent-sandbox/copilot/home/
~/.local/state/agent-sandbox/codex/home/
~/.local/state/agent-sandbox/codex/xdg-state/
~/.local/state/agent-sandbox/claude/home/
~/.local/state/agent-sandbox/junie/home/
```

Für Copilot wird neben `config.json` auch der restliche Inhalt von `~/.copilot/` in einen separaten State-Pfad gespiegelt. Damit bleiben lokale Sessions, Resume-Metadaten, Logs und andere CLI-Artefakte über mehrere Sandbox-Runs hinweg erhalten, ohne die modifizierte `config.json` mit dem Trust-Eintrag mit dem übrigen State zu vermischen.

Praktisch heißt das:

- Inhalte aus `~/.copilot/` außer `config.json` werden nach `~/.local/state/agent-sandbox/copilot/home/` persistiert.
- Beim nächsten Sandbox-Start wird dieser Copilot-State wieder nach `~/.copilot/` im temporären Home eingespielt.
- Danach wird `config.json` separat geladen und um `/workspace` in `trusted_folders` ergänzt.
- Host-Dateien wie `~/.copilot/settings.json` und `permissions-config.json` dienen nur als Initial-Fallback. Sobald Sandbox-State existiert, wird er nicht mehr durch den Host überschrieben, damit ein `copilot login` im Sandbox nicht beim nächsten Start verloren geht.
- Copilot Auto-Update ist im Sandbox standardmäßig deaktiviert (`COPILOT_AUTO_UPDATE=false`), weil die globale Installation read-only eingebunden ist. Updates sollten außerhalb des Sandbox laufen.

#### Copilot-Authentifizierung (Token statt Keyring)

Ab Copilot CLI 1.0.65 wird das OAuth-Token im **System-Credential-Store (Keyring)** abgelegt, nicht mehr in einer Datei unter `~/.copilot/`. Der Sandbox kann dieses Keyring-Token nicht zuverlässig auslesen — Copilot startet dann mit `Login status unknown` / `Logged out`. Der unterstützte Weg für headless/sandboxed Nutzung ist ein Token über die Umgebung (`COPILOT_GITHUB_TOKEN`).

Einmalige Einrichtung:

1. Auf der GHE-Instanz (`https://techhub-by-efs.ghe.com`) ein **fine-grained Personal Access Token (v2)** mit der Berechtigung **„Copilot Requests"** erstellen. (Klassische `ghp_`-PATs werden von Copilot nicht akzeptiert.)
2. Token in eine Datei legen, nur für den eigenen User lesbar:

   ```bash
   install -Dm600 /dev/stdin ~/.config/agent-sandbox/copilot/token <<<'<DEIN_TOKEN>'
   ```

Das Sandbox-Script liest diese Datei (Pfad überschreibbar via `COPILOT_TOKEN_FILE`) und injiziert sie als `COPILOT_GITHUB_TOKEN` über die **vererbte Umgebung** — nicht via `--setenv`, damit das Token nie auf der `bwrap`-Kommandozeile (`ps` / `/proc/PID/cmdline`) erscheint. Beim Start zeigt `copilot_token=injected (host=…)` an, dass Token und Host aktiv sind (`none`, wenn keine Token-Datei vorhanden).

**Wichtig — GHE-Host:** Bei Token-Auth über die Umgebung validiert Copilot standardmäßig gegen `github.com` und ignoriert den Host aus `config.json`. Ein GHE-Data-Residency-PAT führt dann zu `Bad credentials`. Das Script setzt deshalb zusätzlich `COPILOT_GH_HOST` (bloßer Hostname, ohne Schema). Der Host wird in dieser Reihenfolge ermittelt:

1. Umgebungsvariable `COPILOT_GH_HOST`
2. Datei `~/.config/agent-sandbox/copilot/host` (Pfad überschreibbar via `COPILOT_HOST_FILE`)
3. Auto-Ableitung des `*.ghe.com`-Hosts aus `~/.copilot/config.json`

Für `techhub-by-efs.ghe.com` greift die Auto-Ableitung, eine `host`-Datei ist also nicht nötig. Den PAT auf genau dieser GHE-Instanz erstellen (nicht auf `github.com`) — ein github.com-Token wird von der GHE-API mit `401 Bad credentials` abgelehnt.

Damit funktioniert `copilot --resume` auch über mehrere Sandbox-Runs hinweg deutlich zuverlässiger.

Für Codex wird nicht nur `~/.codex/` gespiegelt, sondern zusätzlich auch XDG-State unter `~/.local/state/codex/`, weil die Resume-/History-Daten je nach CLI-Version nicht konsistent nur an einer Stelle liegen.

Praktisch heißt das:

- Session-Dateien wie `~/.codex/sessions/...jsonl` werden nach `~/.local/state/agent-sandbox/codex/home/` persistiert.
- Zusätzlicher Codex-State unter `~/.local/state/codex/` wird nach `~/.local/state/agent-sandbox/codex/xdg-state/` persistiert.
- Beim nächsten Sandbox-Start werden beide Verzeichnisse wieder in das temporäre Home eingespielt.

Damit funktioniert mindestens `codex resume --last` auch über mehrere Sandbox-Runs hinweg.

Der interaktive Resume-Picker kann je nach Codex-Version trotzdem unvollständig sein, obwohl die Session-Dateien bereits vorhanden sind. In dem Fall ist `codex resume --last` der zuverlässigere Weg.

Für Claude Code wird `~/.claude/` nach dem gleichen Muster behandelt:

- `credentials.json` wird bei jedem Start frisch vom Host geseeded (ephemeral, nicht persistiert).
- `settings.json` wird persistent gespeichert und um `/workspace` in `trustedDirectories` sowie Standard-Tool-Permissions ergänzt.
- Restlicher State (Sessions, Logs, Projects) wird nach `~/.local/state/agent-sandbox/claude/home/` persistiert.

Damit funktioniert `claude --resume` über mehrere Sandbox-Runs hinweg.

Für JetBrains Junie CLI wird `~/.junie/` nach dem gleichen Muster behandelt:

- `settings.json` wird persistent gespeichert.
- `secure_credentials.json` wird bei jedem Start frisch vom Host geseeded (ephemeral, nicht persistiert) — das ist Junies Fallback-Secret-Store, der nur greift, wenn kein System-Keyring verfügbar ist.
- Restlicher State (`sessions/`, `allowlist.json`, `mcp/`, `models/`, `agent-skills/`, Logs) wird nach `~/.local/state/agent-sandbox/junie/home/` persistiert.

Junie selbst wird von diesem Repo nicht als Nix-Package gebaut, weil der CLI-Shim sich selbst aktualisiert (neue Versionen landen unter `~/.local/share/junie/versions/<version>/`) — ein unveränderlicher Nix-Store-Pfad stünde dem im Weg, genau wie bei Copilot (`COPILOT_AUTO_UPDATE=false`). Stattdessen führt `environments/base.nix` bei jedem `home-manager switch` über `home.activation.installJunieCli` einen Versions-Check gegen das öffentliche Update-Manifest durch: Nur wenn die lokal installierte Version nicht der neuesten für die eigene Plattform entspricht, wird der offizielle Installer (`curl -fsSL https://junie.jetbrains.com/install.sh | bash`) tatsächlich ausgeführt und lädt das ~200-MB-Release neu herunter. Ist bereits die aktuelle Version installiert, ist der Schritt ein No-Op (kein Download, < 1 Sekunde) — der Installer selbst prüft das nämlich nicht und würde bei jedem Aufruf blind neu herunterladen. Der Shim landet unter `~/.local/bin/junie`, die eigentlichen Binaries unter `~/.local/share/junie`. Beide Pfade sind bereits im Sandbox read-only eingebunden (wie bei Copilot/Codex), sodass keine manuelle Installation mehr nötig ist.

#### Junie-Authentifizierung (Headless)

Junie unterstützt Auth über die Umgebungsvariable `JUNIE_API_KEY` (Token generieren unter [junie.jetbrains.com/cli](https://junie.jetbrains.com/cli)). Einmalige Einrichtung:

```bash
install -Dm600 /dev/stdin ~/.config/agent-sandbox/junie/token <<<'<DEIN_TOKEN>'
```

Das Sandbox-Script liest diese Datei (Pfad überschreibbar via `JUNIE_TOKEN_FILE`) und injiziert sie als `JUNIE_API_KEY` über die vererbte Umgebung — nicht via `--setenv`, damit das Token nie auf der `bwrap`-Kommandozeile erscheint. Beim Start zeigt `junie_token=injected` an, dass das Token aktiv ist (`none`, wenn keine Token-Datei vorhanden ist). Alternativ funktioniert auch die JetBrains-Account-Anmeldung, sofern das lokale Session-Keyring über D-Bus im Sandbox erreichbar ist (siehe Copilot-Abschnitt oben zu `~/.local/share/keyrings`).

Extra Bind-Mounts für Sonderfälle:

```bash
EXTRA_RO="/pfad/host:/pfad/sandbox" sbx-codex   # zusätzlicher Read-Only-Mount
EXTRA_BIND="/pfad/host:/pfad/sandbox" sbx-codex  # zusätzlicher Read-Write-Mount
```

Standardmäßig wird `.git/` read-only übermountet. Damit funktionieren `git status`, `git log` und `git diff` weiter, aber Schreiboperationen wie `git add`, `git commit`, `git fetch` oder `git push` scheitern an den Git-Metadaten.

## Clipboard / Bild-Paste

Die Agenten lesen die Zwischenablage (inklusive eingefügter Bilder) über eine gebündelte Rust-Library (`clipboard-rs`). Deren Wayland-Pfad braucht das Protokoll `wlr-data-control` bzw. `ext-data-control`, das einige Compositor (insbesondere GNOME/Mutter) nicht kompatibel anbieten — dann schlägt Bild-Paste mit „a required Wayland protocol … is not supported by the compositor“ fehl. Der klassische X11-Selektionspfad über XWayland funktioniert dagegen zuverlässig und trägt auch Bilder, die aus nativen Wayland-Apps kopiert wurden.

Deshalb bevorzugt der Sandbox standardmäßig X11/XWayland für die Zwischenablage, sobald ein X-Display erreichbar ist. Steuerbar über `SANDBOX_CLIPBOARD`:

```bash
SANDBOX_CLIPBOARD=auto     sbx-copilot   # Default: X11 wenn XWayland da, sonst Wayland
SANDBOX_CLIPBOARD=x11      sbx-copilot   # nur X11/XWayland
SANDBOX_CLIPBOARD=wayland  sbx-copilot   # native Wayland (z. B. wlroots/Hyprland)
SANDBOX_CLIPBOARD=off      sbx-copilot   # keine Clipboard-Weiterleitung
```

## Logging und Diagnose

Jede Sandbox-Session schreibt ein strukturiertes Log nach `~/.local/state/agent-sandbox/`:

```
time=2026-04-10T12:19:26+02:00
project=/home/ub422/projects/myapp
no_net=0
dbus=yes
clipboard=auto
wayland=no
x11=yes
settings_root=/home/ub422/.config/agent-sandbox
state_root=/home/ub422/.local/state/agent-sandbox
cmd=copilot --allow-all
```

Für vollständiges Syscall-Tracing (was der Agent wirklich tut):

```bash
TRACE_SANDBOX=1 sbx-codex
```

Erzeugt pro Prozess eine Trace-Datei im selben Log-Verzeichnis. Nützliche Auswertungen:

```bash
# Alle ausgeführten Binaries
grep execve ~/.local/state/agent-sandbox/*trace* | grep -v ENOENT | sed 's/.*execve("\([^"]*\)".*/\1/' | sort -u

# Schreibzugriffe — sollten nur /workspace und /home/user enthalten
grep -h 'creat\|rename\|unlink' ~/.local/state/agent-sandbox/*trace* | grep -v 'ENOENT\|O_RDONLY'

# Zugriffe auf echtes $HOME (sollte leer sein)
grep "$HOME" ~/.local/state/agent-sandbox/*trace*
```

**Beobachtung aus der Praxis:** Codex lädt beim Start automatisch seine Plugin-Marketplace-Daten von GitHub (`git clone https://github.com/openai/plugins.git`) — noch bevor der erste Prompt eingegeben wird. Die Writes landen im Scratch-Home und werden beim Exit gelöscht.

## Sicherheitsbewertung

| Aspekt | Bewertung |
|---|---|
| Schutz von `$HOME` | ✅ Gut — nicht gebunden, nicht sichtbar |
| Schutz anderer Projekte | ✅ Gut — nur `/workspace` gebunden |
| Credential-Isolation | ✅ Gut — nur explizit kopierte Files |
| Prozess-Isolation | ✅ Gut — eigener PID/IPC/UTS-Namespace |
| Netzwerk-Isolation | ⚠️ Optional — standardmäßig offen (Agents brauchen API-Zugriff) |
| Syscall-Filterung | ❌ Kein seccomp — Kernel-Angriffsfläche bleibt |
| Schutz innerhalb `/workspace` | ⚠️ Teilweise — Worktree ist schreibbar, `.git/` aber standardmäßig read-only |
| Kernel-Escape-Schutz | ❌ Kein — dafür gVisor oder MicroVM nötig |

**Geeignet für:** Lokale Dev-Workflows, eigene Projekte, Pair-Programming mit KI-Agenten.  
**Nicht geeignet für:** Ausführung von fremdem/unvertrauenswürdigem Code, Produktionsumgebungen, geteilte Systeme.

## Dateien

```
scripts/
  agent-sandbox.sh          # Wrapper-Script (installiert nach ~/.local/bin/)
  bwrap-apparmor.profile    # AppArmor-Profil für Ubuntu 24.04+
dotfiles/
  .bash_aliases             # Shell-Funktionen: sbx, sbx-copilot, sbx-codex, ...
```
