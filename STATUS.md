# STATUS

Branch: `linux-port`. Resume rule: read `STATUS.md`, `PLAN.md`, `DECISIONS.md` first.

## Done
- Phase 0 inventory (read-only): `docs/port/INVENTORY.md`.
- Gate A question written to `DECISIONS.md`.

## In progress
- Nothing. Stopped at Gate A as instructed; Phase 1 not started.

## Next
- Phase 1 (headless Linux build and boot), after Ken answers Gate A (or confirms to proceed
  with the recommendation). Write `docs/port/phase-1.md` before touching code.

## Not testable here / notes
- `jackd`, `sclang`, `lua5.3` were not found on this sandbox's PATH (Xvfb is present). Phase 1
  will need to install them; if apt access is unavailable, the boot test moves to
  `docs/port/HARDWARE-CHECKLIST.md`.
- `SANDBOX.md` (referenced in CLAUDE.md for the notification hook) does not exist in the repo,
  so no notification was fired. Ken needs to see the Gate A entry in `DECISIONS.md`.
- The Phase 0 commit is local only: `git push` to `origin/linux-port` returned 403 (the Claude
  GitHub App has no access to aktsom/verdandi). Push after access is fixed.
