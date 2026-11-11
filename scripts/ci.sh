#!/usr/bin/env bash
# CI entry point. Runs as the unprivileged "builder" user inside an Arch
# container: processes every package directory, then pushes any commits.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

export REPO_NAME=ponesicek RELEASE_TAG=repo
export PACKAGER='Ponesicek arch-repo CI <ponesicek@users.noreply.github.com>'

: "${GPG_PRIVATE_KEY:?The GPG_PRIVATE_KEY repository secret is not set}"
: "${GH_TOKEN:?}" "${GH_REPO:?}"
gpg --batch --quiet --import <<<"$GPG_PRIVATE_KEY"
GPGKEY=$(gpg --list-secret-keys --with-colons | awk -F: '$1 == "fpr" { print $10; exit }')
export GPGKEY

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git remote set-url origin "https://x-access-token:${GH_TOKEN}@github.com/${GH_REPO}.git"

failed=()
for pkgbuild in */PKGBUILD; do
  pkg=${pkgbuild%/PKGBUILD}
  echo "::group::$pkg"
  scripts/package.sh "$pkg" || failed+=("$pkg")
  echo "::endgroup::"
done

if [[ -n $(git log --oneline origin/main..HEAD) ]]; then
  git pull --quiet --rebase origin main
  git push --quiet origin HEAD:main
fi

if (( ${#failed[@]} )); then
  echo "::error::Failed packages: ${failed[*]}"
  exit 1
fi
