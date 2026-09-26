#!/usr/bin/env bash
# Fast, build-free validation of the whole repository. Runs identically on a
# developer machine (`.github/scripts/validate.sh`) and in the `validate` CI
# job. Every check is required; nothing here needs a container build.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

readonly bluebuild_image='ghcr.io/blue-build/cli:v0.9.37@sha256:f7f3cba63624578590b6664d90d26caad38f16e8241b686d4cfdde889bf9e80e'
status=0
step() { printf '\n==> %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; status=1; }

step 'BlueBuild recipe schema'
if command -v bluebuild >/dev/null; then
  for recipe in recipes/*.yml; do bluebuild validate "${recipe}" || fail "${recipe}"; done
elif command -v docker >/dev/null; then
  for recipe in recipes/*.yml; do
    docker run --rm -v "${PWD}:/bluebuild" "${bluebuild_image}" bluebuild validate "${recipe}" \
      || fail "${recipe}"
  done
else
  fail 'neither bluebuild nor docker is available for schema validation'
fi

step 'Recipe policy (source: local on in-repo modules, duplicates, names)'
DOORS_REPO="${PWD}" python3 -B files/common/usr/bin/doors-recipe --json validate || fail 'doors-recipe validate'

step 'doors-recipe unit tests'
python3 -B -m unittest discover -s tests -q || fail 'unit tests'

step 'Python syntax'
python3 -B -m py_compile files/common/usr/bin/doors-recipe tests/*.py || fail 'py_compile'

step 'Shell scripts'
mapfile -d '' scripts < <(
  {
    find modules files .github/scripts -type f -name '*.sh' -print0
    grep -rlZ --exclude-dir=.git -m1 '^#!.*\bbash\b' files/common/usr/bin files/common/usr/libexec 2>/dev/null || true
  } | sort -zu)
shellcheck --shell=bash --severity=warning "${scripts[@]}" || fail 'shellcheck'
for f in "${scripts[@]}"; do
  [[ "${f}" == */profile.d/* || -x "${f}" ]] || fail "${f} is not executable"
done

step 'systemd unit syntax'
if command -v systemd-analyze >/dev/null; then
  mapfile -t units < <(find files -path '*/systemd/*' -type f \( -name '*.service' -o -name '*.timer' \) | sort)
  systemd-analyze verify --recursive-errors=no "${units[@]}" 2>&1 | grep -v 'Unit .* not found' || true
fi

step 'Workflows (actionlint)'
if command -v actionlint >/dev/null; then actionlint -color || fail 'actionlint'; else echo 'actionlint not installed; skipped'; fi

step 'Workflows (zizmor)'
if command -v zizmor >/dev/null; then zizmor --persona auditor . || fail 'zizmor'; else echo 'zizmor not installed; skipped'; fi

step 'Stray references'
if grep -rIn --exclude-dir=.git --exclude-dir=tests --exclude-dir=rpm-gpg \
  --exclude=validate.sh --exclude=smoke.sh --exclude='*.gpg' --exclude='*.der' \
  -i -E 'cosmic|doors-staging|doors-iso|t3code|\bT3\b' . ; then
  fail 'references to removed images/tools remain'
fi

if (( status == 0 )); then printf '\nAll validation checks passed.\n'; fi
exit "${status}"
