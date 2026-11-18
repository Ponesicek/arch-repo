#!/usr/bin/env bash
# Remove packages from the pacman repository whose directory no longer exists
# here: drop them from the signed database, then delete their release assets.
set -euo pipefail
shopt -s extglob

: "${REPO_NAME:?}" "${RELEASE_TAG:?}" "${GPGKEY:?}"
cd "$(git rev-parse --show-toplevel)"

assets=$(gh release view "$RELEASE_TAG" --json assets --jq '.assets[].name')
grep -Fxq "$REPO_NAME.db.tar.gz" <<<"$assets" || exit 0

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for db in "$REPO_NAME.db.tar.gz" "$REPO_NAME.files.tar.gz"; do
  gh release download "$RELEASE_TAG" --dir "$work" --pattern "$db" --pattern "$db.sig"
done

wanted=$(for pkgbuild in */PKGBUILD; do
  grep -m1 '^pkgname=' "$pkgbuild" | cut -d= -f2 | tr -d "'\""
done | sort -u)
published=$(tar -xOzf "$work/$REPO_NAME.db.tar.gz" --wildcards '*/desc' |
  awk 'prev == "%NAME%" { print } { prev = $0 }' | sort -u)
mapfile -t stale < <(comm -13 <(echo "$wanted") <(echo "$published"))
(( ${#stale[@]} )) || exit 0

echo "Removing from the repository: ${stale[*]}"
# --verify refuses to touch a database whose signature doesn't check out.
repo-remove --quiet --sign --key "$GPGKEY" --verify "$work/$REPO_NAME.db.tar.gz" "${stale[@]}"
for ext in db files; do
  cp --remove-destination "$work/$REPO_NAME.$ext.tar.gz" "$work/$REPO_NAME.$ext"
  cp --remove-destination "$work/$REPO_NAME.$ext.tar.gz.sig" "$work/$REPO_NAME.$ext.sig"
done
# Databases first, so nothing points at a package file that is gone.
gh release upload "$RELEASE_TAG" --clobber \
  "$work/$REPO_NAME".{db,files}{,.sig} "$work/$REPO_NAME".{db,files}.tar.gz{,.sig}

for name in "${stale[@]}"; do
  while read -r asset; do
    [[ $asset == "$name"-+([^-])-+([^-])-+([^-]).pkg.tar.zst?(.sig) ]] || continue
    gh release delete-asset "$RELEASE_TAG" "$asset" --yes
  done <<<"$assets"
done
