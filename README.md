# arch-repo

A personal, signed pacman repository built by GitHub Actions. It replaces AUR
packages that would otherwise be built on your machine with `yay`, without
you ever seeing the PKGBUILD.

| Package | Upstream | Packaging based on |
|---|---|---|
| `jetbrains-toolbox` | [JetBrains Toolbox App](https://www.jetbrains.com/toolbox-app/) | [AUR `jetbrains-toolbox`](https://aur.archlinux.org/packages/jetbrains-toolbox) |

## How it keeps updates safe

Every 6 hours the [`Update packages`](.github/workflows/update.yml) workflow
does the following for each package:

1. **New upstream release → shipped automatically.**
   [`update.sh`](jetbrains-toolbox/update.sh) asks the JetBrains API for the
   latest stable release. It downloads the tarball and checks it against the
   SHA-256 that JetBrains publishes. Then it changes **only** `pkgver`, `pkgrel`
   and the checksum in the PKGBUILD. The package is built in a clean Arch
   container, signed, and published.
2. **AUR packaging change → waits for you.**
   [`aur-watch.sh`](scripts/aur-watch.sh) compares the AUR package with the
   AUR commit you last reviewed, stored in
   [`.aur-commit`](jetbrains-toolbox/.aur-commit).
   - If the AUR only bumped the version or checksums, it records the new
     commit and does nothing else.
   - If **anything else** changed (dependencies, install steps, the desktop
     file, new files…), it opens a **pull request** with the AUR diff. Nothing
     from that change is built until you merge it.

Your machine only installs packages signed by this repo's key, and pacman
refuses anything else.

## Setting it up on your machine

### 1. Trust the repository's signing key

```bash
curl -fsSLo /tmp/ponesicek-repo.asc \
  https://raw.githubusercontent.com/Ponesicek/arch-repo/main/keys/ponesicek-repo.asc
sudo pacman-key --add /tmp/ponesicek-repo.asc
sudo pacman-key --finger 6273CDBBCA715712CE7DD4B81301AD4BF1EC0E50
```

Check that the fingerprint printed is exactly:

```
6273 CDBB CA71 5712 CE7D  D4B8 1301 AD4B F1EC 0E50
```

Then sign it locally, so pacman trusts it:

```bash
sudo pacman-key --lsign-key 6273CDBBCA715712CE7DD4B81301AD4BF1EC0E50
```

### 2. Add the repository to pacman

Put the repo definition in its own file:

```bash
sudo tee /etc/pacman.d/ponesicek.conf > /dev/null <<'EOF'
[ponesicek]
SigLevel = Required
Server = https://github.com/Ponesicek/arch-repo/releases/download/repo
EOF
```

`SigLevel = Required` makes pacman reject any package or database that isn't
signed by a trusted key.

Then include it at the **end** of `/etc/pacman.conf`. Official repositories
come first, so they always win if a package exists in both:

```bash
echo 'Include = /etc/pacman.d/ponesicek.conf' | sudo tee -a /etc/pacman.conf
```

**Omarchy:** `omarchy refresh pacman` rewrites `/etc/pacman.conf` from a
template, which would drop that line. Add a hook that puts it back every time:

```bash
cat > ~/.config/omarchy/hooks/pre-refresh-pacman.d/ponesicek-repo <<'EOF'
#!/bin/bash
# Re-add the ponesicek repo after Omarchy rewrites pacman.conf.
LINE='Include = /etc/pacman.d/ponesicek.conf'
[[ -r /etc/pacman.d/ponesicek.conf ]] || exit 0
grep -qxF "$LINE" /etc/pacman.conf || echo "$LINE" | sudo tee -a /etc/pacman.conf > /dev/null
EOF
chmod +x ~/.config/omarchy/hooks/pre-refresh-pacman.d/ponesicek-repo
```

### 3. Install (or switch over from the AUR)

```bash
sudo pacman -Sy
sudo pacman -S ponesicek/jetbrains-toolbox
```

If you already had `jetbrains-toolbox` from the AUR, this replaces it with the
copy from this repo. Your Toolbox settings and installed IDEs live in your home
directory and are not touched. Check that it worked:

```bash
pacman -Qi jetbrains-toolbox | grep -E '^(Version|Packager|Validated By)'
pacman -Qm | grep jetbrains-toolbox || echo "not an AUR/foreign package anymore ✓"
```

### 4. Updating

Nothing new to learn. Omarchy's updater (and `sudo pacman -Syu`) now upgrades
Toolbox like any official package. Omarchy's AUR step (`yay -Sua`) only touches
*foreign* packages, so it no longer builds Toolbox.

## When a review PR shows up

GitHub notifies you when the workflow opens a PR titled
`jetbrains-toolbox: review AUR changes (…)`. It means the AUR maintainer changed
something other than the version.

1. Read the diff in the PR description. It is exactly what changed on the AUR
   since the commit you last accepted. Look out for new `source=` URLs, new
   `install=` scripts, `curl`/`wget` in `package()`, or anything you can't
   explain.
2. **Looks fine → Merge.** The workflow runs on the merge, bumps to the latest
   JetBrains release if needed, and publishes a new build.
3. **Looks wrong → Close.** Nothing changes. You'll get a new PR if the AUR
   changes again.

A newer AUR change automatically closes an older review PR for the same
package.

## Maintenance

- **Run it now:** Actions → *Update packages* → *Run workflow*, or
  `gh workflow run update.yml -R Ponesicek/arch-repo`.
- **See what got published:** the [`repo` release](https://github.com/Ponesicek/arch-repo/releases/tag/repo).
  It holds the newest build of each package plus the signed `ponesicek.db`.
- **Failed runs:** GitHub emails you. A failed run publishes nothing, so
  your machine keeps the last good version.
- **Schedule turned off?** GitHub disables scheduled workflows after 60 days
  without repo activity. The workflow re-enables itself on every scheduled run,
  and each update commits to `main`. If it ever shows as disabled anyway,
  click *Enable workflow* on the Actions tab.
- **Pushing a packaging fix yourself:** edit the PKGBUILD, raise `pkgrel`, and
  push to `main`. The push triggers a build.

### The signing key

The private key exists only as the `GPG_PRIVATE_KEY` repository secret. It has
no passphrase (CI must use it unattended) and is used for nothing else. If it
is ever exposed, or you want to rotate it:

1. Generate a new key and replace the secret:
   ```bash
   export GNUPGHOME=$(mktemp -d)
   gpg --batch --passphrase '' --quick-gen-key 'Ponesicek pacman repo <ponesicek@users.noreply.github.com>' ed25519 sign never
   gpg --armor --export-secret-keys | gh secret set GPG_PRIVATE_KEY -R Ponesicek/arch-repo
   gpg --armor --export > keys/ponesicek-repo.asc
   rm -rf "$GNUPGHOME"
   ```
2. Update the fingerprint in this README, then commit and push. Pushing
   republishes nothing on its own, so raise `pkgrel` to force a re-signed build.
   Also delete `ponesicek.db*` and `ponesicek.files*` from the `repo` release
   first: they are signed with the old key, and the workflow refuses to extend
   them.
3. On your machine: `sudo pacman-key --delete <old fingerprint>`, then repeat
   step 1 of the setup.

## Adding another package

1. Create a directory named after the package with its PKGBUILD and source
   files. To base it on the AUR, copy the files from
   `git clone https://aur.archlinux.org/<name>.git` after reading them, and
   write that commit's hash to `<name>/.aur-commit`.
2. Add an executable `<name>/update.sh` that bumps `pkgver` and the checksums
   when upstream releases, and verifies the download against an upstream
   checksum or signature. [`jetbrains-toolbox/update.sh`](jetbrains-toolbox/update.sh)
   is the template.
3. Push. The workflow picks up every `*/PKGBUILD` automatically.

## Layout

```
.github/workflows/update.yml   schedule + push trigger, Arch container
scripts/ci.sh                  entry point: loops over packages, pushes commits
scripts/package.sh             per package: AUR watch → update → publish
scripts/aur-watch.sh           version-only AUR change → record, else review PR
scripts/publish.sh             makepkg --sign, repo-add --sign, upload to release
keys/ponesicek-repo.asc        public signing key
jetbrains-toolbox/             PKGBUILD + files from the AUR, update.sh, .aur-commit
```
