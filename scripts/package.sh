#!/usr/bin/env bash
# Process one package directory: check the AUR for packaging changes, bump to
# the latest upstream release, then build and publish if needed.
set -euo pipefail

pkg=$1
cd "$(git rev-parse --show-toplevel)"

if [[ -f $pkg/.aur-commit ]]; then
  scripts/aur-watch.sh "$pkg"
fi

if [[ -x $pkg/update.sh ]]; then
  "$pkg/update.sh"
  if ! git diff --quiet -- "$pkg"; then
    version=$(grep -m1 '^pkgver=' "$pkg/PKGBUILD" | cut -d= -f2)
    git add -- "$pkg"
    git commit --quiet -m "$pkg: update to $version"
  fi
fi

scripts/publish.sh "$pkg"
