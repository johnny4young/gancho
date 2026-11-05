#!/bin/sh
# Git exports GIT_DIR to a hook in a linked worktree. Whatever the hook runs must
# not reach the real repository: `git init` in a temporary folder marks it bare.
set -eu
unset $(git rev-parse --local-env-vars)

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/gancho-hook-env.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

git init -q "$tmp/main"
git init -q --bare "$tmp/remote.git"
git -C "$tmp/main" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false \
    commit -q --allow-empty -m base
git -C "$tmp/main" worktree add -q -b linked "$tmp/linked"

expect_not_bare() {
    if [ "$(git -C "$tmp/main" config --get core.bare)" != false ]; then
        echo "test-hook-git-environment: $1 marked the repository bare" >&2
        exit 1
    fi
}

GIT_DIR="$tmp/main/.git/worktrees/linked" \
    python3 "$root/scripts/restore-xcode-catalog-noise.py" --self-test >/dev/null
expect_not_bare "the catalog self-test"

# The hooks run for real; only what they call is replaced.
mkdir "$tmp/linked/scripts"
printf 'raise SystemExit(0)\n' >"$tmp/linked/scripts/restore-xcode-catalog-noise.py"
printf 'lint test:\n\t@cd "$$(mktemp -d)" && git init -q\n' >"$tmp/linked/Makefile"

git -C "$tmp/linked" -c core.hooksPath="$root/scripts/githooks" \
    -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false \
    commit -q --allow-empty -m change >/dev/null
expect_not_bare "the pre-commit hook"

git -C "$tmp/linked" -c core.hooksPath="$root/scripts/githooks" \
    push -q "$tmp/remote.git" linked >/dev/null 2>&1
expect_not_bare "the pre-push hook"

echo "Hook git environment test passed"
