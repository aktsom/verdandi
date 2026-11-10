# ASIO and the licence of a GPL-3.0 program (milestone M3)

Question: what does Steinberg's ASIO SDK licence mean for Verdandi, a GPL-3.0 program that would ship a PortAudio built with the ASIO host API?

## What was read, and what was not (please read this first)

- **Not read from Steinberg's own file.** `raw.githubusercontent.com/steinbergmedia/asiosdk/.../LICENSE.txt` and `github.com/steinbergmedia/asiosdk` could not be fetched in this session (404 or the host is blocked from the sandbox). What I read instead: the `audiosdk/asio` mirror of the SDK (its description of `LICENSE.txt` and its README), the SwankyAmp pull request that builds a program against the SDK "under its GPLv3 option" (it quotes the package's licence and README), Repology's entry for the 2.3.4 package, Steinberg's press release of 2025-10-15 and the secondary coverage (Libre Arts, CDM, Steinberg forum). **I did not read the licence text word for word from Steinberg.**
- **So the build reads it for you.** `windows/ci/build-portaudio-asio.sh` clones the SDK (first CI run: `github.com/steinbergmedia/asiosdk` is **not public**, git asked for a user name; the build now tries the third-party mirror `github.com/audiosdk/asio` first, then Steinberg's address, and records which one it used in `PA-ASIO-BUILD.txt`), **stops if the SDK has no `LICENSE.txt` or if that file does not mention the GPL**, prints its first lines into the step log, and the ASIO zip carries the file **unchanged** as `licenses\ASIO-SDK-LICENSE.txt`. Read that file once, before you hand the ASIO zip to anyone.

## What the sources agree on

1. Since October 2025 the SDK (2.3.4) is **dual-licensed: the proprietary "ASIO SDK licensing agreement" (a signed agreement with Steinberg), or the GNU GPL version 3.** You choose one per product.
2. Choosing the GPLv3 option means **the product must be released under GPLv3 terms, including its source.** Steinberg's FAQ says so (as quoted by the secondary sources).
3. Existing products on the proprietary agreement need not move.
4. **Trademark:** "ASIO" is a Steinberg trademark. Under the GPLv3 option the name or logo is optional; if used it must follow Steinberg's trademark rules (which the SDK is reported to include), and not following them does not touch your GPL rights but can be a trademark violation.
5. **Open point:** Repology lists the 2.3.4 package as **GPL-3.0-only** next to a `LicenseRef-Steinberg` entry; other coverage says just "GPLv3". "Only" or "or later" is to be read in the file. It does not change the answer for Verdandi, which is GPL-3.0.

## What it means for Verdandi (GPL-3.0)

- **Compatible.** Verdandi is GPL-3.0. Taking the SDK under the GPLv3 option and building PortAudio (MIT, GPL-compatible) with it gives a combined work that is GPLv3 as a whole, which is what Verdandi already is. No agreement with Steinberg, no fee, no registration. **The proprietary agreement must not be accepted for this build** (its restrictions are additional restrictions that GPLv3 forbids): the build is GPLv3 only.
- **What we owe to anyone who gets the ASIO zip (GPLv3 sections 4 to 6):** the licence text, the copyright and trademark notices, and the **corresponding source** of the binary: Verdandi (this repository at the commit of the build), PortAudio as it was built, the SDK as it was used, and the scripts that built it.
- **What this does not change:** SuperCollider is GPL-3.0-or-later, Lua and libmonome are permissive, the MSYS2 libraries are LGPL or permissive: all unchanged.
- **Which code is ASIO code.** Only `libportaudio-2.dll` of the ASIO zip contains Steinberg SDK code (its ASIO host API). `norns.exe` has none: `audio_backend_pa.c` re-declares PortAudio's own public stream-info struct (`PaAsioStreamInfo`, MIT, part of PortAudio's API) and asks the DLL which host APIs it has. A PortAudio without ASIO lists none and the code is not reached. So the default zip has **no ASIO code at all**.

## What must be where

| Where | What |
|---|---|
| Repository | this note; `docs/port/DEPS.md` (PortAudio with ASIO, the SDK, licences, trademark); `windows/ci/build-portaudio-asio.sh` and `windows/ci/asio-sdk.env` (what is built from which commit); `windows/pack/ASIO-NOTICE.txt` and `windows/pack/SOURCE-OFFER.txt` (the texts that go into the zips). **No SDK file is committed** (the licence would allow it; not doing it keeps the repository free of code that is not ours and the licence question in one place). |
| Both zips | `SOURCE-OFFER.txt` (the repository, the commit, the other sources), `licenses\Verdandi-GPL-3.0.txt`, `licenses\SuperCollider-GPL.txt` |
| ASIO zip only | `licenses\ASIO-SDK-LICENSE.txt` (verbatim), `ASIO-NOTICE.txt` (also in `licenses\`; says: ASIO is a trademark and software of Steinberg Media Technologies GmbH, GPLv3 option, no endorsement), `source\portaudio-source.zip`, `source\asio-sdk-source.zip`, `source\PA-ASIO-BUILD.txt` (the commits), `FLAVOR.txt` |
| Release notes | which zip is the default, a pointer to the notice |
| The program | the word "ASIO" appears on the AUDIO page only to name the driver interface; **no ASIO logo is used anywhere** |

## Recommendation

**Two builds, separate artifacts, WASAPI-only as the default.** The ASIO build is made by the same workflow and published next to the default one (`Verdandi-windows-asio-<version>-<hash>.zip`; `Verdandi-windows-asio-latest.zip` has a fixed address; `update-and-run.cmd` in an ASIO folder updates to the ASIO build). The default `Verdandi-windows-latest.zip` has no ASIO code and no ASIO notices to carry.

Why not ASIO as the default now: (a) the licence text was read through mirrors, not from Steinberg (above); (b) "GPL-3.0-only" versus "or later" and the trademark rules are unread; (c) the ASIO build is new and never ran on a Windows machine with a driver (CI has none); (d) on the owner's PC ASIO is usually held by Ableton, so the default route is WASAPI or the Loopback route anyway (`docs/port/phase-m3.md`, section 3).

**To make ASIO the default** (a later decision, `DECISIONS.md` lists it): read `licenses\ASIO-SDK-LICENSE.txt` of a build, accept that the ASIO zip is GPLv3 as a whole (it is), check that the notices in the zip are enough, and tell me; the change is one line in `publish-release.sh` and the release notes.

**If the reading comes out differently** (the file offers no GPL option, or Steinberg's trademark rules ask for more): the ASIO job is `continue-on-error`, it can be switched off in one place (delete the `asio` and `package-asio` jobs); nothing else depends on it.

## Not verified

- The SDK's `LICENSE.txt` word for word; GPL-3.0-only vs. or-later; the trademark guidelines text.
- That the mirror is an unmodified copy of Steinberg's SDK (it is not Steinberg's own file; read the shipped `LICENSE.txt` and compare with the zip from steinberg.net), that its layout has `common/asio.h` and `LICENSE.txt` (the script stops if not), and the SDK **commit pin** in `windows/ci/asio-sdk.env` (empty until a run prints it; the PortAudio commit is pinned).
- That PortAudio 19.7's CMake finds the SDK through `ASIOSDK_ROOT_DIR` (both spellings are passed; the first CI run tells).
- No legal advice: this is a reading of public texts by someone who is not a lawyer.
