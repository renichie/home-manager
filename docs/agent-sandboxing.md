# AI Agent Sandboxing mit Bubblewrap

Dieses Setup isoliert KI-Coding-Agenten (GitHub Copilot CLI, OpenAI Codex) auf dem Linux-Desktop mit [bubblewrap](https://github.com/containers/bubblewrap) — demselben Sandboxing-Mechanismus, den Flatpak verwendet.

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
│  │  copilot / codex                              │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

Bubblewrap erstellt beim Start einen frischen **Mount-Namespace**: Nur die explizit gebundenen Pfade existieren im Sandbox. Alles andere — der echte `$HOME`, andere Projekte, SSH-Keys, Browser-Profile — ist schlicht nicht sichtbar.

Kurz gesagt funktioniert es so:

- `agent-sandbox.sh` startet `bwrap` mit eigenen User/PID/IPC/UTS-Namespaces.
- Das Projekt wird als `/workspace` read-write gemountet; `.git/` wird standardmäßig read-only übermountet. Systempfade (`/usr`, `/nix`, Teile von `/etc`) sind ebenfalls nur read-only.
- Der Agent läuft mit einem temporären `/home/user`; nach Ende wird dieses gelöscht (außer persistente Settings unter `~/.config/agent-sandbox/`).

Das Scratch-Home wird mit `mktemp -d` erstellt. Beim Exit werden temporäre Daten gelöscht; Agent-Settings werden separat persistent gespeichert. Es enthält nur:

- `.gitconfig` und `.gitignore_global` (nicht-sensitiv)
- Genau die benötigten Agent-Dateien (Copilot: `~/.copilot/config.json`, Codex: `~/.codex/auth.json` + `~/.codex/config.toml`)
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

## Verwendung

Nach `hm_switch` stehen folgende Shell-Funktionen zur Verfügung:

```bash
copilot                # Default: Sandbox + --allow-all
codex                  # Default: Sandbox + --full-auto, aber .git/ read-only
copilot-vanilla        # Host-Copilot ohne Sandbox
codex-vanilla          # Host-Codex ohne Sandbox
sbx                    # Sandbox für $PWD, interaktive Bash
sbx-copilot            # Copilot CLI im Sandbox
sbx-copilot-yolo       # Copilot mit --allow-all (kein Confirmation-Prompt)
sbx-codex              # Codex CLI im Sandbox
sbx-codex-yolo         # Codex mit --full-auto
sbx-nonet              # Sandbox ohne Netzwerkzugriff
```

Das Projekt wird immer aus dem aktuellen Arbeitsverzeichnis (`$PWD`) genommen.

Argumente werden durchgereicht:

```bash
copilot --resume               # Copilot-Session fortsetzen (sandboxed yolo)
codex --prompt "..."           # Direkt einen Prompt übergeben (sandboxed yolo)
copilot-vanilla --resume       # Host-Copilot explizit ohne Sandbox
codex-vanilla --prompt "..."   # Host-Codex explizit ohne Sandbox
sbx -n codex                   # Codex ohne Netz (explizit)
```

Persistente Settings und lokaler Agent-State:

```bash
~/.config/agent-sandbox/codex/config.toml
~/.config/agent-sandbox/copilot/config.json
~/.local/state/agent-sandbox/copilot/home/
~/.local/state/agent-sandbox/codex/home/
~/.local/state/agent-sandbox/codex/xdg-state/
```

Für Copilot wird neben `config.json` auch der restliche Inhalt von `~/.copilot/` in einen separaten State-Pfad gespiegelt. Damit bleiben lokale Sessions, Resume-Metadaten, Logs und andere CLI-Artefakte über mehrere Sandbox-Runs hinweg erhalten, ohne die modifizierte `config.json` mit dem Trust-Eintrag mit dem übrigen State zu vermischen.

Praktisch heißt das:

- Inhalte aus `~/.copilot/` außer `config.json` werden nach `~/.local/state/agent-sandbox/copilot/home/` persistiert.
- Beim nächsten Sandbox-Start wird dieser Copilot-State wieder nach `~/.copilot/` im temporären Home eingespielt.
- Danach wird `config.json` separat geladen und um `/workspace` in `trusted_folders` ergänzt.

Damit funktioniert `copilot --resume` auch über mehrere Sandbox-Runs hinweg deutlich zuverlässiger.

Für Codex wird nicht nur `~/.codex/` gespiegelt, sondern zusätzlich auch XDG-State unter `~/.local/state/codex/`, weil die Resume-/History-Daten je nach CLI-Version nicht konsistent nur an einer Stelle liegen.

Praktisch heißt das:

- Session-Dateien wie `~/.codex/sessions/...jsonl` werden nach `~/.local/state/agent-sandbox/codex/home/` persistiert.
- Zusätzlicher Codex-State unter `~/.local/state/codex/` wird nach `~/.local/state/agent-sandbox/codex/xdg-state/` persistiert.
- Beim nächsten Sandbox-Start werden beide Verzeichnisse wieder in das temporäre Home eingespielt.

Damit funktioniert mindestens `codex resume --last` auch über mehrere Sandbox-Runs hinweg.

Der interaktive Resume-Picker kann je nach Codex-Version trotzdem unvollständig sein, obwohl die Session-Dateien bereits vorhanden sind. In dem Fall ist `codex resume --last` der zuverlässigere Weg.

Extra Bind-Mounts für Sonderfälle:

```bash
EXTRA_RO="/pfad/host:/pfad/sandbox" sbx-codex   # zusätzlicher Read-Only-Mount
EXTRA_BIND="/pfad/host:/pfad/sandbox" sbx-codex  # zusätzlicher Read-Write-Mount
```

Standardmäßig wird `.git/` read-only übermountet. Damit funktionieren `git status`, `git log` und `git diff` weiter, aber Schreiboperationen wie `git add`, `git commit`, `git fetch` oder `git push` scheitern an den Git-Metadaten.

## Logging und Diagnose

Jede Sandbox-Session schreibt ein strukturiertes Log nach `~/.local/state/agent-sandbox/`:

```
time=2026-04-10T12:19:26+02:00
project=/home/ub422/projects/myapp
no_net=0
dbus=yes
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
