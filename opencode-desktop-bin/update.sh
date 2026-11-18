#!/usr/bin/env bash
# Bump the PKGBUILD to the latest OpenCode desktop release.
#
# Only pkgver, pkgrel and the checksums change. Both .debs are verified
# against the SHA-256 and SHA-512 that OpenCode's update API publishes (the
# metadata its own updater trusts) before their checksums are written into
# the PKGBUILD.
set -euo pipefail
cd "$(dirname "$0")"

json=$(curl --fail --silent --show-error --location \
  https://opencode.ai/update/api/latest/desktop/opencode)

latest=$(jq -r .version <<<"$json")
if [[ ! $latest =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
  echo "Unexpected version from the OpenCode update API: $latest" >&2
  exit 1
fi
if [[ $(jq -r '.channel + " " + (.active | tostring)' <<<"$json") != 'latest true' ]]; then
  echo "The OpenCode update API did not return an active stable release" >&2
  exit 1
fi

current=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2)
if (( $(vercmp "$latest" "$current") <= 0 )); then
  echo "opencode-desktop-bin is up to date ($current)"
  exit 0
fi

echo "New release: $current -> $latest"
for debarch in amd64 arm64; do
  name="opencode-desktop-linux-$debarch.deb"
  url="https://opencode.ai/files/bin/$latest/$name"
  # The local name matches the PKGBUILD source, so updpkgsums reuses this file.
  file="opencode-desktop-$latest-linux-$debarch.deb"

  meta=$(jq --arg n "$name" '.metadata.files[$n]' <<<"$json")
  if [[ $(jq -r .url <<<"$meta") != "$url" ]]; then
    echo "Unexpected download URL for $name: $(jq -r .url <<<"$meta")" >&2
    exit 1
  fi
  sha256=$(jq -r .sha256 <<<"$meta")
  sha512=$(jq -r --arg u "$url" \
    '.metadata.manifests[].files[]? | select(.url == $u) | .sha512' <<<"$json" | head -n1)
  if [[ ! $sha256 =~ ^[0-9a-f]{64}$ || -z $sha512 ]]; then
    echo "No checksums for $name in the update API" >&2
    exit 1
  fi

  curl --fail --silent --show-error --location --output "$file" "$url"
  if ! echo "$sha256  $file" | sha256sum --check --strict --quiet - ||
     [[ $(openssl dgst -sha512 -binary "$file" | base64 -w0) != "$sha512" ]]; then
    echo "Checksum mismatch for $file" >&2
    rm -f "$file"
    exit 1
  fi
  echo "$file: SHA-256 and SHA-512 match the update API"
done

sed -i -E "s/^pkgver=.*/pkgver=${latest}/; s/^pkgrel=.*/pkgrel=1/" PKGBUILD
updpkgsums
