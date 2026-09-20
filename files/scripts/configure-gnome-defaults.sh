#!/usr/bin/env bash
# Compile user-overridable dconf defaults only after every extension schema is
# present. Verify UUID directories rather than assuming extension packaging.
set -euo pipefail

readonly extensions_root='/usr/share/gnome-shell/extensions'
readonly -a required_extensions=(
  'dash-to-dock@micxgx.gmail.com'
  'appindicatorsupport@rgcjonas.gmail.com'
  'gsconnect@andyholmes.github.io'
  'clipboard-indicator@tudmotu.com'
  'grand-theft-focus@zalckos.github.com'
  'just-perfection-desktop@just-perfection'
  'AlphabeticalAppGrid@stuarthayhurst'
  'vicinae@dagimg-dot.netlify.app'
  'emoji-copy@felipeftn'
)

for extension in "${required_extensions[@]}"; do
  [[ -d "${extensions_root}/${extension}" ]] || {
    echo "Required GNOME extension is missing: ${extension}" >&2
    exit 1
  }
done

dconf update
[[ -s /etc/dconf/db/local ]] || { echo 'dconf system defaults did not compile' >&2; exit 1; }
