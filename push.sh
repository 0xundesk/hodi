#!/bin/bash
set -euo pipefail
ACCOUNT="${1:?usage: ./push.sh <github-account> [repo-name]}"
REPO="${2:-aaa}"
TOKEN=$(gh auth token --user "$ACCOUNT")
