#!/usr/bin/env bash
# hbak fork: move the hbak/patches commits onto the newest upstream AeroSpace release, rebuild,
# install, and push. Stops on a rebase conflict (resolve, `git rebase --continue`, re-run).
set -euo pipefail
cd "$(dirname "$0")"
git fetch -q upstream --tags
latest=$(git tag -l 'v*' --sort=-v:refname | head -1)
base=$(git describe --tags --abbrev=0 --match 'v*')
if [[ "$latest" == "$base" ]]; then
  echo "already on $latest"
  exit 0
fi
echo "rebasing hbak/patches: $base -> $latest"
git rebase --onto "$latest" "$base" hbak/patches
./hbak-build.sh --install
git push --force-with-lease origin hbak/patches
