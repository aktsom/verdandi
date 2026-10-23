# DECISIONS

## GATE A: fork vs upstream-as-platform-folders (open)

**Question:** where does the Linux (and later Windows) code live, and do we approach ha1dcre?

Findings from the inventory (`docs/port/INVENTORY.md`): the reusable desktop layer (skins,
key mapping, vgrid protocol, GIF writer) sits in `matron/src/platform/macos/`; upstream
norns already builds on desktop Linux and has the Linux device code, so most Linux work is
the desktop layer (window, menu, picker, drop, SYS input) plus build/launcher/packaging.

**Options**
1. Platform folders in this fork: new `matron/src/platform/linux/` (later `windows/`), shared
   files moved or referenced from a `platform/common/` folder; macOS files untouched at first.
   Keeps the code offerable upstream.
2. Fork-only layout: Linux files added next to the macOS ones, no shared folder, no upstream
   intent. Least refactoring, most duplication risk.
3. Approach ha1dcre before starting: ask whether they want a Linux/Windows port upstream and
   in what layout. Highest coordination cost; I will not contact anyone without Ken.

**Recommendation:** Option 1, with shared files left in place in Phase 1-2 and moved to
`platform/common/` only in a separate commit once Linux works (keeps macOS behavior and its
tests unchanged meanwhile). Whether to approach ha1dcre is Ken's call, after Linux works.

**Needed from Ken:** pick 1, 2 or 3 (and if 3, who contacts ha1dcre).

Notification: not sent. `SANDBOX.md` (notification hook) is missing from the repo.
