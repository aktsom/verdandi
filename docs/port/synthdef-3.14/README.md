# SynthDefs that build on SuperCollider 3.13 but not on 3.14 (KNOWN-ISSUES item 21)

- `mx_malone-clip.diff`: the fix for the mod nb_mxsynths (`Clip.ar` -> `Clip.kr` on two control-rate signals); apply in the mod's folder with `patch -p1`. Builds on 3.13.0 and 3.14.1 (11 of 11 `mx_` defs).
- `ClipKr.sc.proposal`: a Linux-only compatibility class extension (NOT installed; the owner decides): `Clip.ar` with a control-rate first input wraps it in `K2A.ar`. With it the unmodified mod builds all 11 defs on 3.14.1.
- `SDTrap.sc.tool`: the test tool: replaces `SynthDef.build` so that a failing def is printed as `SDFAIL <name> :: <error>` and the others still build (put its folder in `includePaths` of a sclang run).

Applied by the launcher (Gate F decided): `sc/linux-compat/NornsSynthDefCompat.sc` does the `ClipKr` idea only for the SynthDef names on its list (not for every def); `ClipKr.sc.proposal` stays a documented fallback and is not installed.
