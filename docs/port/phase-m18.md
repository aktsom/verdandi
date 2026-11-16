# Phase M18 (Windows 0.10.9): the false "duplicate classes (Routine)" warning

What the owner saw: after installing the scripts glut and mangl the main window said "SuperCollider: duplicate classes (Routine) in two folders of yours: move one by hand, see launcher.log" (also for orgn and mangl after glut was removed). Nothing was moved, SuperCollider started, glut and orgn made sound.

## 1. The lines that made the guard report Routine

The guard is `windows/launcher/dup_heal.h` (`dh_class_names`), run by the launcher before every start of sclang. It collected "a capital word at the start of a line, followed by `:` or `{` or `[`" from every .sc file, and said two files define the same class when two files had the same name. The three engine files (current master of each repository):

| file | line | what it is |
|---|---|---|
| glut `Engine_Glut.sc` | 261: `Routine {}` | inside `alloc`, in `Array.fill(nvoices, { arg i; Routine {} })` |
| mangl `lib/Engine_MGlut.sc` | 294: `Routine {}` | the same code (mangl is built on glut) |
| orgn `lib/Engine_Orgn.sc` | 188, 198, 291: `Routine {` | inside `this.addCommand(...)` functions: `Routine { ... }.play` |

In every case it is the SuperCollider class `Routine` **used as code inside a method**, on a line of its own. The old reading looked only at the start of a line, not at where in the file the line is, so it took `Routine {` for the head of a class definition. The three engines were first seen as "Engine_X and Routine"; all three have "Routine", hence "duplicate classes (Routine)" for every pair, and for the pair that remained after glut was removed.

## 2. What SuperCollider itself says

Run with the real sclang 3.13 (the one in the test machine): the three files compiled together, with a small CroneEngine stand-in, **without a duplicate**; `Engine_Glut`, `Engine_MGlut`, `Engine_Orgn` and `Routine` all exist afterwards. The same run with a deliberate second `Engine_Orgn` in another folder stops with `ERROR: duplicate Class found: 'Engine_Orgn'` and `Library has not been compiled successfully`. So sclang reports real duplicates and reported nothing here: the guard was wrong.

## 3. The fix

`dh_class_names` now reads a file the way sclang does:
- comments (line comments and block comments, which nest), the inside of strings and symbols and `$x` characters are blanked first;
- a class definition is `Name { }`, `Name : Super { }` or `Name[slots] : Super { }` **outside every `{ }`**: a class body, a method or a function is a body, so a line `Routine {` in a method is no definition;
- `+ Name { }` (an extension of a class defined elsewhere) is not a definition; the superclass name is not one either.
Nothing else in the guard changed: the shipped packs are still kept and a second copy moved aside, two copies of the owner's own are still only reported, plug-in files (`.scx`) are checked as before.

Real duplicates between the owner's folders stay possible, so the note for the norns screen now names both folders (it said only "two folders of yours"): `SuperCollider: duplicate classes (Engine_Orgn) in two folders of yours (dust/code/orgn2 and dust/code/orgn): move one by hand, see launcher.log`. launcher.log has the full paths and the class names, as before.

## 4. Tests

- `linux/tests/dup_heal_test.c` (runs in `run_all.sh`): the old reading is kept in the test, verbatim, and reports `Routine` for the shapes of the glut and orgn engines; the new reading reports only the engine class; the three engines together give no finding, no note and nothing moved (also with a shipped pack present: the owner's engine is not moved because of Routine); the same engine class in two script folders is found (named, with both files and no Routine), nothing moved, and the note names both folders; case by case: comments (nested), strings, symbols, `$}`, extensions, classes with slots, two classes on a line, braces on the next line, a damaged file. All the old cases still pass.
- `linux/tests/dup_heal_sclang_test.sh` (real sclang, unchanged): the 0.8.2 duplicate is still reproduced and healed.
- Windows CI (`m18-*` in `smoke-m1.sh`): the real launcher and sclang start with three engine files shaped like the real ones (class line, Routine lines in methods): no finding, no note, no duplicate in sclang.log; then the same engine in a second script folder: found, both files named, nothing moved, sclang reports the duplicate itself, the note on the screen names both folders. The existing OwnClash check is unchanged.

## 5. Not tested

The three real files were read, and run through the new and the old reading and through real sclang on Linux; the CI uses cut-down copies. The owner's own folders were not available.
