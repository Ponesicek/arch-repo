#!/usr/bin/env bash
# Bump the PKGBUILD to the latest stable Paper Desktop release.
#
# Only pkgver, _build, pkgrel and the checksum change. The version and SHA-256
# come from Paper's APT repository (hosted by ToDesktop, which builds Paper):
# InRelease must carry a valid signature from the pinned ToDesktop key in
# keys/, and the Packages index must match the hash InRelease lists for it.
# makepkg then checks the .deb against that SHA-256 on every build.
set -euo pipefail
cd "$(dirname "$0")"

apt=https://download.paper.design/apt/dists/stable
fpr=91C289D49135E691E3D7E13BD5042931F5577C5E
get() { curl --fail --silent --show-error --location "$@"; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# gpgv with a keyring holding only the pinned key: no other key can pass.
gpg --batch --quiet --dearmor --output "$work/upstream.gpg" "keys/$fpr.asc"
get --output "$work/InRelease" "$apt/InRelease"
if ! gpgv --keyring "$work/upstream.gpg" --output "$work/Release" "$work/InRelease"; then
  echo "InRelease is not signed by $fpr" >&2
  exit 1
fi
# The signed text uses CRLF line endings.
sed -i 's/\r$//' "$work/Release"

index=main/binary-amd64/Packages
expected=$(awk -v f="$index" '/^SHA256:/ { s = 1; next } /^[^ ]/ { s = 0 } s && $3 == f { print $1; exit }' "$work/Release")
if [[ ! $expected =~ ^[0-9a-f]{64}$ ]]; then
  echo "No SHA-256 for $index in InRelease" >&2
  exit 1
fi
get --output "$work/Packages" "$apt/$index"
if [[ $(sha256sum "$work/Packages" | cut -d' ' -f1) != "$expected" ]]; then
  echo "SHA-256 mismatch for $index" >&2
  exit 1
fi

# Only the signed text is used from here on.
sed -i 's/\r$//' "$work/Packages"
field() { awk -v k="$1:" '$1 == "Package:" { p = ($2 == "paper") } p && $1 == k { print $2; exit }' "$work/Packages"; }
debver=$(field Version)
filename=$(field Filename)
sha256=$(field SHA256)
if [[ ! $debver =~ ^([0-9]+(\.[0-9]+)+)-([a-z0-9]+)$ ]]; then
  echo "Unexpected Paper version: $debver" >&2
  exit 1
fi
latest=${BASH_REMATCH[1]} build=${BASH_REMATCH[3]}
if [[ $filename != "paper-desktop-${latest}-build-${build}-amd64.deb" || ! $sha256 =~ ^[0-9a-f]{64}$ ]]; then
  echo "Unexpected Packages entry: $filename $sha256" >&2
  exit 1
fi

current=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2)
current_build=$(grep -m1 '^_build=' PKGBUILD | cut -d= -f2)
cmp=$(vercmp "$latest" "$current")
if (( cmp < 0 )) || { (( cmp == 0 )) && [[ $build == "$current_build" ]]; }; then
  echo "paper-desktop is up to date ($current, build $current_build)"
  exit 0
fi

if (( cmp == 0 )); then
  # Same version, new upstream build: keep pkgver, raise pkgrel.
  echo "New build of $current: $current_build -> $build"
  pkgrel=$(( $(grep -m1 '^pkgrel=' PKGBUILD | cut -d= -f2) + 1 ))
else
  echo "New release: $current -> $latest"
  pkgrel=1
fi
sed -i -E "s/^pkgver=.*/pkgver=${latest}/; s/^_build=.*/_build=${build}/; s/^pkgrel=.*/pkgrel=${pkgrel}/; s/^sha256sums=.*/sha256sums=('${sha256}')/" PKGBUILD
