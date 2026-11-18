#!/usr/bin/env bash
# Bump the PKGBUILD to the latest stable CodeAF release on GitHub.
#
# Only pkgver, pkgrel, the furrow pin and the checksums change. The source is
# the release's git tag; makepkg records a checksum of the tagged tree, so a
# tag that moves later fails the build instead of shipping. The furrow binary
# CodeAF embeds must match the sha256 pinned in the tag's
# internal/furrowbin/pin.json.
set -euo pipefail
cd "$(dirname "$0")"

repo=Agent-Field/CodeAF
auth=()
[[ -n ${GH_TOKEN:-} ]] && auth=(--header "Authorization: Bearer $GH_TOKEN")
get() { curl --fail --silent --show-error --location "$@"; }

# /releases/latest skips drafts and prereleases (CodeAF's dev-* and -rc builds).
tag=$(get "${auth[@]}" "https://api.github.com/repos/$repo/releases/latest" | jq -r .tag_name)
if [[ ! $tag =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
  echo "Unexpected CodeAF release tag: $tag" >&2
  exit 1
fi
latest=${BASH_REMATCH[1]}

current=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2)
if (( $(vercmp "$latest" "$current") <= 0 )); then
  echo "codeaf is up to date ($current)"
  exit 0
fi

echo "New release: $current -> $latest"
pin=$(get "https://raw.githubusercontent.com/$repo/$tag/internal/furrowbin/pin.json")
furrow_repo=$(jq -r .repository <<<"$pin")
furrow_tag=$(jq -r .tag <<<"$pin")
furrow_asset=$(jq -r '.artifacts["linux-amd64"].asset' <<<"$pin")
furrow_sha=$(jq -r '.artifacts["linux-amd64"].sha256' <<<"$pin")
if [[ $furrow_repo != Agent-Field/furrow || $furrow_asset != furrow-linux-amd64 \
      || ! $furrow_tag =~ ^v[0-9.]+$ || ! $furrow_sha =~ ^[0-9a-f]{64}$ ]]; then
  echo "Unexpected furrow pin in $tag; review the PKGBUILD by hand:" >&2
  echo "$pin" >&2
  exit 1
fi

furrow="furrow-${furrow_tag}-linux-amd64"
get --output "$furrow" "https://github.com/$furrow_repo/releases/download/$furrow_tag/$furrow_asset"
if [[ $(sha256sum "$furrow" | cut -d' ' -f1) != "$furrow_sha" ]]; then
  echo "SHA-256 mismatch for $furrow" >&2
  rm -f "$furrow"
  exit 1
fi
echo "$furrow: SHA-256 matches pin.json at $tag"

sed -i -E "s/^pkgver=.*/pkgver=${latest}/; s/^pkgrel=.*/pkgrel=1/; s/^_furrow_tag=.*/_furrow_tag=${furrow_tag}/" PKGBUILD
updpkgsums
