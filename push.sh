#!/bin/bash
# Publish this repo under the project's own GitHub account, and nobody else's.
# Usage: ./push.sh <github-account> [repo-name]
set -euo pipefail
ACCOUNT="${1:?usage: ./push.sh <github-account> [repo-name]}"
REPO="${2:-aaa}"

# Pin the identity explicitly. The keyring's active login is never trusted.
TOKEN=$(gh auth token --user "$ACCOUNT")
LOGIN=$(GH_TOKEN="$TOKEN" gh api /user -q .login)
ID=$(GH_TOKEN="$TOKEN" gh api /user -q .id)
[ "$LOGIN" = "$ACCOUNT" ] || { echo "token resolves to $LOGIN, not $ACCOUNT"; exit 1; }

# Nothing personal goes out. Trip on anything and stop.
if grep -rniE "baayoo|awesome-h|quorum90|saturn2022|distin|curved|/Users/" \
    --exclude-dir=lib --exclude-dir=out --exclude-dir=cache --exclude-dir=.git \
    --exclude=push.sh . ; then
  echo "leak gate tripped, nothing was pushed"; exit 1
fi

git config user.name "$LOGIN"
git config user.email "${ID}+${LOGIN}@users.noreply.github.com"
git add -A
git commit -q -m "AAA: a rating agency with nobody inside" || echo "nothing new to commit"

GH_TOKEN="$TOKEN" gh repo create "$LOGIN/$REPO" --public \
  -d "Letter grades for tokenized stocks, computed on chain from the feeds' own rounds. No analysts." \
  2>/dev/null || echo "repo exists, pushing"
git remote remove origin 2>/dev/null || true
git remote add origin "https://github.com/$LOGIN/$REPO.git"
git -c credential.helper="!f(){ echo username=$LOGIN; echo password=$TOKEN; }; f" push -u origin HEAD:main

echo "--- author on GitHub ---"
GH_TOKEN="$TOKEN" gh api "repos/$LOGIN/$REPO/commits" -q '.[0].author.login'
