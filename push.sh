#!/bin/bash
set -euo pipefail
ACCOUNT="${1:?usage: ./push.sh <github-account> [repo-name]}"
REPO="${2:-aaa}"
TOKEN=$(gh auth token --user "$ACCOUNT")
LOGIN=$(GH_TOKEN="$TOKEN" gh api /user -q .login)
[ "$LOGIN" = "$ACCOUNT" ] || { echo "token resolves to $LOGIN"; exit 1; }
