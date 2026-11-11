#!/usr/bin/env bash
# Bump the PKGBUILD to the latest stable JetBrains Toolbox release.
#
# Only pkgver, pkgrel and the tarball checksum change. The tarball is
# verified against the SHA-256 that JetBrains publishes before its
# checksum is written into the PKGBUILD.
set -euo pipefail
cd "$(dirname "$0")"

api='https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release'
json=$(curl --fail --silent --show-error --location "$api")

latest=$(jq -r '.TBA[0].build' <<<"$json")
link=$(jq -r '.TBA[0].downloads.linux.link' <<<"$json")
sum_link=$(jq -r '.TBA[0].downloads.linux.checksumLink' <<<"$json")

if [[ ! $latest =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
  echo "Unexpected version from JetBrains API: $latest" >&2
  exit 1
fi

current=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2)
if (( $(vercmp "$latest" "$current") <= 0 )); then
  echo "jetbrains-toolbox is up to date ($current)"
  exit 0
fi

file="jetbrains-toolbox-${latest}.tar.gz"
if [[ $link != "https://download.jetbrains.com/toolbox/$file" ]]; then
  echo "Unexpected download URL from JetBrains API: $link" >&2
  exit 1
fi

echo "New release: $current -> $latest"
curl --fail --silent --show-error --location --output "$file" "$link"
expected=$(curl --fail --silent --show-error --location "$sum_link" | awk '{ print $1 }')
echo "$expected  $file" | sha256sum --check --strict -

sed -i -E "s/^pkgver=.*/pkgver=${latest}/; s/^pkgrel=.*/pkgrel=1/" PKGBUILD
updpkgsums
