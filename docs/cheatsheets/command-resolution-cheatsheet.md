# Command Resolution Cheatsheet

Beispiel: `teams-for-linux`

```bash
which teams-for-linux
```
Ersten Treffer im `PATH` zeigen.

```bash
type -a teams-for-linux
```
Zeigen, ob es Alias, Funktion oder Binary ist.

```bash
readlink -f "$(which teams-for-linux)"
```
Symlinks bis zum echten Ziel aufloesen.

```bash
file "$(which teams-for-linux)"
```
Zeigen, ob es Skript oder ELF-Binary ist.

```bash
sed -n '1,80p' "$(which teams-for-linux)"
```
Wrapper-Inhalt und gesetzte Flags ansehen.

```bash
bash -x "$(which teams-for-linux)" 2>&1 | head -n 50
```
Bei Shell-Wrappern die expandierten `exec`-Aufrufe sehen.

```bash
pgrep -af teams-for-linux
pgrep -af electron
```
Laufende Prozesse samt Argumenten anzeigen.

```bash
tr '\0' ' ' < /proc/$(pgrep -n -f teams-for-linux)/cmdline; echo
```
Exakte Argumente eines laufenden Prozesses anzeigen.

Fuer dieses Setup ist meist genug:

```bash
which teams-for-linux
readlink -f "$(which teams-for-linux)"
sed -n '1,80p' "$(which teams-for-linux)"
```
