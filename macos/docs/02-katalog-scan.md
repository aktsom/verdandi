# Katalog-Scan: was die Community-Scripts vom Port verlangen

Stand 2026-10-19. Quelle: `community.json` aus monome/norns-community (353 Einträge),
351 Repos geklont (`macos/tools/catalog/fetch_one.sh`) (2 existieren nicht mehr: jaseknighter/semiconductor,
nattog/vials). Rohdaten pro Repo: `catalog-scan.json`, erzeugt mit
`python3 -I macos/tools/catalog/scan_catalog.py <arbeitsordner> catalog-scan.json`
(der Arbeitsordner enthält `catalog/src` mit den Klonen und `upstream/` mit norns,
supercollider, sc3-plugins und mi-UGens).

Statischer Scan, nichts aus den Repos wurde ausgeführt. Kommentare werden vor dem Zählen entfernt.

## Ergebnis

| Kategorie | Repos | Bedeutung |
|---|---|---|
| A sauber | 177 | keine Shell-Aufrufe, keine `/home/we`-Pfade, nur Core-UGens, keine Binaries |
| B zentral fixbar | 141 | braucht nur Dinge, die der Port einmal für alle liefert (unten) |
| C Laufzeit-Check | 25 | baut Shell-Befehle dynamisch zusammen; erst im laufenden Port prüfbar |
| D offen | 8 | Einzelfälle (unten) |

Engines: 140 Scripts nutzen keine SC-Engine (nur softcut/MIDI/Grid), 49 eine eingebaute
(PolyPerc, PolySub …), 129 eine eigene, 41 die Engine eines anderen Katalog-Scripts
(Abhängigkeit wie auf norns). Fehlend nur `Moonshine` (sonocircuit/streams).

## Was der Port zentral liefern muss (Kategorie B)

1. **Pfad-Umleitung `/home/we`**: 82 Repos schreiben den Pfad fest rein.
2. **sc3-plugins für macOS**: 71 Repos. Häufigste: Decimator 31, SVF 11, MoogLadder 10,
   SawDPW 9, SineShaper 9, DFM1 8, Greyhole 6, PulseDPW 6, DPW3Tri 5, JPverb 4.
   Dazu mi-UGens (MiRings 2, MiClouds 1) und ChowDSP-Ports (AnalogTape/Chew/Loss/Degrade/
   VintageDistortion, je 2).
3. **lua-cjson eingebaut**: 15 Repos bringen ein Linux-`cjson.so` mit. Der Port muss
   `require "cjson"` auf das eingebaute Modul lenken (norns hat dafür `ENABLE_LUA_CJSON`).
4. **Neu gebaute native Teile** (einmal pro Datei, nicht pro Script): ryleelyman-UGens
   FormantTriPTR/PulsePTR/TrianglePTR (`*_scsynth.so`, 3 Repos), Programme
   `audiowaveform`, `soxgo`, `jack_capture`, `aubioonset`.
5. **Shell**: 100 Repos rufen die Shell auf, 63 davon nur mit POSIX-Befehlen, die macOS hat
   (mkdir 51, rm 28, cp 25, ls, touch, cd, find, mv, cat, curl, git …).
   Shims nötig für GNU/Linux-only: `stat` (andere Flags), `sha256sum`, `timeout`, `shuf`,
   `pidof`, `apt`/`apt-get` (Abhängigkeits-Installation → no-op, Abhängigkeit mitliefern),
   `jack_connect`/`jack_disconnect` (5 Repos, auf das Port-Routing abbilden).
   Mitliefern: `sox`, `ffmpeg`/`ffprobe`, `convert`, `mpv`, `aubioonset`.

## Kategorie D, Einzelfälle

- UGens aus unbekannten Paketen: `ByteBeat` (midouest/bitebeet), `Fverb2` (schollz/rachim),
  `Open303` (toneburst/bline) — Herkunft klären, vermutlich beim Install nachgeladen.
- Engine `Moonshine` fehlt im Katalog (sonocircuit/streams).
- Linux-Paket-/System-Tools: `dpkg`, `ldconfig` (schollz/zxcvbn), `dpkg-query`, `iwgetid`
  (tapecanvas/nornsfetch, ein Systeminfo-Script), `powershell` (subvertnormality/mosaic,
  vermutlich Dev-Hilfsskript).
- spgarbet/Ygg ist nur ein Fehlalarm (`[` = POSIX test) und gehört nach B.

## iOS-Vorschau

Auf iOS gibt es keine Shell: alle 100 Repos mit Shell-Aufrufen brauchen dort Emulation.
Die 63 Repos mit reinen Datei-Befehlen (mkdir/rm/cp/ls/touch/mv) sind in Lua direkt
nachbildbar; `sox`/`ffmpeg`/Programme brauchen eingebettete Bibliotheken.

## Grenzen

Erkennt keine Abweichungen in der Lua-API-Nutzung, keine Laufzeitfehler und keine
Performance-Probleme. Das kommt mit dem Laufzeit-Test, sobald der Port headless startet.
