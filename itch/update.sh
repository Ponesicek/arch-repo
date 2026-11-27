#!/usr/bin/env bash
# Bump the PKGBUILD to the latest stable itch release on GitHub.
#
# /releases/latest skips the "-canary" prereleases (kitch). Only pkgver,
# pkgrel and the tarball's checksum change. The SHA-256 is the digest GitHub
# computed for the asset when it was uploaded, and the download must match it;
# makepkg then checks the tarball against it on every build. itch publishes no
# signature or checksum file, so this relies on HTTPS to GitHub.
set -euo pipefail
cd "$(dirname "$0")"

repo=itchio/itch
auth=()
[[ -n ${GH_TOKEN:-} ]] && auth=(--header "Authorization: Bearer $GH_TOKEN")
get() { curl --fail --silent --show-error --location "$@"; }

release=$(get "${auth[@]}" "https://api.github.com/repos/$repo/releases/latest")
tag=$(jq -r .tag_name <<<"$release")
if [[ ! $tag =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
  echo "Unexpected itch release tag: $tag" >&2
  exit 1
fi
latest=${BASH_REMATCH[1]}

current=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2)
if (( $(vercmp "$latest" "$current") <= 0 )); then
  echo "itch is up to date ($current)"
  exit 0
fi

echo "New release: $current -> $latest"
tarball="itch-v${latest}-linux-amd64.tar.gz"
digest=$(jq -r --arg n "$tarball" '.assets[] | select(.name == $n) | .digest // "" | ltrimstr("sha256:")' <<<"$release")
if [[ ! $digest =~ ^[0-9a-f]{64}$ ]]; then
  echo "GitHub lists no SHA-256 for $tarball" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
get --output "$work/$tarball" "https://github.com/$repo/releases/download/$tag/$tarball"
sha256=$(sha256sum "$work/$tarball" | cut -d' ' -f1)
if [[ $sha256 != "$digest" ]]; then
  echo "$tarball ($sha256) does not match GitHub's digest $digest" >&2
  exit 1
fi
echo "$tarball: matches GitHub's digest"

# sha256sums has two entries (tarball, itch.desktop); only the first changes.
sed -i -E \
  -e "s/^pkgver=.*/pkgver=${latest}/" \
  -e "s/^pkgrel=.*/pkgrel=1/" \
  -e "s/^sha256sums=\('[0-9a-f]{64}'/sha256sums=('${sha256}'/" \
  PKGBUILD
