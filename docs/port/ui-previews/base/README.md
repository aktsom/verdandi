The product's `device_skin.c` and `device_skin.h` as they were before the Linux layout table was added (the Mac layout, commit 511db78). The preview
generators of rounds 1 and 2 (`gen_variant.py`, `gen_variant33.py`, `gen_variant_ui.py`) patch constants of these copies, so that they keep working
after the product file changed. The Mac layout itself is also what the product's file gives when built without `NORNS_LINUX_DESKTOP`.
