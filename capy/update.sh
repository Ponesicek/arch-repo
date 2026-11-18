#!/usr/bin/env bash
# Bump the PKGBUILD to the latest stable Capy release.
#
# Only pkgver, pkgrel and the checksums change. latest-linux.yml is the file
# Capy's own updater reads; the .deb is checked against the SHA-512 it lists
# before its checksum is written into the PKGBUILD. Capy publishes no signature,
# so this relies on HTTPS to downloads.capy.ai.
set -euo pipefail
cd "$(dirname "$0")"

base=https://downloads.capy.ai/stable
get() { curl --fail --silent --show-error --location "$@"; }

yml=$(get "$base/latest-linux.yml")
latest=$(awk '/^version:/ { print $2; exit }' <<<"$yml")
if [[ ! $latest =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
  echo "Unexpected Capy version: $latest" >&2
  exit 1
fi

current=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2)
if (( $(vercmp "$latest" "$current") <= 0 )); then
  echo "capy is up to date ($current)"
  exit 0
fi

echo "New release: $current -> $latest"
deb="capy-${latest}-amd64.deb"
expected=$(awk -v f="$deb" '$NF == f { found = 1; next } found && $1 == "sha512:" { print $2; exit }' <<<"$yml")
if [[ -z $expected ]]; then
  echo "No SHA-512 for $deb in latest-linux.yml" >&2
  exit 1
fi

get --output "$deb" "$base/$deb"
actual=$(openssl dgst -sha512 -binary "$deb" | base64 -w0)
if [[ $actual != "$expected" ]]; then
  echo "SHA-512 mismatch for $deb" >&2
  rm -f "$deb"
  exit 1
fi
echo "$deb: SHA-512 matches latest-linux.yml"

sed -i -E "s/^pkgver=.*/pkgver=${latest}/; s/^pkgrel=.*/pkgrel=1/" PKGBUILD
updpkgsums
