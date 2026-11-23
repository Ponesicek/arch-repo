#!/usr/bin/env bash
# Bump the PKGBUILD to the latest Ladybird release in upstream's APT repository.
#
# The PKGBUILD is the AUR's ladybird-bin (see .aur-commit). Only pkgver,
# _debrel, pkgrel and the checksums change here. The version and the SHA-256
# of each .deb come from Ladybird's APT repository: InRelease must carry a
# valid signature from the pinned Ladybird key in keys/, and each Packages
# index must match the hash InRelease lists for it. makepkg then checks the
# .deb against that SHA-256 on every build.
set -euo pipefail
cd "$(dirname "$0")"

apt=https://apt.ladybird.org
suite=resolute # Ubuntu 26.04, the build the AUR PKGBUILD uses
fpr=4F3D5DFE64EBD9BB35D58FBDCF9EF7324C4B27AE
get() { curl --fail --silent --show-error --location "$@"; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# gpgv with a keyring holding only the pinned key: no other key can pass.
gpg --batch --quiet --dearmor --output "$work/upstream.gpg" "keys/$fpr.asc"
get --output "$work/InRelease" "$apt/dists/$suite/InRelease"
if ! gpgv --keyring "$work/upstream.gpg" --output "$work/Release" "$work/InRelease"; then
  echo "InRelease is not signed by $fpr" >&2
  exit 1
fi

# Prints "<version> <filename> <sha256>" of the newest ladybird in the index
# for one Debian architecture, from signed text only.
newest() { # <debarch>
  local index=main/binary-$1/Packages expected
  expected=$(awk -v f="$index" '/^SHA256:/ { s = 1; next } /^[^ ]/ { s = 0 } s && $3 == f { print $1; exit }' "$work/Release")
  if [[ ! $expected =~ ^[0-9a-f]{64}$ ]]; then
    echo "No SHA-256 for $index in InRelease" >&2
    return 1
  fi
  get --output "$work/Packages-$1" "$apt/dists/$suite/$index"
  if [[ $(sha256sum "$work/Packages-$1" | cut -d' ' -f1) != "$expected" ]]; then
    echo "SHA-256 mismatch for $index" >&2
    return 1
  fi
  awk '
    $1 == "Package:" { p = ($2 == "ladybird") }
    p && $1 == "Version:" { v = $2 }
    p && $1 == "Filename:" { f = $2 }
    p && $1 == "SHA256:" { h = $2 }
    /^$/ { if (p && v != "") print v, f, h; p = 0; v = f = h = "" }
    END { if (p && v != "") print v, f, h }
  ' "$work/Packages-$1" | sort -V | tail -n1
}

read -r debver filename sha_amd64 < <(newest amd64)
read -r debver_arm filename_arm sha_arm64 < <(newest arm64)

if [[ ! $debver =~ ^([0-9]+(\.[0-9]+)+)-([0-9]+~ubuntu[0-9.]+)$ ]]; then
  echo "Unexpected Ladybird version: $debver" >&2
  exit 1
fi
latest=${BASH_REMATCH[1]} debrel=${BASH_REMATCH[3]}
if [[ $filename != "pool/main/l/ladybird/ladybird_${debver}_amd64.deb" || ! $sha_amd64 =~ ^[0-9a-f]{64}$ ]]; then
  echo "Unexpected amd64 Packages entry: $filename $sha_amd64" >&2
  exit 1
fi
if [[ $debver_arm != "$debver" || $filename_arm != "pool/main/l/ladybird/ladybird_${debver}_arm64.deb" || ! $sha_arm64 =~ ^[0-9a-f]{64}$ ]]; then
  echo "arm64 entry doesn't match amd64: $debver_arm $filename_arm $sha_arm64" >&2
  exit 1
fi

current=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2)
current_debrel=$(grep -m1 '^_debrel=' PKGBUILD | cut -d= -f2)
cmp=$(vercmp "$latest" "$current")
if (( cmp < 0 )) || { (( cmp == 0 )) && [[ $debrel == "$current_debrel" ]]; }; then
  echo "ladybird-bin is up to date ($current-$current_debrel)"
  exit 0
fi

if (( cmp == 0 )); then
  # Same version, new Debian revision: keep pkgver, raise pkgrel.
  echo "New Debian revision of $current: $current_debrel -> $debrel"
  pkgrel=$(( $(grep -m1 '^pkgrel=' PKGBUILD | cut -d= -f2) + 1 ))
else
  echo "New release: $current -> $latest"
  pkgrel=1
fi

# The LICENSE comes from the release tag on GitHub (HTTPS only).
license_sum=$(get "https://raw.githubusercontent.com/LadybirdBrowser/ladybird/${latest}/LICENSE" | sha256sum | cut -d' ' -f1)

sed -i -E \
  -e "s/^pkgver=.*/pkgver=${latest}/" \
  -e "s/^_debrel=.*/_debrel=${debrel}/" \
  -e "s/^pkgrel=.*/pkgrel=${pkgrel}/" \
  -e "s/^sha256sums=.*/sha256sums=('${license_sum}')/" \
  -e "s/^sha256sums_x86_64=.*/sha256sums_x86_64=('${sha_amd64}')/" \
  -e "s/^sha256sums_aarch64=.*/sha256sums_aarch64=('${sha_arm64}')/" \
  PKGBUILD
