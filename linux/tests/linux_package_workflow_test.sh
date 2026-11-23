#!/bin/bash
# the workflow that builds and publishes the Linux package (docs/port/phase-m36.md): a tag or a hand start, never a push of a branch; explicit generous timeouts; the publishing job is the only one with write permission and
# runs linux/ci/publish-release.sh; nothing in it names a Windows release; the unit test workflow is not changed to build the package.
cd "$(dirname "$0")/../.." || exit 1
W=.github/workflows/linux-package.yml
fails=0
ck() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
[ -f "$W" ] || { echo "FAIL $W does not exist"; exit 1; }
python3 - "$W" << 'PY' || fails=$((fails + 1))
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
on = d.get(True, d.get('on'))
bad = []
if 'push' not in on or set(on['push'].keys()) != {'tags'} or on['push']['tags'] != ['linux-v*']: bad.append('push must be tags linux-v* only (no branches)')
if 'workflow_dispatch' not in on: bad.append('no workflow_dispatch')
if 'schedule' in on or 'pull_request' in on: bad.append('schedule or pull_request trigger')
if d['permissions'] != {'contents': 'read'}: bad.append('top-level permissions must be contents: read')
for name, job in d['jobs'].items():
    if not isinstance(job.get('timeout-minutes'), int) or job['timeout-minutes'] < 20: bad.append(name + ': no generous job timeout')
    for st in job['steps']:
        if 'run' in st and len(st['run']) > 400 and 'timeout-minutes' not in st and 'Publish' not in st.get('name', ''): bad.append(name + ': long step without a timeout: ' + st.get('name', '?'))
    w = job.get('permissions', {}).get('contents')
    if (w == 'write') != (name == 'release'): bad.append(name + ': write permission is only for the release job')
pk = d['jobs']['package']
tm = {st.get('name', ''): st.get('timeout-minutes') for st in pk['steps']}
if not any(v and v >= 60 for k, v in tm.items() if 'linux/package.sh' in k): bad.append('the package step needs a timeout of at least 60 minutes')
if 'linux/ci/publish-release.sh' not in str(d['jobs']['release']): bad.append('the release job does not run linux/ci/publish-release.sh')
if 'cache' not in str(pk): bad.append('no cache of the SuperCollider build')
if 'ubuntu:24.04' not in str(pk) or 'ubuntu-24.04' not in pk['runs-on']: bad.append('Ubuntu 24.04 runner and ubuntu:24.04 container expected')
if 'deb_upgrade_inner.sh' not in str(pk): bad.append('the clean-container checks are not run')
print('\n'.join('FAIL ' + b for b in bad) if bad else 'ok   triggers, permissions, timeouts, cache, clean container, publish script')
sys.exit(1 if bad else 0)
PY
ck "the second checkout gets the real origin address (a local path would be taken as identity words by the privacy scan: the first run failed on that)" 'grep -q "remote set-url origin" "$W"'
ck "the root install test and the package build use a neutral HOME (the name of the runner account would be an identity word)" 'grep -q "HOME=/root PATH" "$W" && grep -q "HOME=\"\$RUNNER_TEMP/pkghome\" linux/package.sh all" "$W"'
ck "linux/ci/upgrade-from.txt names a commit that exists in this history, and the workflow reads it" 'h="$(grep -v "^#" linux/ci/upgrade-from.txt | head -n 1 | tr -d " ")"; git cat-file -e "$h^{commit}" 2>/dev/null && grep -q "upgrade-from.txt" "$W"'
ck "the maintainer script test is given the NEW package (the newest file in build/package is the older one there; run 4 failed on that)" 'grep -q "deb_scripts_test.sh \"\$RUNNER_TEMP/new.deb\"" "$W"'
ck "nothing in the workflow names a Windows release, tag or zip" '! grep -qiE "windows-latest|windows-[0-9a-f]{7}|Verdandi-windows" "$W"'
ck "the unit test workflow does not build or publish the package" '! grep -qE "package.sh|publish-release|linux-latest" .github/workflows/linux-tests.yml'
ck "the Windows workflows do not mention the Linux package" '! grep -qE "linux-latest|linux-package|linux/ci/" .github/workflows/windows-m0.yml .github/workflows/windows-m1.yml'
ck "no personal name or handle in the workflow" '! grep -qiE "aktsom|ha1dcre" "$W"'
[ $fails -eq 0 ] && echo "linux_package_workflow_test: all passed"
exit $fails
