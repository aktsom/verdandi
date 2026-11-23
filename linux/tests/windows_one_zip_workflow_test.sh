#!/bin/bash
# M31 (docs/port/phase-m31.md): the Windows workflow makes and publishes ONE zip. structure only (nothing runs here): the ASIO build of PortAudio is required for the zip (no continue-on-error), the zip is assembled once
# and checked by two jobs on the same file with the M30 limits (the ASIO cases job 90 minutes / 75 for its step; the long checks 110 / 100), the release waits for all of them and publishes only that zip, there is no
# second zip, no FLAVOR, no ASIO_ZIP_DIR any more, and the transition copy is made by the publish script from the same bytes.
cd "$(dirname "$0")/../.." || exit 1
W=.github/workflows/windows-m1.yml
fails=0
ck() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
python3 - "$W" << 'PY' || fails=$((fails + 1))
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
j = d['jobs']
bad = []
for need in ('sc', 'norns', 'asio', 'assemble', 'package', 'package-asio', 'release', 'report'):
    if need not in j: bad.append('job missing: ' + need)
if j.get('asio', {}).get('continue-on-error'): bad.append('the ASIO PortAudio job must not be continue-on-error: the zip is the ASIO build')
if 'asio' not in j.get('assemble', {}).get('needs', []): bad.append('assemble must need the asio job')
for name in ('package', 'package-asio'):
    if j[name].get('needs') != ['assemble']: bad.append(name + ' must need exactly assemble (both check the same zip)')
    if j[name].get('continue-on-error'): bad.append(name + ' must not be continue-on-error: a failed check holds the zip back')
def step_timeout(job):
    return max([st.get('timeout-minutes', 0) for st in j[job]['steps']] + [0])
if j['package-asio'].get('timeout-minutes') != 90 or step_timeout('package-asio') != 75: bad.append('package-asio keeps the M30 limits: 90 minutes for the job, 75 for the step')
if j['package'].get('timeout-minutes', 0) < 110 or step_timeout('package') < 100: bad.append('package keeps its limits (110 / 100)')
rel = j['release']
for need in ('assemble', 'package', 'package-asio', 'report'):
    if need not in rel['needs']: bad.append('release must wait for ' + need)
cond = rel['if']
for need in ('assemble', 'package', 'package-asio'):
    if "needs.%s.result == 'success'" % need not in cond: bad.append('release only when %s succeeded' % need)
text = open(sys.argv[1]).read()
for word in ('FLAVOR', 'ASIO_ZIP_DIR', 'm3-asio-zip', 'release-zip-asio', 'Verdandi-windows-asio-latest.zip'):
    if word in text: bad.append('the workflow must not mention ' + word)
if 'SMOKE_PART=main' not in text or 'SMOKE_PART=asio' not in text: bad.append('the two check jobs run the two parts of the smoke test')
if 'permissions' not in rel or rel['permissions'].get('contents') != 'write': bad.append('only the release job writes')
print('\n'.join('FAIL ' + b for b in bad) if bad else 'ok   jobs, needs, limits, release condition, no second zip')
sys.exit(1 if bad else 0)
PY
ck "the publish script has no ASIO zip input and makes the transition copy from the one zip" '! grep -q "ASIO_ZIP_DIR\|HAVE_ASIO" windows/ci/publish-release.sh && grep -q "OLDNAME=\"Verdandi-windows-asio-latest.zip\"" windows/ci/publish-release.sh'
ck "assemble-m1.sh has no FLAVOR any more" '! grep -q "FLAVOR" windows/ci/assemble-m1.sh'
ck "the smoke test has no EXPECT_ASIO (the zip is the ASIO build) and knows the two parts and the vanish case" '! grep -q EXPECT_ASIO windows/ci/smoke-m1.sh && grep -q "SMOKE_PART" windows/ci/smoke-m1.sh && grep -q "m31-check-asio-vanish" windows/ci/smoke-m1.sh'
ck "the update routines name the one zip" 'grep -q "Verdandi-windows-latest" windows/update-and-run.cmd windows/update-and-run.ps1 && ! grep -q "windows-asio-latest" windows/update-and-run.cmd windows/update-and-run.ps1'
ck "no personal name or handle in the files of this phase" '! grep -qiE "aktsom|ha1dcre" docs/port/phase-m31.md windows/ci/publish-release.sh windows/update-and-run.cmd windows/update-and-run.ps1 '"$W"
[ $fails -eq 0 ] && echo "windows_one_zip_workflow_test: all passed"
exit $fails
