#!/usr/bin/env bash
# Build the latest official wl-clip-persist release in the disposable stage.
# Upstream publishes source only. Cargo uses the release's committed Cargo.lock;
# the release tag is resolved to an immutable commit before building.
set -euo pipefail

readonly REPOSITORY='Linus789/wl-clip-persist'
readonly REPOSITORY_URL="https://github.com/${REPOSITORY}.git"
readonly API_URL="https://api.github.com/repos/${REPOSITORY}/releases/latest"
readonly OUT_DIR='/out'

mkdir -p "${OUT_DIR}"
dnf5 install -y --setopt=install_weak_deps=False cargo gcc make git jq

release_json="$(curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --silent --show-error "${API_URL}")"
tag="$(jq --raw-output '.tag_name // empty' <<<"${release_json}")"
if [[ ! "${tag}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Unexpected wl-clip-persist release tag: ${tag:-<empty>}" >&2
  exit 1
fi

# An annotated tag needs its peeled object; a lightweight tag is its object.
commit="$(git ls-remote "${REPOSITORY_URL}" "refs/tags/${tag}^{}" | awk 'NR == 1 { print $1 }')"
if [[ -z "${commit}" ]]; then
  commit="$(git ls-remote "${REPOSITORY_URL}" "refs/tags/${tag}" | awk 'NR == 1 { print $1 }')"
fi
if [[ ! "${commit}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Could not resolve ${REPOSITORY} ${tag} to an immutable commit" >&2
  exit 1
fi

export CARGO_HOME='/tmp/cargo-home'
export CARGO_TARGET_DIR='/tmp/cargo-target'
cargo install --locked --git "${REPOSITORY_URL}" --rev "${commit}" --root /tmp/wl-clip-persist-root wl-clip-persist
install -D -m 0755 /tmp/wl-clip-persist-root/bin/wl-clip-persist "${OUT_DIR}/wl-clip-persist"
"${OUT_DIR}/wl-clip-persist" --help >/dev/null

cat > "${OUT_DIR}/wl-clip-persist.buildinfo" <<INFO
repository=${REPOSITORY}
tag=${tag}
commit=${commit}
INFO
