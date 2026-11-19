#!/usr/bin/env bash
# Bump the PKGBUILD to the newest Ardia release that ships a Linux .deb.
#
# Linux builds are nightlies (GitHub prereleases), and not every nightly has
# one, so this looks through recent releases rather than /releases/latest.
# Only pkgver, pkgrel and the checksum change. The SHA-256 must agree between
# the release's .sha256 file and the digest GitHub computed for the asset when
# it was uploaded; makepkg then checks the .deb against it on every build.
# Ardia publishes no signature, so this relies on HTTPS to GitHub. Ardia on
# Linux doesn't update itself (it only links to the release page).
set -euo pipefail
cd "$(dirname "$0")"

repo=ardia-browser/ardia
auth=()
[[ -n ${GH_TOKEN:-} ]] && auth=(--header "Authorization: Bearer $GH_TOKEN")
get() { curl --fail --silent --show-error --location "${auth[@]}" "$@"; }

releases=$(get "https://api.github.com/repos/$repo/releases?per_page=50")

# Every non-draft release tagged v<x.y.z> or v<x.y.z>-nightly.<n> with a Linux
# .deb, as "<version> <GitHub sha256>".
candidates=$(jq -r '
  .[] | select(.draft | not) | (.tag_name | ltrimstr("v")) as $v
  | select($v | test("^[0-9]+\\.[0-9]+\\.[0-9]+(-nightly\\.[0-9]+)?$"))
  | .assets[] | select(.name == "Ardia-\($v)-linux-x64.deb")
  | "\($v) \(.digest // "" | ltrimstr("sha256:"))"
' <<<"$releases")
if [[ -z $candidates ]]; then
  echo "No Ardia release with a Linux .deb" >&2
  exit 1
fi

latest="" digest=""
while read -r version sha; do
  pkgver=${version/-nightly/nightly}
  if [[ -z $latest ]] || (( $(vercmp "$pkgver" "${latest/-nightly/nightly}") > 0 )); then
    latest=$version digest=$sha
  fi
done <<<"$candidates"
pkgver=${latest/-nightly/nightly}

current=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2)
if (( $(vercmp "$pkgver" "$current") <= 0 )); then
  echo "ardia is up to date ($current)"
  exit 0
fi

echo "New release: $current -> $pkgver"
deb="Ardia-${latest}-linux-x64.deb"
if [[ ! $digest =~ ^[0-9a-f]{64}$ ]]; then
  echo "GitHub lists no SHA-256 for $deb" >&2
  exit 1
fi
published=$(get "https://github.com/$repo/releases/download/v${latest}/${deb}.sha256")
read -r sha256 name <<<"$published"
if [[ $name != "$deb" || $sha256 != "$digest" ]]; then
  echo "$deb.sha256 ($published) does not match GitHub's digest $digest" >&2
  exit 1
fi
echo "$deb: .sha256 file matches GitHub's digest"

sed -i -E "s/^pkgver=.*/pkgver=${pkgver}/; s/^pkgrel=.*/pkgrel=1/; s/^sha256sums=.*/sha256sums=('${sha256}')/" PKGBUILD
