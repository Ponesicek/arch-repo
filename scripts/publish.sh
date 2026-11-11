#!/usr/bin/env bash
# Build, sign and upload one package to the pacman repository (the GitHub
# release named $RELEASE_TAG), unless that exact version is already there.
set -euo pipefail
shopt -s extglob

pkg=$1
: "${REPO_NAME:?}" "${RELEASE_TAG:?}" "${GPGKEY:?}"
cd "$(git rev-parse --show-toplevel)/$pkg"

pkgname=$(grep -m1 '^pkgname=' PKGBUILD | cut -d= -f2 | tr -d "'\"")
pkgfile=$(makepkg --packagelist | head -n1)
file=$(basename "$pkgfile")

if ! gh release view "$RELEASE_TAG" > /dev/null 2>&1; then
  gh release create "$RELEASE_TAG" --title 'Pacman repository' \
    --notes 'Signed pacman repository. See the README for setup.'
fi
assets=$(gh release view "$RELEASE_TAG" --json assets --jq '.assets[].name')

if grep -Fxq "$file" <<<"$assets"; then
  echo "$file is already published"
  exit 0
fi

makepkg --nodeps --cleanbuild --clean --force --sign --noconfirm

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for db in "$REPO_NAME.db.tar.gz" "$REPO_NAME.files.tar.gz"; do
  if grep -Fxq "$db" <<<"$assets"; then
    gh release download "$RELEASE_TAG" --dir "$work" --pattern "$db" --pattern "$db.sig"
  fi
done

cp "$pkgfile" "$pkgfile.sig" "$work/"
# --verify refuses to extend a database whose signature doesn't check out.
repo-add --quiet --sign --key "$GPGKEY" --verify "$work/$REPO_NAME.db.tar.gz" "$work/$file"

# repo-add makes <repo>.db and <repo>.files symlinks; release assets must be files.
for ext in db files; do
  cp --remove-destination "$work/$REPO_NAME.$ext.tar.gz" "$work/$REPO_NAME.$ext"
  cp --remove-destination "$work/$REPO_NAME.$ext.tar.gz.sig" "$work/$REPO_NAME.$ext.sig"
done

# Package first, then the databases that point at it.
gh release upload "$RELEASE_TAG" --clobber "$work/$file" "$work/$file.sig"
gh release upload "$RELEASE_TAG" --clobber \
  "$work/$REPO_NAME".{db,files}{,.sig} "$work/$REPO_NAME".{db,files}.tar.gz{,.sig}

# Remove this package's older builds (<pkgname>-<ver>-<rel>-<arch>.pkg.tar.zst).
while read -r asset; do
  [[ $asset == "$pkgname"-+([^-])-+([^-])-+([^-]).pkg.tar.zst?(.sig) ]] || continue
  [[ $asset == "$file" || $asset == "$file.sig" ]] && continue
  gh release delete-asset "$RELEASE_TAG" "$asset" --yes
done <<<"$assets"

echo "Published $file"
