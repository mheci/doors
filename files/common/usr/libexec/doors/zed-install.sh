#!/usr/bin/env bash
# Install Zed for the calling account. The first login installs one reviewed
# stable tarball. Later versions are unpacked only by `doors-update apply`,
# and only after GitHub's published digest matches the download.
set -uo pipefail

if (( EUID == 0 )); then
  printf 'doors-zed-install must run as a regular user, not root\n' >&2
  exit 1
fi

readonly zed_version='v1.21.0'
readonly zed_sha256='b79a992e960ed4067cb2b50d66789ed8618eeb1780ed6a0f8f1e71dd80f74200'
readonly zed_asset='zed-linux-x86_64.tar.gz'
readonly zed_repo='zed-industries/zed'
readonly state_home="${XDG_STATE_HOME:-${HOME}/.local/state}"
readonly stamp="${state_home}/doors/zed-installed"
readonly version_file="${state_home}/doors/zed-version"
readonly app_dir="${HOME}/.local/zed.app"
readonly launcher="${HOME}/.local/bin/zed"

log() { printf 'doors-zed-install: %s\n' "$*"; }

installed_version() {
  if [[ -f "${version_file}" ]]; then
    tr -d '[:space:]' < "${version_file}"
    return 0
  fi
  printf '%s\n' ''
}

disable_auto_update() {
  python3 - <<'PY'
import json
from pathlib import Path
path = Path.home() / ".config" / "zed" / "settings.json"
path.parent.mkdir(parents=True, exist_ok=True)
if path.exists():
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        raise SystemExit(0)
    if not isinstance(data, dict):
        raise SystemExit(0)
else:
    data = {}
if "auto_update" in data:
    raise SystemExit(0)
data["auto_update"] = False
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
}

install_tree() {
  local archive="$1"
  local version="$2"
  local expected="$3"
  local actual tmp desktop icon
  actual="$(sha256sum "${archive}" | awk '{print $1}')"
  if [[ "${actual}" != "${expected}" ]]; then
    log 'checksum mismatch; refusing to unpack'
    return 1
  fi
  tmp="$(mktemp -d)"
  if ! tar -xzf "${archive}" -C "${tmp}"; then
    rm -rf -- "${tmp}"
    log 'archive did not unpack'
    return 1
  fi
  if [[ ! -x "${tmp}/zed.app/bin/zed" || ! -x "${tmp}/zed.app/libexec/zed-editor" ]]; then
    rm -rf -- "${tmp}"
    log 'archive is missing the Zed launcher or editor'
    return 1
  fi
  rm -rf -- "${app_dir}"
  mv -- "${tmp}/zed.app" "${app_dir}"
  rm -rf -- "${tmp}"
  install -d -m 0700 "${HOME}/.local/bin" "${HOME}/.local/share/applications"
  ln -sfn "${app_dir}/bin/zed" "${launcher}"
  desktop="${HOME}/.local/share/applications/dev.zed.Zed.desktop"
  if [[ -f "${app_dir}/share/applications/dev.zed.Zed.desktop" ]]; then
    cp -- "${app_dir}/share/applications/dev.zed.Zed.desktop" "${desktop}"
    icon="${app_dir}/share/icons/hicolor/512x512/apps/zed.png"
    python3 - "${desktop}" "${launcher}" "${icon}" <<'PY'
import pathlib, sys
path, launcher, icon = sys.argv[1:]
file = pathlib.Path(path)
file.write_text(
    file.read_text(encoding="utf-8")
    .replace("Exec=zed", f"Exec={launcher}")
    .replace("TryExec=zed", f"TryExec={launcher}")
    .replace("Icon=zed", f"Icon={icon}"),
    encoding="utf-8",
)
PY
  fi
  disable_auto_update || log 'left existing Zed settings unchanged'
  install -d -m 0700 "${state_home}/doors"
  printf '%s\n' "${version}" > "${version_file}"
  date --utc --iso-8601=seconds > "${stamp}"
  log "installed ${version}"
}

download() {
  local url="$1"
  local destination="$2"
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    --retry 5 --retry-delay 15 --output "${destination}" "${url}"
}

latest_release() {
  local payload
  if ! payload="$(curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    --retry 3 --retry-delay 5 \
    --header 'Accept: application/vnd.github+json' \
    --header 'User-Agent: doors-update' \
    "https://api.github.com/repos/${zed_repo}/releases/latest")"; then
    return 1
  fi
  printf '%s' "${payload}" | python3 -c '
import json, sys
data = json.load(sys.stdin)
tag = data.get("tag_name") or ""
asset = next((item for item in data.get("assets") or [] if item.get("name") == "zed-linux-x86_64.tar.gz"), None)
digest = (asset or {}).get("digest") or ""
url = (asset or {}).get("browser_download_url") or ""
if not tag.startswith("v") or not digest.startswith("sha256:"):
    raise SystemExit(2)
expected = f"https://github.com/zed-industries/zed/releases/download/{tag}/zed-linux-x86_64.tar.gz"
if url != expected:
    raise SystemExit(2)
print(f"{tag}\t{digest[7:]}")
'
}

cmd_check() {
  local current latest payload
  if [[ ! -x "${launcher}" ]]; then
    printf 'not-installed\n'
    return 0
  fi
  current="$(installed_version)"
  current="${current#v}"
  if ! payload="$(latest_release)"; then
    printf 'check-failed\tgithub-api\n'
    return 0
  fi
  latest="${payload%%$'\t'*}"
  latest="${latest#v}"
  if [[ -z "${current}" || "${current}" != "${latest}" ]]; then
    printf 'pending\t%s\t%s\n' "${current:-unknown}" "${latest}"
  else
    printf 'current\n'
  fi
}

cmd_upgrade() {
  local payload tag digest url archive current rc
  if [[ "$(uname -m)" != "x86_64" ]]; then
    log 'Zed is provisioned for the amd64 image only'
    return 1
  fi
  if ! payload="$(latest_release)"; then
    log 'could not read the latest Zed release digest'
    return 1
  fi
  tag="${payload%%$'\t'*}"
  digest="${payload#*$'\t'}"
  current="$(installed_version)"
  if [[ -x "${launcher}" && "${current}" == "${tag}" ]]; then
    log "already at ${tag}"
    return 0
  fi
  url="https://github.com/${zed_repo}/releases/download/${tag}/${zed_asset}"
  archive="$(mktemp --suffix=.tar.gz)"
  if ! download "${url}" "${archive}"; then
    rm -f -- "${archive}"
    log 'download failed'
    return 1
  fi
  install_tree "${archive}" "${tag}" "${digest}"
  rc=$?
  rm -f -- "${archive}"
  return "${rc}"
}

cmd_pinned() {
  local url archive rc
  if [[ -x "${launcher}" && -f "${stamp}" ]]; then
    log 'already installed'
    return 0
  fi
  if [[ "$(uname -m)" != "x86_64" ]]; then
    log 'Zed is provisioned for the amd64 image only'
    return 1
  fi
  url="https://github.com/${zed_repo}/releases/download/${zed_version}/${zed_asset}"
  archive="$(mktemp --suffix=.tar.gz)"
  if ! download "${url}" "${archive}"; then
    rm -f -- "${archive}"
    log 'download failed; will retry on the next login'
    return 1
  fi
  install_tree "${archive}" "${zed_version}" "${zed_sha256}"
  rc=$?
  rm -f -- "${archive}"
  return "${rc}"
}

case "${1:-}" in
  --check)
    cmd_check
    ;;
  --upgrade)
    cmd_upgrade
    ;;
  '')
    cmd_pinned
    ;;
  *)
    printf 'usage: doors-zed-install [--check|--upgrade]\n' >&2
    exit 2
    ;;
esac
