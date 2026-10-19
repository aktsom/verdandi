# Linux-Inventar: was matron/crone für macOS brauchen

Stand: monome/norns `a2d27d5` (2026-10-19), vor dem Port.

## Schon da (upstream)

- `--desktop` (wscript) baut mit SDL2: `matron/src/hardware/screen/sdl.cc` (Screen-Fenster)
  und `matron/src/hardware/input/sdl.cc` (Keys/Encoder per Tastatur). Der Stand aus dem
  Forum-Thread (2020: "--desktop macht nichts") ist überholt.
- crone (JACK + softcut) ist portabel; laut zebra (Forum 30832) läuft crone auf macOS,
  die norns-SuperCollider-Klassen laufen mit der normalen macOS-SC-Installation.
- liblo, libmonome (serialosc), cairo, Lua 5.3, libsndfile, nng, JACK: gibt es alle für macOS.
- avahi-compat-libdns_sd: macOS hat `dns_sd.h` nativ (Bonjour), gleiche API.

## Zu ersetzen (Linux-only API-Aufrufe, gezählt)

| Datei | Aufrufe | Linux-API | macOS-Ersatz | Aufwand |
|---|---|---|---|---|
| `matron/src/metro.cc` | 2 | `clock_nanosleep` (absolut) | Shim: `mach_absolute_time` + `mach_wait_until` | klein |
| `matron/src/clocks/clock_internal.cc` | 1 | `clock_nanosleep` | gleicher Shim | klein |
| `matron/src/device/device_monitor.cc` | 64 | libudev (Hotplug, `/dev/snd`) | IOKit-Notifications + CoreMIDI-Notifications | groß |
| `matron/src/device/device_midi.cc` (+ `.h`) | 29 | ALSA rawmidi, Pfad `/dev/snd/midiC%dD%d` | CoreMIDI | mittel |
| `matron/src/device/device_hid.cc` | 12 | libevdev | IOHIDManager | mittel |

`device_serial.cc` / `device_crow.cc` / `device_monome.cc` nutzen termios bzw. libmonome,
beides gibt es auf macOS; nur die Geräteerkennung hängt an `device_monitor.cc`.

## Pi-Hardware, im Mac-Build weglassen bzw. stubben

`hardware/screen/ssd1322.cc` (gpiod + `clock_nanosleep`), `hardware/input/gpio.cc`,
`hardware/battery.cc` (`/sys/class/power_supply`), `hardware/i2c.cc` (`/dev/i2c-1`),
`hardware/stat.cc` (`/proc/stat`, Thermal-Zone), `hardware/platform.cc` (Device-Tree-Modell),
`args.cc` (`/dev/fb0`-Default). `watcher/` ist Pi-only.
Heute stehen diese Dateien unbedingt in `norns/wscript` und sind nur über `io.cc`-Ops
ausgewählt; der Mac-Build braucht dafür eine Plattform-Weiche im wscript.

## Pfade

`matron/src/system_cmd.cc:154` setzt `home = "/home/we"` als Fallback. Scripts schreiben
denselben Pfad oft fest rein; siehe Katalog-Scan (`02-katalog-scan.md`).
