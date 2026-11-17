#!/usr/bin/env bash
# Bump the PKGBUILD to the latest stable ArtCraft Launcher release on GitHub.
#
# Only pkgver, pkgrel and the checksums change. Before the new checksum is
# written, the release's SHA256SUMS.txt must carry a valid signature from the
# pinned upstream key in keys/pgp/, and the package must match it. makepkg
# then checks the package's own signature again on every build.
set -euo pipefail
cd "$(dirname "$0")"

repo=storytold/craft-launcher
fpr=2B76741B414AAD6CD33E631213A005C0B9D7C3ED
auth=()
[[ -n ${GH_TOKEN:-} ]] && auth=(--header "Authorization: Bearer $GH_TOKEN")
get() { curl --fail --silent --show-error --location "$@"; }

# /releases/latest skips drafts and prereleases.
tag=$(get "${auth[@]}" "https://api.github.com/repos/$repo/releases/latest" | jq -r .tag_name)
if [[ ! $tag =~ ^v([0-9]+(\.[0-9]+)+)$ ]]; then
  echo "Unexpected ArtCraft Launcher release tag: $tag" >&2
  exit 1
fi
latest=${BASH_REMATCH[1]}

current=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2)
if (( $(vercmp "$latest" "$current") <= 0 )); then
  echo "artcraft-launcher is up to date ($current)"
  exit 0
fi

echo "New release: $current -> $latest"
base="https://github.com/$repo/releases/download/$tag"
pkg="artcraft-launcher-${latest}-linux-x86_64.pkg.tar.zst"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# gpgv with a keyring holding only the pinned key: no other key can pass.
gpg --batch --quiet --dearmor --output "$work/upstream.gpg" "keys/pgp/$fpr.asc"
get --output "$work/SHA256SUMS.txt" "$base/SHA256SUMS.txt"
get --output "$work/SHA256SUMS.txt.asc" "$base/SHA256SUMS.txt.asc"
if ! gpgv --keyring "$work/upstream.gpg" "$work/SHA256SUMS.txt.asc" "$work/SHA256SUMS.txt"; then
  echo "SHA256SUMS.txt is not signed by $fpr" >&2
  exit 1
fi

expected=$(awk -v f="$pkg" '$2 == f || $2 == "*" f { print $1; exit }' "$work/SHA256SUMS.txt")
if [[ ! $expected =~ ^[0-9a-f]{64}$ ]]; then
  echo "No SHA-256 for $pkg in SHA256SUMS.txt" >&2
  exit 1
fi

get --output "$pkg" "$base/$pkg"
if [[ $(sha256sum "$pkg" | cut -d' ' -f1) != "$expected" ]]; then
  echo "SHA-256 mismatch for $pkg" >&2
  rm -f "$pkg"
  exit 1
fi
echo "$pkg: SHA-256 matches the signed SHA256SUMS.txt"

sed -i -E "s/^pkgver=.*/pkgver=${latest}/; s/^pkgrel=.*/pkgrel=1/" PKGBUILD
updpkgsums
