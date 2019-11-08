#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2019 Serokell <https://serokell.io>
# SPDX-License-Identifier: LicenseRef-MPL-2.0

set -e -o pipefail

git config --global user.email "hi@serokell.io"
git config --global user.name "CI autodoc generator"
git remote remove auth-origin 2> /dev/null || :
git remote add auth-origin https://serokell:$(cat ~/.config/serokell-bot-token)@github.com/serokell/tezos-btc.git
git fetch

our_branch="$BUILDKITE_BRANCH"
doc_branch="autodoc/$our_branch"
sha=$(git rev-parse --short HEAD)
git checkout origin/$doc_branch
git checkout -B $doc_branch
git merge -X theirs origin/$our_branch -m "Upstream merge"
nix-shell --run "stack exec tzbtc printContractDoc > TZBTC-contract.md"
git add TZBTC-contract.md
git commit --allow-empty -m "Documentation update for $sha"
git push --set-upstream auth-origin $doc_branch
git checkout @{-2}
