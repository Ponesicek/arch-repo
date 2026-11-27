#!/usr/bin/env bash
# Bump the PKGBUILD to the latest stable doop desktop release on GitHub.
#
# The repo is a monorepo whose release-please run cuts two kinds of release:
# desktop-vX.Y.Z for the desktop app and vX.Y.Z for the web app, and either
# can be GitHub's "latest". So this lists releases and takes the highest
# non-draft, non-prerelease desktop-v tag that upstream also shipped a Linux
# .deb for (proof its own desktop build of that tag succeeded).
#
# Only pkgver, pkgrel and the checksums change. The source is the release's
# git tag; makepkg records a checksum of the tagged tree, so a tag that moves
# later fails the build instead of shipping.
set -euo pipefail
cd "$(dirname "$0")"

repo=doop-design/doop
auth=()
[[ -n ${GH_TOKEN:-} ]] && auth=(--header "Authorization: Bearer $GH_TOKEN")
get() { curl --fail --silent --show-error --location "$@"; }

releases=$(get "${auth[@]}" "https://api.github.com/repos/$repo/releases?per_page=100")
latest=$(jq -r '.[]
  | select(.draft == false and .prerelease == false)
  | select(.tag_name | test("^desktop-v[0-9]+\\.[0-9]+\\.[0-9]+$"))
  | (.tag_name | ltrimstr("desktop-v")) as $v
  | select(any(.assets[]; .name == "doop_\($v)_amd64.deb"))
  | $v' <<<"$releases" | sort -V | tail -n1)
if [[ ! $latest =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "No stable doop desktop release found" >&2
  exit 1
fi

current=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2)
if (( $(vercmp "$latest" "$current") <= 0 )); then
  echo "doop is up to date ($current)"
  exit 0
fi

echo "New release: $current -> $latest"
sed -i -E "s/^pkgver=.*/pkgver=${latest}/; s/^pkgrel=.*/pkgrel=1/" PKGBUILD
updpkgsums
