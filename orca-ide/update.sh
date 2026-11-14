#!/usr/bin/env bash
# Bump the PKGBUILD to the latest stable Orca release on GitHub.
#
# Only pkgver, pkgrel and the checksums change. The .deb is verified against
# the SHA-512 that Orca's release publishes in latest-linux.yml (the file its
# own updater trusts) before its checksum is written into the PKGBUILD.
set -euo pipefail
cd "$(dirname "$0")"

repo=stablyai/orca
auth=()
[[ -n ${GH_TOKEN:-} ]] && auth=(--header "Authorization: Bearer $GH_TOKEN")
get() { curl --fail --silent --show-error --location "${auth[@]}" "$@"; }

# /releases/latest skips drafts and prereleases.
tag=$(get "https://api.github.com/repos/$repo/releases/latest" | jq -r .tag_name)
if [[ ! $tag =~ ^v([0-9]+(\.[0-9]+)+)$ ]]; then
  echo "Unexpected Orca release tag: $tag" >&2
  exit 1
fi
latest=${BASH_REMATCH[1]}

current=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2)
if (( $(vercmp "$latest" "$current") <= 0 )); then
  echo "orca-ide is up to date ($current)"
  exit 0
fi

echo "New release: $current -> $latest"
base="https://github.com/$repo/releases/download/$tag"
deb="orca-ide_${latest}_amd64.deb"

yml=$(curl --fail --silent --show-error --location "$base/latest-linux.yml")
if [[ $(awk '/^version:/ { print $2 }' <<<"$yml") != "$latest" ]]; then
  echo "latest-linux.yml does not describe $latest" >&2
  exit 1
fi
expected=$(awk -v f="$deb" '$NF == f { found = 1; next } found && $1 == "sha512:" { print $2; exit }' <<<"$yml")
if [[ -z $expected ]]; then
  echo "No SHA-512 for $deb in latest-linux.yml" >&2
  exit 1
fi

curl --fail --silent --show-error --location --output "$deb" "$base/$deb"
actual=$(openssl dgst -sha512 -binary "$deb" | base64 -w0)
if [[ $actual != "$expected" ]]; then
  echo "SHA-512 mismatch for $deb" >&2
  rm -f "$deb"
  exit 1
fi
echo "$deb: SHA-512 matches latest-linux.yml"

sed -i -E "s/^pkgver=.*/pkgver=${latest}/; s/^pkgrel=.*/pkgrel=1/" PKGBUILD
updpkgsums
