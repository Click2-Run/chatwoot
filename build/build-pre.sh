#!/bin/bash
##
# @fileoverview Pre-build hook — chatwoot fast-fail sanity checks
# @module build/build-pre.sh
# @category Build/Hooks
# @description Runs before build.sh ships the source tar to remote nodes.
#   Chatwoot is a single monolithic Rails+Vue app with no vendored sibling-
#   repo packages, so this hook is intentionally lightweight — it catches the
#   issues that would otherwise blow up 5–15 minutes into the remote build:
#     1. Working tree is dirty (image won't be reproducible from git history)
#     2. Dockerfile missing or moved
#     3. Gemfile.lock out of sync with Gemfile (soft warning — Docker stage
#        will still fail loudly, but we surface it locally first)
# @architecture Called by build.sh:run_hook() before sync_source_code.
#   Receives positional args: PROJECT_ROOT IMAGE_NAME IMAGE_TAG.
#   Reads BUILD_* env vars exported by build.sh:run_hook() for context.
# @relatedFiles
#   - build/build.sh (calls this hook, exports BUILD_* env vars)
#   - docker/Dockerfile (primary chatwoot Dockerfile)
#   - Gemfile.lock / pnpm-lock.yaml (validated here)
# @created 2026-05-14
##

set -euo pipefail

PROJECT_ROOT="${1:-.}"
cd "$PROJECT_ROOT"

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}[build-pre]${NC} Chatwoot pre-build sanity checks"
echo -e "${GREEN}[build-pre]${NC}   project:     ${BUILD_PROJECT_ROOT:-$PROJECT_ROOT}"
echo -e "${GREEN}[build-pre]${NC}   image:       ${BUILD_IMAGE_NAME:-?}:${BUILD_IMAGE_TAG:-?}"
echo -e "${GREEN}[build-pre]${NC}   git commit:  ${BUILD_GIT_COMMIT:-?}"
echo -e "${GREEN}[build-pre]${NC}   git tag:     ${BUILD_GIT_TAG:-?}"

# 1. Git working-tree status — warn only, never abort.
#    The Dockerfile bakes `git rev-parse HEAD > /app/.git_sha` for forensics;
#    if the tree is dirty, that SHA will not represent what's in the image.
if git rev-parse --git-dir &>/dev/null; then
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        echo -e "${YELLOW}[build-pre] WARNING:${NC} working tree has uncommitted changes — the baked .git_sha will not match the image contents"
        git status --short 2>&1 | head -20 | sed 's/^/  | /'
    else
        echo -e "${GREEN}[build-pre]${NC}   git tree:    clean"
    fi
fi

# 2. Dockerfile must exist where build.sh expects it.
DF="$PROJECT_ROOT/docker/Dockerfile"
if [[ ! -f "$DF" ]]; then
    echo -e "${RED}[build-pre] ERROR:${NC} Dockerfile not found at $DF" >&2
    exit 1
fi
echo -e "${GREEN}[build-pre]${NC}   dockerfile:  $DF"

# 2b. Pre-populate .git_sha so the source tar carries it.
#     build/build.sh excludes .git from the tar to keep the SSH transfer
#     small (.git can be 200+ MB on this fork), but the Dockerfile's
#     `git rev-parse HEAD > /app/.git_sha` step then fails because the
#     remote build context has no git history. Writing the SHA here means
#     the Dockerfile's RUN step is a no-op on remote builds (and still
#     idempotent on local builds where .git is present).
if git rev-parse --git-dir &>/dev/null; then
    git rev-parse HEAD > "$PROJECT_ROOT/.git_sha"
    echo -e "${GREEN}[build-pre]${NC}   git_sha:     $(cat "$PROJECT_ROOT/.git_sha") (written to .git_sha for tar)"
fi

# 3. Gemfile.lock sanity — soft check.
#    `bundle check` returns non-zero if Gemfile.lock would not satisfy
#    a fresh install. The Docker pre-builder stage runs `bundle install`
#    and will fail in the same way, but catching it here saves ~5 min of
#    wasted tar+ssh+gem-compile time on the remote node.
if command -v bundle &>/dev/null && [[ -f Gemfile.lock ]]; then
    if ! bundle check &>/dev/null; then
        echo -e "${YELLOW}[build-pre] WARNING:${NC} 'bundle check' is unsatisfied — Gemfile.lock may be out of sync with Gemfile"
        echo -e "${YELLOW}[build-pre]${NC}   run 'bundle install' locally if the remote build fails at the bundler stage"
    else
        echo -e "${GREEN}[build-pre]${NC}   gemfile:     in sync"
    fi
fi

echo -e "${GREEN}[build-pre]${NC} Pre-build checks complete"
exit 0
