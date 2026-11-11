#!/usr/bin/env bash
# Compare a package's AUR repo with the AUR commit that was last reviewed
# (stored in <pkg>/.aur-commit).
#
# - Nothing changed, or only pkgver/pkgrel/checksums changed: record the new
#   commit. The version itself comes from update.sh, not from the AUR.
# - Anything else changed: open a pull request that adopts the AUR files, with
#   the AUR diff in its description. Nothing ships until a human merges it.
set -euo pipefail

pkg=$1
name=$(basename "$pkg")
vetted=$(tr -d '[:space:]' < "$pkg/.aur-commit")

tmp=$(mktemp -d)
trap 'git worktree remove --force "$tmp/wt" 2>/dev/null || true; rm -rf "$tmp"' EXIT

git clone --quiet "https://aur.archlinux.org/$name.git" "$tmp/aur"
head=$(git -C "$tmp/aur" rev-parse HEAD)
short=${head:0:12}

if [[ $head == "$vetted" ]]; then
  echo "$name: AUR unchanged since reviewed commit ${vetted:0:12}"
  exit 0
fi

# Generated or maintainer-only files that never affect the built package.
ignored=(.SRCINFO .nvchecker.toml .gitignore)

export_tree() { # <commit> <dir>
  mkdir -p "$2"
  git -C "$tmp/aur" archive "$1" | tar -x -C "$2"
  for f in "${ignored[@]}"; do rm -f "$2/$f"; done
}

strip_versions() { # drop pkgver, pkgrel and every *sums=(...) array
  awk '
    /^(pkgver|pkgrel)=/ { next }
    /^[a-z0-9]+sums(_[A-Za-z0-9_]+)?=\(/ { skip = 1 }
    skip { if (/\)/) skip = 0; next }
    { print }
  ' "$1" > "$1.tmp"
  mv "$1.tmp" "$1"
}

export_tree "$vetted" "$tmp/old"
export_tree "$head" "$tmp/new"
cp -a "$tmp/new" "$tmp/adopt"
strip_versions "$tmp/old/PKGBUILD"
strip_versions "$tmp/new/PKGBUILD"

if diff -r "$tmp/old" "$tmp/new" > /dev/null; then
  echo "$name: AUR ${vetted:0:12}..$short only changes version/checksums"
  echo "$head" > "$pkg/.aur-commit"
  git add "$pkg/.aur-commit"
  git commit --quiet -m "$name: AUR $short only changes version/checksums"
  exit 0
fi

echo "$name: AUR ${vetted:0:12}..$short changes more than the version; opening a review PR"
branch="aur/$name-$short"

if [[ -n $(gh pr list --state open --head "$branch" --json number --jq '.[].number') ]]; then
  echo "$name: review PR for AUR $short is already open"
  exit 0
fi

# A newer AUR commit supersedes any older review PR for this package.
gh pr list --state open --json number,headRefName \
  --jq ".[] | select(.headRefName | startswith(\"aur/$name-\")) | .number" |
  while read -r number; do
    gh pr close "$number" --delete-branch --comment "Superseded by AUR commit $short."
  done

git worktree add --quiet -b "$branch" "$tmp/wt" origin/main
git -C "$tmp/aur" diff --name-only --diff-filter=D "$vetted" "$head" |
  while read -r gone; do rm -f "$tmp/wt/$pkg/$gone"; done
cp -a "$tmp/adopt/." "$tmp/wt/$pkg/"
echo "$head" > "$tmp/wt/$pkg/.aur-commit"
git -C "$tmp/wt" add -A "$pkg"
git -C "$tmp/wt" commit --quiet -m "$name: adopt AUR $short"
git -C "$tmp/wt" push --quiet origin "$branch"

aur_diff=$(git -C "$tmp/aur" diff "$vetted" "$head" -- . ':!.SRCINFO' ':!.nvchecker.toml')
if (( ${#aur_diff} > 50000 )); then
  aur_diff="${aur_diff:0:50000}
... (truncated, see the full diff in the Files changed tab)"
fi

gh pr create --base main --head "$branch" \
  --title "$name: review AUR changes ($short)" \
  --body-file - <<EOF
The AUR package \`$name\` changed more than its version and checksums since
the last reviewed commit (\`${vetted:0:12}\`). Nothing has been built from it.

**Review the diff below.** Merge this PR to adopt the changes; the next build
publishes them. Close it to keep the current packaging.

If the AUR version is older than the one in \`main\`, don't worry: the updater
bumps it to the latest JetBrains release right after merging.

AUR history: https://aur.archlinux.org/cgit/aur.git/log/?h=$name

\`\`\`diff
$aur_diff
\`\`\`
EOF
