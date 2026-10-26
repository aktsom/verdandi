# Scratch material for docs/port/packaging.md

Not part of the product; nothing here is run by `run_all.sh`. The experiments were made in a scratch folder outside the repository (paths are inside the scripts); no repository code was changed.
- `build-supercollider-no-qt.sh`: SuperCollider 3.14.1 built from its tag with the Mac port's flags (JACK, no Qt, no IDE), the recipe of `macos/setup-deps.sh`.
- `readonly-boot.sh`: boots norns headless from a program tree mounted read-only (a private mount namespace), with the home in another folder.
- `make-clean-rootfs.sh`, `clean-rootfs-run.sh`, `clean-rootfs-inner.sh`: a minimal Ubuntu 24.04 root (debootstrap), the experimental package installed with apt, a headless boot.
- `experiment-control`, `experiment.desktop`: the control file and desktop entry of the experimental package (the `Depends` line comes from `dpkg-shlibdeps` plus the choices in the note).
- `clean-install-output.txt`: the output of the last run.
