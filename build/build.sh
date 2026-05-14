#!/bin/bash
##
# @fileoverview Native multi-arch Docker build (generic, project-agnostic)
# @module build
# @category Scripts/Build
# @description Builds Docker images natively on arm64/amd64 cluster nodes via SSH.
#   No QEMU emulation — source code is synced to actual architecture-native worker
#   nodes, built natively on each, pushed as arch-specific tags, then unified into
#   a multi-arch manifest. Go CGO with static linking under QEMU runs 10-50x slower
#   than native; this script eliminates that penalty entirely.
# @architecture
#   1. Parse flags and resolve target platforms
#   2. Run build-pre.sh hook if present (e.g., go mod vendor)
#   3. Discover healthy worker nodes per requested arch via kubectl
#   4. Sync build context (mirroring .dockerignore exclusions) via tar+ssh
#   5. Build Docker image natively on each node — zero emulation
#   6. Push arch-specific tags from each node to registry
#   7. Create and push a unified multi-arch manifest (multi-platform only)
#   8. Update docker-compose.yml with new image tag
#   9. Run build-post.sh hook if present
# @dependencies docker, ssh (key-based access to cluster nodes), kubectl, jq
# @note All kubectl calls use --context=default to target the host cluster
#       (not a vCluster) for worker node discovery.
# @relatedFiles
#   - Dockerfile (project root — multi-stage Go build)
#   - .dockerignore (project root — mirrored in tar excludes)
#   - docker-compose.yml (image tag reference, auto-updated on push)
#   - build/build-pre.sh (optional pre-build hook — e.g., go mod vendor)
#   - build/build-post.sh (optional post-build hook)
# @created 2026-02-28
##
#
# Usage:
#   ./build/build.sh [OPTIONS] [TAG]
#
# Options:
#   -t, --tag TAG            Image tag (default: YYYYMMDD)
#   -p, --platform PLATFORM  Target platform: arm64, amd64, or all (default: all)
#   --push                   Push images to registry (default)
#   --no-push                Build only, skip push
#   --no-cache               Build without Docker layer cache
#   -l, --local              Build local arch locally, only use remote for other arch
#   --cleanup                Remove build artifacts from remote nodes after build
#   --update-compose         Update docker-compose.yml with new image tag
#   -h, --help               Show usage
#
# Hooks:
#   build/build-pre.sh     Runs before sync (e.g., go mod vendor)
#   build/build-post.sh    Runs after successful build+push
#
# Examples:
#   ./build/build.sh                          # multi-arch, push, tag=YYYYMMDD
#   ./build/build.sh 20260228                 # multi-arch, push, tag=20260228
#   ./build/build.sh --platform arm64         # arm64 only
#   ./build/build.sh --no-push                # build only, no push
#   ./build/build.sh --no-cache --cleanup     # fresh build, cleanup remote nodes
#   ./build/build.sh -p amd64 -t latest       # amd64 only, tag=latest
#   ./build/build.sh --local                  # local arch here, other arch remote
#   ./build/build.sh --local -p amd64         # amd64 locally only, no arm64
#   ./build/build.sh --app landing            # build ppcloud-landing instead of minha
#   ./build/build.sh --app landing --no-push  # build landing locally, no push

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
# Chatwoot ships docker-compose.production.yaml as the prod stack manifest;
# point --update-compose at that file instead of the upstream docker-compose.yml
# convention used by propriacloud / whatsapp-api.
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.production.yaml"

# Image settings — derived from Makefile (single source of truth)
# Override with --app <name> for monorepo app selection (e.g., --app landing)
DOCKER_REGISTRY=$(grep '^DOCKER_REGISTRY' "$PROJECT_ROOT/Makefile" 2>/dev/null | head -1 | sed 's/.*:= *//')
DOCKER_IMAGE=$(grep '^IMAGE_NAME' "$PROJECT_ROOT/Makefile" 2>/dev/null | head -1 | sed 's/.*:= *//')
IMAGE_NAME="${DOCKER_REGISTRY:?DOCKER_REGISTRY not found in Makefile}/${DOCKER_IMAGE:?IMAGE_NAME not found in Makefile}"
IMAGE_TAG=""

# App selection (monorepo: minha, landing, etc.)
# When set via --app, overrides DOCKER_IMAGE and selects build/Dockerfile.<app>
APP_NAME=""
DOCKERFILE=""
DOCKERFILE_REL=""

# Remote build directory
REMOTE_BUILD_DIR="/tmp/docker-build/${DOCKER_IMAGE}"

# kubectl context — always target the host cluster for node discovery
KUBE_CONTEXT="default"

# Build options (defaults)
PLATFORMS="all"           # all | arm64 | amd64
PUSH_IMAGES="true"
NO_CACHE=""
CLEANUP="false"
UPDATE_COMPOSE="false"
LOCAL_BUILD="false"

# Selected nodes (populated by discover_build_nodes)
ARM64_NODE=""
AMD64_NODE=""

# Resolved platform list (populated by resolve_platforms)
BUILD_ARM64="false"
BUILD_AMD64="false"

# Local build flags (populated when --local is used)
LOCAL_ARCH=""
BUILD_ARM64_LOCAL="false"
BUILD_AMD64_LOCAL="false"

# Status tracking via temp files (background processes can't modify parent vars)
STATUS_DIR=""

# Build timing
BUILD_START_TIME=""
BUILD_END_TIME=""
OVERALL_STATUS="pending"
FAILURE_REASON=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# Status File Helpers
# =============================================================================
# Background processes (& jobs) run in subshells and CANNOT modify parent
# variables via eval. Status files bridge this gap reliably.

write_status() {
    local key="$1"
    local value="$2"
    echo "$value" > "$STATUS_DIR/$key"
}

read_status() {
    local key="$1"
    local default="${2:-pending}"
    cat "$STATUS_DIR/$key" 2>/dev/null || echo "$default"
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--tag)
                IMAGE_TAG="$2"
                shift 2
                ;;
            -p|--platform)
                PLATFORMS="$2"
                shift 2
                ;;
            --push)
                PUSH_IMAGES="true"
                shift
                ;;
            --no-push)
                PUSH_IMAGES="false"
                shift
                ;;
            --no-cache)
                NO_CACHE="--no-cache"
                shift
                ;;
            --cleanup)
                CLEANUP="true"
                shift
                ;;
            -l|--local)
                LOCAL_BUILD="true"
                shift
                ;;
            -a|--app)
                APP_NAME="$2"
                shift 2
                ;;
            --update-compose)
                UPDATE_COMPOSE="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                log "ERROR" "Unknown option: $1"
                echo "Use -h or --help for usage information" >&2
                exit 1
                ;;
            *)
                # Positional argument treated as tag
                IMAGE_TAG="$1"
                shift
                ;;
        esac
    done

    # Default tag if not provided
    if [[ -z "$IMAGE_TAG" ]]; then
        IMAGE_TAG=$(date +%Y%m%d)
    fi
}

resolve_platforms() {
    case "$PLATFORMS" in
        all|both)
            BUILD_ARM64="true"
            BUILD_AMD64="true"
            ;;
        arm64|aarch64)
            BUILD_ARM64="true"
            BUILD_AMD64="false"
            ;;
        amd64|x86_64|x64)
            BUILD_ARM64="false"
            BUILD_AMD64="true"
            ;;
        *)
            log "ERROR" "Invalid platform: $PLATFORMS (expected: all, arm64, or amd64)"
            exit 1
            ;;
    esac
}

# =============================================================================
# Node Discovery
# =============================================================================

discover_nodes_by_arch() {
    local arch="$1"
    kubectl --context="$KUBE_CONTEXT" get nodes -o json | jq -r --arg arch "$arch" '
        .items[] |
        select(.metadata.name | test("^cdc01-wk")) |
        select(.status.nodeInfo.architecture == $arch) |
        select(.status.conditions[] | select(.type == "Ready" and .status == "True")) |
        .status.addresses[] |
        select(.type == "ExternalIP") |
        .address
    ' 2>/dev/null
}

test_node_health() {
    local node="$1"
    local timeout=5
    if ! ssh -o ConnectTimeout=$timeout -o BatchMode=yes "$node" "echo ok" &>/dev/null; then
        return 1
    fi
    if ! ssh -o ConnectTimeout=$timeout -o BatchMode=yes "$node" "docker info" &>/dev/null; then
        return 1
    fi
    return 0
}

find_healthy_node() {
    local arch="$1"
    local nodes
    log "INFO" "Discovering $arch nodes..."
    nodes=$(discover_nodes_by_arch "$arch")
    if [[ -z "$nodes" ]]; then
        log "ERROR" "No $arch worker nodes found in cluster"
        return 1
    fi
    for node in $nodes; do
        log "INFO" "  Testing $arch node: $node"
        if test_node_health "$node"; then
            log "INFO" "  -> Node $node is healthy"
            echo "$node"
            return 0
        else
            log "WARN" "  -> Node $node is not reachable or Docker not running"
        fi
    done
    log "ERROR" "No healthy $arch nodes found"
    return 1
}

discover_build_nodes() {
    log "INFO" "Discovering build nodes..."

    if [[ "$BUILD_ARM64" == "true" && "$BUILD_ARM64_LOCAL" == "false" ]]; then
        ARM64_NODE=$(find_healthy_node "arm64")
        if [[ -z "$ARM64_NODE" ]]; then
            log "ERROR" "Failed to find healthy ARM64 node"
            FAILURE_REASON="No healthy ARM64 worker node found"
            exit 1
        fi
    fi

    if [[ "$BUILD_AMD64" == "true" && "$BUILD_AMD64_LOCAL" == "false" ]]; then
        AMD64_NODE=$(find_healthy_node "amd64")
        if [[ -z "$AMD64_NODE" ]]; then
            log "ERROR" "Failed to find healthy AMD64 node"
            FAILURE_REASON="No healthy AMD64 worker node found"
            exit 1
        fi
    fi

    log "INFO" "Selected build nodes:"
    if [[ "$BUILD_ARM64_LOCAL" == "true" ]]; then
        log "INFO" "  ARM64: local"
    elif [[ "$BUILD_ARM64" == "true" ]]; then
        log "INFO" "  ARM64: $ARM64_NODE"
    fi
    if [[ "$BUILD_AMD64_LOCAL" == "true" ]]; then
        log "INFO" "  AMD64: local"
    elif [[ "$BUILD_AMD64" == "true" ]]; then
        log "INFO" "  AMD64: $AMD64_NODE"
    fi
}

# =============================================================================
# Core Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local color=""
    case "$level" in
        INFO)  color="$GREEN" ;;
        WARN)  color="$YELLOW" ;;
        ERROR) color="$RED" ;;
        *)     color="$CYAN" ;;
    esac
    echo -e "${color}[${level}]${NC} $*" >&2
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."

    if ! command -v kubectl &>/dev/null; then
        log "ERROR" "kubectl is not installed"
        FAILURE_REASON="kubectl not found"
        exit 1
    fi

    if ! command -v jq &>/dev/null; then
        log "ERROR" "jq is not installed"
        FAILURE_REASON="jq not found"
        exit 1
    fi

    if ! kubectl --context="$KUBE_CONTEXT" get nodes &>/dev/null; then
        log "ERROR" "Cannot connect to Kubernetes cluster (context: $KUBE_CONTEXT)"
        FAILURE_REASON="Cluster unreachable (context: $KUBE_CONTEXT)"
        exit 1
    fi

    if [[ ! -f "$DOCKERFILE" ]]; then
        log "ERROR" "Dockerfile not found at $DOCKERFILE"
        FAILURE_REASON="Dockerfile not found"
        exit 1
    fi

    log "INFO" "Prerequisites OK"
}

# =============================================================================
# Pre/Post Build Hooks
# =============================================================================

run_hook() {
    local hook_name="$1"
    local hook_path="$SCRIPT_DIR/$hook_name"

    if [[ -f "$hook_path" && -x "$hook_path" ]]; then
        log "INFO" "Running hook: $hook_name"
        # Export build context so hooks can react to runtime options
        # (positional args $1..$3 retained below for backward compatibility).
        export BUILD_PROJECT_ROOT="$PROJECT_ROOT"
        export BUILD_IMAGE_NAME="$IMAGE_NAME"
        export BUILD_IMAGE_TAG="$IMAGE_TAG"
        export BUILD_APP_NAME="$APP_NAME"
        export BUILD_NO_CACHE="$([[ -n "$NO_CACHE" ]] && echo "true" || echo "false")"
        export BUILD_PUSH="$PUSH_IMAGES"
        export BUILD_PLATFORMS="$PLATFORMS"
        export BUILD_LOCAL="$LOCAL_BUILD"
        export BUILD_CLEANUP="$CLEANUP"
        export BUILD_UPDATE_COMPOSE="$UPDATE_COMPOSE"
        export BUILD_GIT_COMMIT="${GIT_COMMIT:-unknown}"
        export BUILD_GIT_TAG="${GIT_TAG:-unknown}"
        if ! "$hook_path" "$PROJECT_ROOT" "$IMAGE_NAME" "$IMAGE_TAG"; then
            log "ERROR" "Hook $hook_name failed"
            return 1
        fi
        log "INFO" "Hook $hook_name completed"
    fi
    return 0
}

# =============================================================================
# Sync, Build, Push
# =============================================================================

detect_local_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)  echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *)
            log "ERROR" "Unsupported local architecture: $arch"
            exit 1
            ;;
    esac
}

build_local() {
    local arch="$1"
    local image_tag="${IMAGE_NAME}:${IMAGE_TAG}-${arch}"

    log "INFO" "Building $arch image locally (native, no emulation)..."

    if docker build \
        --build-arg RAILS_ENV=production \
        --build-arg BUNDLE_WITHOUT=development:test \
        --build-arg RAILS_SERVE_STATIC_FILES=true \
        --build-arg TARGETARCH="$arch" \
        $NO_CACHE \
        -t "$image_tag" \
        -f "$DOCKERFILE" "$PROJECT_ROOT"; then
        write_status "BUILD_${arch^^}" "success"
        log "INFO" "Built $image_tag locally"
    else
        write_status "BUILD_${arch^^}" "failed"
        log "ERROR" "Failed to build $image_tag locally"
        return 1
    fi
}

push_local() {
    local arch="$1"
    local image_tag="${IMAGE_NAME}:${IMAGE_TAG}-${arch}"
    local push_output

    log "INFO" "Pushing $image_tag from local..."

    if push_output=$(docker push "$image_tag" 2>&1); then
        write_status "PUSH_${arch^^}" "success"
        local digest
        digest=$(echo "$push_output" | grep -oP 'digest: \Ksha256:[a-f0-9]+' | head -1)
        if [[ -n "$digest" ]]; then
            write_status "PUSH_${arch^^}_DIGEST" "$digest"
        fi
        log "INFO" "Pushed $image_tag"
    else
        write_status "PUSH_${arch^^}" "failed"
        log "ERROR" "Failed to push $image_tag"
        echo "$push_output" >&2
        return 1
    fi
}

sync_source_code() {
    local node="$1"
    local arch="$2"

    log "INFO" "Syncing source code to $arch node ($node)..."

    if ! ssh -o BatchMode=yes "$node" "rm -rf $REMOTE_BUILD_DIR && mkdir -p $REMOTE_BUILD_DIR"; then
        write_status "SYNC_${arch^^}" "failed"
        log "ERROR" "Failed to prepare remote directory on $arch node"
        return 1
    fi

    # Sync build context from project root. The tar excludes mirror .dockerignore
    # AND drop heavyweight rebuild-from-source artifacts (node_modules, bundler
    # cache, compiled assets) — these get regenerated inside the Dockerfile's
    # pre-builder stage, so shipping them across SSH is pure waste.
    if tar -C "$PROJECT_ROOT" \
        --exclude='.git' \
        --exclude='.gitignore' \
        --exclude='.gitmodules' \
        --exclude='.idea' \
        --exclude='.vscode' \
        --exclude='.bundle' \
        --exclude='node_modules' \
        --exclude='vendor/bundle' \
        --exclude='log' \
        --exclude='tmp' \
        --exclude='storage' \
        --exclude='public/packs' \
        --exclude='public/packs-test' \
        --exclude='public/system' \
        --exclude='public/assets' \
        --exclude='coverage' \
        --exclude='*.log' \
        --exclude='docker-compose*.yml' \
        --exclude='docker-compose*.yaml' \
        --exclude='.env' \
        --exclude='.env.*' \
        --exclude='.llm' \
        --exclude='.codex' \
        --exclude='.claude' \
        --exclude='.claudel' \
        --exclude='.github' \
        --exclude='.devcontainer' \
        --exclude='k8s' \
        --exclude='.codeclimate.yml' \
        --exclude='.DS_Store' \
        --exclude='Thumbs.db' \
        --exclude='*.swp' \
        --exclude='*~' \
        --exclude='CLAUDE.md' \
        --exclude='AGENT.md' \
        --exclude='AGENTS.md' \
        --exclude='GEMINI.md' \
        --exclude='CONTRIBUTING.md' \
        --exclude='CHANGELOG.md' \
        --exclude='CUSTOM-*.md' \
        --exclude='LLM-*.md' \
        -czf - . | ssh -o BatchMode=yes "$node" "tar -C $REMOTE_BUILD_DIR -xzf -"; then
        write_status "SYNC_${arch^^}" "success"
        log "INFO" "Source code synced to $arch node"
    else
        write_status "SYNC_${arch^^}" "failed"
        log "ERROR" "Failed to sync source code to $arch node"
        return 1
    fi
}

build_on_node() {
    local node="$1"
    local arch="$2"
    local image_tag="${IMAGE_NAME}:${IMAGE_TAG}-${arch}"

    log "INFO" "Building $arch image on $node (native, no emulation)..."

    # ⚠️  WARNING: NEVER use --network=host for Docker builds on Kubernetes nodes.
    # --network=host shares the host's network namespace with the build container.
    # On K8s nodes this causes: iptables chain conflicts with kube-proxy rules,
    # conntrack table exhaustion that kills ALL pod networking on the node,
    # and DNS resolver contention with systemd-resolved. Use Docker's default
    # bridge network instead — configure /etc/docker/daemon.json with explicit
    # DNS servers on each node (e.g., "dns": ["8.8.8.8", "1.1.1.1"]).
    #
    # TARGETARCH: must match the native architecture of the build node so that
    # GOARCH is set correctly and CGO uses the right compiler flags.
    if ssh -o BatchMode=yes "$node" "cd $REMOTE_BUILD_DIR && docker build \
        --build-arg RAILS_ENV=production \
        --build-arg BUNDLE_WITHOUT=development:test \
        --build-arg RAILS_SERVE_STATIC_FILES=true \
        --build-arg TARGETARCH='$arch' \
        $NO_CACHE \
        -t '$image_tag' \
        -f '$DOCKERFILE_REL' ."; then
        write_status "BUILD_${arch^^}" "success"
        log "INFO" "Built $image_tag on $node"
    else
        write_status "BUILD_${arch^^}" "failed"
        log "ERROR" "Failed to build $image_tag on $node"
        return 1
    fi
}

push_from_node() {
    local node="$1"
    local arch="$2"
    local image_tag="${IMAGE_NAME}:${IMAGE_TAG}-${arch}"
    local push_output
    local digest

    log "INFO" "Pushing $image_tag from $node..."

    # Copy Docker Hub credentials to remote node if needed
    if [[ -f ~/.docker/config.json ]]; then
        ssh -o BatchMode=yes "$node" "mkdir -p ~/.docker"
        scp -q ~/.docker/config.json "$node:~/.docker/config.json"
    fi

    if push_output=$(ssh -o BatchMode=yes "$node" "docker push '$image_tag'" 2>&1); then
        write_status "PUSH_${arch^^}" "success"
        digest=$(echo "$push_output" | grep -oP 'digest: \Ksha256:[a-f0-9]+' | head -1)
        if [[ -n "$digest" ]]; then
            write_status "PUSH_${arch^^}_DIGEST" "$digest"
        fi
        log "INFO" "Pushed $image_tag"
    else
        write_status "PUSH_${arch^^}" "failed"
        log "ERROR" "Failed to push $image_tag"
        echo "$push_output" >&2
        return 1
    fi
}

create_manifest() {
    log "INFO" "Creating multi-arch manifest..."

    local arm64_tag="${IMAGE_NAME}:${IMAGE_TAG}-arm64"
    local amd64_tag="${IMAGE_NAME}:${IMAGE_TAG}-amd64"
    local manifest_tag="${IMAGE_NAME}:${IMAGE_TAG}"
    local push_output

    docker manifest rm "$manifest_tag" 2>/dev/null || true

    if ! docker manifest create "$manifest_tag" \
        --amend "$arm64_tag" \
        --amend "$amd64_tag"; then
        write_status "MANIFEST" "failed"
        log "ERROR" "Failed to create manifest"
        return 1
    fi

    docker manifest annotate "$manifest_tag" "$arm64_tag" --arch arm64
    docker manifest annotate "$manifest_tag" "$amd64_tag" --arch amd64

    if push_output=$(docker manifest push "$manifest_tag" 2>&1); then
        write_status "MANIFEST" "success"
        write_status "MANIFEST_DIGEST" "$(echo "$push_output" | grep -oP 'sha256:[a-f0-9]+' | head -1)"
        log "INFO" "Multi-arch manifest pushed: $manifest_tag"
    else
        write_status "MANIFEST" "failed"
        log "ERROR" "Failed to push manifest"
        echo "$push_output" >&2
        return 1
    fi
}

create_single_arch_manifest() {
    local arch
    [[ "$BUILD_ARM64" == "true" ]] && arch="arm64" || arch="amd64"
    local arch_tag="${IMAGE_NAME}:${IMAGE_TAG}-${arch}"
    local manifest_tag="${IMAGE_NAME}:${IMAGE_TAG}"

    log "INFO" "Creating single-arch manifest ($arch) for base tag..."

    docker manifest rm "$manifest_tag" 2>/dev/null || true

    if ! docker manifest create "$manifest_tag" --amend "$arch_tag"; then
        write_status "MANIFEST" "failed"
        log "ERROR" "Failed to create single-arch manifest"
        return 1
    fi

    docker manifest annotate "$manifest_tag" "$arch_tag" --arch "$arch"

    local push_output
    if push_output=$(docker manifest push "$manifest_tag" 2>&1); then
        write_status "MANIFEST" "success"
        write_status "MANIFEST_DIGEST" "$(echo "$push_output" | grep -oP 'sha256:[a-f0-9]+' | head -1)"
        log "INFO" "Single-arch manifest pushed: $manifest_tag -> $arch"
    else
        write_status "MANIFEST" "failed"
        log "ERROR" "Failed to push single-arch manifest"
        echo "$push_output" >&2
        return 1
    fi
}

update_compose_tag() {
    if [[ "$UPDATE_COMPOSE" != "true" ]]; then
        log "INFO" "Skipping docker-compose.yml update (use --update-compose to enable)"
        return 0
    fi

    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log "WARN" "docker-compose.yml not found, skipping tag update"
        return 0
    fi

    local full_image="$IMAGE_NAME:$IMAGE_TAG"
    log "INFO" "Updating docker-compose.yml image tag to $IMAGE_TAG..."
    sed -i "s|image: $IMAGE_NAME:.*|image: $full_image|" "$COMPOSE_FILE"

    if grep -q "image: $full_image" "$COMPOSE_FILE"; then
        log "INFO" "Updated docker-compose.yml with $full_image"
    else
        log "WARN" "Failed to update docker-compose.yml — verify manually"
    fi
}

cleanup_remote() {
    local node="$1"
    local arch="$2"
    if [[ "$CLEANUP" == "true" ]]; then
        log "INFO" "Cleaning up on $arch node ($node)..."
        ssh -o BatchMode=yes "$node" "rm -rf $REMOTE_BUILD_DIR" 2>/dev/null || true
        ssh -o BatchMode=yes "$node" "docker rmi '${IMAGE_NAME}:${IMAGE_TAG}-${arch}' 2>/dev/null || true" 2>/dev/null || true
    fi
}

verify_image() {
    if [[ "$BUILD_ARM64" == "true" && "$BUILD_AMD64" == "true" ]]; then
        log "INFO" "Verifying multi-arch image..."
        docker manifest inspect "${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null \
            | grep -E '"architecture"|"os"' | head -10 || true
        log "INFO" "Image ${IMAGE_NAME}:${IMAGE_TAG} available with both architectures"
    else
        local arch
        [[ "$BUILD_ARM64" == "true" ]] && arch="arm64" || arch="amd64"
        log "INFO" "Single-platform image pushed: ${IMAGE_NAME}:${IMAGE_TAG}-${arch}"
    fi
}

# =============================================================================
# Report
# =============================================================================

format_status() {
    local status="$1"
    case "$status" in
        success)  echo -e "${GREEN}SUCCESS${NC}" ;;
        failed)   echo -e "${RED}FAILED${NC}" ;;
        skipped)  echo -e "${YELLOW}SKIPPED${NC}" ;;
        pending)  echo -e "${YELLOW}N/A${NC}" ;;
        *)        echo -e "${NC}UNKNOWN${NC}" ;;
    esac
}

format_duration() {
    local start="$1"
    local end="$2"
    local duration=$((end - start))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    if [[ $minutes -gt 0 ]]; then
        echo "${minutes}m ${seconds}s"
    else
        echo "${seconds}s"
    fi
}

short_digest() {
    local digest="$1"
    if [[ -n "$digest" ]]; then
        echo "${digest:0:19}..."
    else
        echo "-"
    fi
}

determine_overall_status() {
    local sync_arm64 sync_amd64 build_arm64 build_amd64 push_arm64 push_amd64 manifest

    sync_arm64=$(read_status "SYNC_ARM64")
    sync_amd64=$(read_status "SYNC_AMD64")
    build_arm64=$(read_status "BUILD_ARM64")
    build_amd64=$(read_status "BUILD_AMD64")
    push_arm64=$(read_status "PUSH_ARM64")
    push_amd64=$(read_status "PUSH_AMD64")
    manifest=$(read_status "MANIFEST")

    if [[ "$PUSH_IMAGES" == "true" ]]; then
        # Manifest is now created for both multi-arch and single-arch builds
        [[ "$manifest" == "success" ]] && OVERALL_STATUS="success" || OVERALL_STATUS="failed"
    else
        local ok="true"
        [[ "$BUILD_ARM64" == "true" && "$build_arm64" != "success" ]] && ok="false"
        [[ "$BUILD_AMD64" == "true" && "$build_amd64" != "success" ]] && ok="false"
        [[ "$ok" == "true" ]] && OVERALL_STATUS="success" || OVERALL_STATUS="failed"
    fi
}

print_build_report() {
    local duration=""
    if [[ -n "$BUILD_START_TIME" && -n "$BUILD_END_TIME" ]]; then
        duration=$(format_duration "$BUILD_START_TIME" "$BUILD_END_TIME")
    fi

    determine_overall_status

    local platform_label="multi-arch (arm64 + amd64)"
    [[ "$BUILD_ARM64" == "true" && "$BUILD_AMD64" == "false" ]] && platform_label="arm64 only"
    [[ "$BUILD_ARM64" == "false" && "$BUILD_AMD64" == "true" ]] && platform_label="amd64 only"

    echo "" >&2
    echo -e "${CYAN}==============================================${NC}" >&2
    echo -e "${CYAN}  ${DOCKER_IMAGE} BUILD REPORT${NC}" >&2
    echo -e "${CYAN}==============================================${NC}" >&2
    echo -e "  Status:    $(format_status $OVERALL_STATUS)" >&2
    echo -e "  Image:     ${IMAGE_NAME}:${IMAGE_TAG}" >&2
    echo -e "  Platforms: ${platform_label}" >&2
    echo -e "${CYAN}----------------------------------------------${NC}" >&2
    if [[ -n "$BUILD_START_TIME" ]]; then
        echo -e "  Started:   $(date -d @"$BUILD_START_TIME" '+%Y-%m-%d %H:%M:%S %Z')" >&2
    fi
    if [[ -n "$BUILD_END_TIME" ]]; then
        echo -e "  Finished:  $(date -d @"$BUILD_END_TIME" '+%Y-%m-%d %H:%M:%S %Z')" >&2
    fi
    [[ -n "$duration" ]] && echo -e "  Duration:  ${duration}" >&2
    [[ -n "$NO_CACHE" ]] && echo -e "  Cache:     disabled" >&2
    echo -e "${CYAN}----------------------------------------------${NC}" >&2
    echo -e "  ${YELLOW}PLATFORM   NODE             SYNC       BUILD      PUSH       DIGEST${NC}" >&2
    echo -e "${CYAN}----------------------------------------------${NC}" >&2

    if [[ "$BUILD_ARM64" == "true" ]]; then
        printf "  %-10s %-16s %-10b %-10b %-10b %s\n" \
            "arm64" "${ARM64_NODE:-N/A}" \
            "$(format_status "$(read_status SYNC_ARM64)")" \
            "$(format_status "$(read_status BUILD_ARM64)")" \
            "$(format_status "$(read_status PUSH_ARM64)")" \
            "$(short_digest "$(read_status PUSH_ARM64_DIGEST "")")" >&2
    fi

    if [[ "$BUILD_AMD64" == "true" ]]; then
        printf "  %-10s %-16s %-10b %-10b %-10b %s\n" \
            "amd64" "${AMD64_NODE:-N/A}" \
            "$(format_status "$(read_status SYNC_AMD64)")" \
            "$(format_status "$(read_status BUILD_AMD64)")" \
            "$(format_status "$(read_status PUSH_AMD64)")" \
            "$(short_digest "$(read_status PUSH_AMD64_DIGEST "")")" >&2
    fi

    echo -e "${CYAN}----------------------------------------------${NC}" >&2

    if [[ "$PUSH_IMAGES" == "true" ]]; then
        echo -e "  Manifest: $(format_status "$(read_status MANIFEST)")" >&2
        local mdigest
        mdigest=$(read_status "MANIFEST_DIGEST" "")
        [[ -n "$mdigest" ]] && echo -e "  Digest:   ${mdigest:0:50}..." >&2
    else
        echo -e "  Manifest: $(format_status skipped) (--no-push)" >&2
    fi

    echo -e "${CYAN}----------------------------------------------${NC}" >&2

    if [[ "$OVERALL_STATUS" == "success" && "$PUSH_IMAGES" == "true" ]]; then
        echo -e "  ${GREEN}Pull:${NC} docker pull ${IMAGE_NAME}:${IMAGE_TAG}" >&2
        echo -e "  ${GREEN}Hub:${NC}  https://hub.docker.com/r/${IMAGE_NAME}/tags" >&2
    elif [[ "$OVERALL_STATUS" == "success" ]]; then
        echo -e "  ${YELLOW}Images built on nodes (not pushed to registry)${NC}" >&2
    else
        if [[ -n "$FAILURE_REASON" ]]; then
            echo -e "  ${RED}FAILED:${NC} $FAILURE_REASON" >&2
        else
            echo -e "  ${RED}Build failed — check logs above${NC}" >&2
        fi
    fi

    echo -e "${CYAN}==============================================${NC}" >&2
    echo "" >&2
}

show_usage() {
    cat << 'EOF'
Native Multi-arch Docker Build

  Production-grade build script that creates multi-architecture Docker images
  by building natively on actual arm64 and amd64 cluster worker nodes via SSH.
  Image name is derived from Makefile (DOCKER_REGISTRY/IMAGE_NAME).
  No QEMU emulation, no buildx cross-compilation — pure native builds.

USAGE
  ./build/build.sh [OPTIONS] [TAG]

OPTIONS
  -t, --tag TAG            Image tag (default: YYYYMMDD)
  -p, --platform PLATFORM  Target: all, arm64, amd64 (default: all)
  -a, --app APP            Monorepo app to build: minha, landing (default: from Makefile)
                           Selects build/Dockerfile.<app> and image ppcloud-<app>
  -l, --local              Build local arch locally, use remote only for the other
                           Combine with -p to build a single arch locally (no remote)
  --push                   Push images to registry (default)
  --no-push                Build only, skip push and manifest
  --no-cache               Build without Docker layer cache
  --cleanup                Remove build artifacts from remote nodes after build
  --update-compose         Update docker-compose.yml with new image tag (off by default)
  -h, --help               Show this help

HOOKS
  The script auto-detects and runs optional hook scripts in build/:

  build-pre.sh     Runs BEFORE sync — prepare the build context
                   (e.g., go mod vendor, npm install, generate assets)
                   Receives args: PROJECT_ROOT IMAGE_NAME IMAGE_TAG

  build-post.sh    Runs AFTER successful build+push — post-processing
                   (e.g., tag git, notify Slack, update deployment)
                   Receives args: PROJECT_ROOT IMAGE_NAME IMAGE_TAG

  Hooks must be executable (chmod +x). If absent, the step is skipped.
  If a hook exits non-zero, the build aborts.

  Both hooks also receive the full build context as environment variables
  so they can react dynamically (e.g., honor --no-cache, gate on --push):

    BUILD_PROJECT_ROOT     Absolute path to the repo root
    BUILD_IMAGE_NAME       Resolved image name (e.g., click2run/ppcloud-minha)
    BUILD_IMAGE_TAG        Final image tag (e.g., 20260508 or git SHA)
    BUILD_APP_NAME         Selected app slug from --app (may be empty)
    BUILD_NO_CACHE         "true" when --no-cache was passed, else "false"
    BUILD_PUSH             "true" / "false" — reflects --push / --no-push
    BUILD_PLATFORMS        "all" | "arm64" | "amd64"
    BUILD_LOCAL            "true" when --local was passed, else "false"
    BUILD_CLEANUP          "true" when --cleanup was passed, else "false"
    BUILD_UPDATE_COMPOSE   "true" when --update-compose was passed
    BUILD_GIT_COMMIT       Short HEAD SHA (or "unknown")
    BUILD_GIT_TAG          git describe output (or "unknown")

ARCHITECTURE
  This script avoids QEMU/buildx emulation entirely. Instead, it leverages
  real hardware nodes in the Kubernetes cluster:

  0. PRE-HOOK   — Run build-pre.sh if present (prepare build context)
  1. DISCOVER   — Find healthy cdc01-wk* worker nodes per arch via kubectl
  2. SYNC       — Tar the build context and stream it to each node via SSH
  3. BUILD      — Run 'docker build --network=host' natively on each node
  4. PUSH       — Push arch-specific tags from each node to Docker Hub
  5. MANIFEST   — Create and push a unified multi-arch manifest (both arches)
  6. UPDATE     — Patch docker-compose.yml with new image tag (only with --update-compose)
  7. POST-HOOK  — Run build-post.sh if present

  Single-platform mode (--platform arm64 or --platform amd64) skips manifest
  creation and only discovers/builds/pushes for the requested architecture.

  Docker builds use --network=host on remote nodes to avoid DNS resolution
  issues with Alpine package repos on cluster networks.

PREREQUISITES
  - kubectl         configured and connected to the cluster
  - jq              for parsing kubectl JSON output
  - ssh             key-based access to cluster worker nodes (BatchMode)
  - docker          on local machine (for manifest create/push/inspect)
  - docker          on remote nodes (for building and pushing)
  - Docker Hub      login on local machine (~/.docker/config.json)

  Docker Hub credentials are copied to remote nodes before push. Ensure
  'docker login' has been run on this machine before building with --push.

PERFORMANCE
  Native builds:    ~2-5 min per arch (parallel = same wall time for both)
  QEMU emulation:   ~30-60+ min (10-50x slower for Go CGO static linking)

  The performance difference is most severe with Go CGO + static linking
  (CGO_ENABLED=1, -linkmode external, -extldflags '-static') because QEMU
  must emulate every compiler and linker instruction for the foreign arch.

IMAGE NAMING (example: click2run/whatsapp-api, derived from Makefile)
  Multi-arch:     <registry>/<image>:<TAG>          (manifest)
  Arch-specific:  <registry>/<image>:<TAG>-arm64    (arm64 image)
                  <registry>/<image>:<TAG>-amd64    (amd64 image)

  When pulling <registry>/<image>:<TAG>, Docker automatically selects
  the correct architecture from the manifest.

EXAMPLES
  # Default: multi-arch build + push with today's date tag
  ./build/build.sh

  # Specific tag
  ./build/build.sh 20260228
  ./build/build.sh -t v1.2.0

  # Single platform only
  ./build/build.sh -p arm64
  ./build/build.sh -p amd64 -t latest

  # Build without pushing (test the build process)
  ./build/build.sh --no-push

  # Fresh build without cache, cleanup remote nodes after
  ./build/build.sh --no-cache --cleanup

  # Combined: arm64 only, specific tag, no push, no compose update
  ./build/build.sh -p arm64 -t test-build --no-push

  # Local build: build native arch here, only remote for the other arch
  ./build/build.sh --local

  # Local-only: build amd64 locally on an amd64 machine, skip arm64 entirely
  ./build/build.sh --local -p amd64

  # Local-only: build arm64 locally on an arm64 machine, skip amd64 entirely
  ./build/build.sh --local -p arm64

ENVIRONMENT VARIABLES (alternative to flags)
  PUSH_IMAGES=false         Same as --no-push
  CLEANUP=true              Same as --cleanup
  UPDATE_COMPOSE=true       Same as --update-compose

TROUBLESHOOTING
  "No <arch> worker nodes found"
    — kubectl cannot find cdc01-wk* nodes with the requested architecture.
      Verify: kubectl get nodes -o wide

  "Node <ip> is not reachable"
    — SSH connection to the worker node failed. Check:
      ssh -o BatchMode=yes <ip> "echo ok"

  "Docker not running" on a node
    — Docker daemon is down on the remote node. Check:
      ssh <ip> "docker info"

  "temporary error (try again later)" from apk
    — Alpine package repos unreachable from the Docker build network.
      The script uses --network=host to mitigate this. If it persists,
      check DNS resolution on the remote node:
      ssh <ip> "nslookup dl-cdn.alpinelinux.org"

  "Failed to push" from a node
    — Docker Hub credentials may be missing on the remote node.
      Ensure 'docker login' was run on this machine (copies ~/.docker/config.json).

  "Failed to create manifest"
    — Both arch-specific tags must be pushed before the manifest can be created.
      Verify: docker manifest inspect <registry>/<image>:<TAG>-arm64

EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    # --app override: select Dockerfile and image name for monorepo apps
    if [[ -n "$APP_NAME" ]]; then
        DOCKER_IMAGE="ppcloud-${APP_NAME}"
        IMAGE_NAME="${DOCKER_REGISTRY}/${DOCKER_IMAGE}"
        REMOTE_BUILD_DIR="/tmp/docker-build/${DOCKER_IMAGE}"
        log "INFO" "App override: --app ${APP_NAME} → ${IMAGE_NAME}"
    fi

    # Resolve Dockerfile path.
    #   1. --app <app> → build/Dockerfile.<app> (monorepo-style override)
    #   2. docker/Dockerfile (chatwoot convention — this repo's primary path)
    #   3. Root Dockerfile (generic convention)
    #   4. build/Dockerfile.minha (propriacloud monorepo fallback, kept for parity)
    if [[ -n "$APP_NAME" ]]; then
        DOCKERFILE="$PROJECT_ROOT/build/Dockerfile.${APP_NAME}"
    elif [[ -f "$PROJECT_ROOT/docker/Dockerfile" ]]; then
        DOCKERFILE="$PROJECT_ROOT/docker/Dockerfile"
    elif [[ -f "$PROJECT_ROOT/Dockerfile" ]]; then
        DOCKERFILE="$PROJECT_ROOT/Dockerfile"
    else
        DOCKERFILE="$PROJECT_ROOT/build/Dockerfile.minha"
    fi

    # Relative path for remote builds (synced context doesn't have absolute paths)
    DOCKERFILE_REL="${DOCKERFILE#$PROJECT_ROOT/}"

    if [[ ! -f "$DOCKERFILE" ]]; then
        log "ERROR" "Dockerfile not found at $DOCKERFILE"
        FAILURE_REASON="Dockerfile not found"
        exit 1
    fi

    resolve_platforms

    # Resolve local build settings
    if [[ "$LOCAL_BUILD" == "true" ]]; then
        LOCAL_ARCH=$(detect_local_arch)

        # When --local + single platform: validate the platform matches this machine
        if [[ "$PLATFORMS" != "all" && "$PLATFORMS" != "both" ]]; then
            local requested_arch="$PLATFORMS"
            [[ "$requested_arch" == "aarch64" ]] && requested_arch="arm64"
            [[ "$requested_arch" == "x86_64" || "$requested_arch" == "x64" ]] && requested_arch="amd64"

            if [[ "$requested_arch" != "$LOCAL_ARCH" ]]; then
                log "ERROR" "Cannot build $requested_arch locally — this machine is $LOCAL_ARCH"
                log "ERROR" "Either drop -p to build $LOCAL_ARCH locally + $requested_arch remotely,"
                log "ERROR" "or drop --local to build $requested_arch on a remote node"
                exit 1
            fi
        fi

        if [[ "$LOCAL_ARCH" == "arm64" && "$BUILD_ARM64" == "true" ]]; then
            BUILD_ARM64_LOCAL="true"
            ARM64_NODE="local"
        fi
        if [[ "$LOCAL_ARCH" == "amd64" && "$BUILD_AMD64" == "true" ]]; then
            BUILD_AMD64_LOCAL="true"
            AMD64_NODE="local"
        fi
    fi

    # Create temp dir for status files (background jobs can't modify parent vars)
    STATUS_DIR=$(mktemp -d)

    # Git metadata for build args
    GIT_COMMIT=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    GIT_TAG=$(git -C "$PROJECT_ROOT" describe --tags --always 2>/dev/null || echo "unknown")
    BUILD_DATE=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    BUILD_START_TIME=$(date +%s)
    trap 'BUILD_END_TIME=$(date +%s); print_build_report; rm -rf "$STATUS_DIR"' EXIT

    local platform_label="arm64 + amd64"
    [[ "$BUILD_ARM64" == "true" && "$BUILD_AMD64" == "false" ]] && platform_label="arm64"
    [[ "$BUILD_ARM64" == "false" && "$BUILD_AMD64" == "true" ]] && platform_label="amd64"

    if [[ "$LOCAL_BUILD" == "true" ]]; then
        local parts=()
        [[ "$BUILD_ARM64" == "true" ]] && { [[ "$BUILD_ARM64_LOCAL" == "true" ]] && parts+=("arm64(local)") || parts+=("arm64(remote)"); }
        [[ "$BUILD_AMD64" == "true" ]] && { [[ "$BUILD_AMD64_LOCAL" == "true" ]] && parts+=("amd64(local)") || parts+=("amd64(remote)"); }
        platform_label="${parts[*]}"
    fi

    echo ""
    log "INFO" "=============================================="
    log "INFO" "${DOCKER_IMAGE} Native Build"
    log "INFO" "=============================================="
    log "INFO" "Image:      ${IMAGE_NAME}:${IMAGE_TAG}"
    log "INFO" "Platforms:  ${platform_label}"
    log "INFO" "Push:       ${PUSH_IMAGES}"
    log "INFO" "Cache:      $([[ -n "$NO_CACHE" ]] && echo "disabled" || echo "enabled")"
    log "INFO" "Git Commit: ${GIT_COMMIT}"
    log "INFO" "Git Tag:    ${GIT_TAG}"
    echo ""

    # --- Pre-build hook ---
    if ! run_hook "build-pre.sh"; then
        FAILURE_REASON="Pre-build hook failed"
        exit 1
    fi

    # --- Prerequisites and node discovery ---
    local need_remote="false"
    [[ "$BUILD_ARM64" == "true" && "$BUILD_ARM64_LOCAL" == "false" ]] && need_remote="true"
    [[ "$BUILD_AMD64" == "true" && "$BUILD_AMD64_LOCAL" == "false" ]] && need_remote="true"

    if [[ "$need_remote" == "true" ]]; then
        check_prerequisites
        discover_build_nodes
    else
        log "INFO" "All platforms building locally, skipping remote node discovery"
        if [[ ! -f "$DOCKERFILE" ]]; then
            log "ERROR" "Dockerfile not found at $DOCKERFILE"
            FAILURE_REASON="Dockerfile not found"
            exit 1
        fi
    fi

    # --- Sync source code to remote nodes (skip local arches) ---
    local sync_pids=()
    local need_sync="false"

    if [[ "$BUILD_ARM64" == "true" && "$BUILD_ARM64_LOCAL" == "false" ]]; then
        sync_source_code "$ARM64_NODE" "arm64" &
        sync_pids+=($!)
        need_sync="true"
    elif [[ "$BUILD_ARM64" == "true" ]]; then
        write_status "SYNC_ARM64" "skipped"
    fi

    if [[ "$BUILD_AMD64" == "true" && "$BUILD_AMD64_LOCAL" == "false" ]]; then
        sync_source_code "$AMD64_NODE" "amd64" &
        sync_pids+=($!)
        need_sync="true"
    elif [[ "$BUILD_AMD64" == "true" ]]; then
        write_status "SYNC_AMD64" "skipped"
    fi

    if [[ "$need_sync" == "true" ]]; then
        log "INFO" "Syncing source code to remote nodes..."
        for pid in "${sync_pids[@]}"; do wait "$pid" || true; done
    fi

    if [[ "$BUILD_ARM64" == "true" && "$BUILD_ARM64_LOCAL" == "false" && "$(read_status SYNC_ARM64)" == "failed" ]] || \
       [[ "$BUILD_AMD64" == "true" && "$BUILD_AMD64_LOCAL" == "false" && "$(read_status SYNC_AMD64)" == "failed" ]]; then
        log "ERROR" "Sync failed, aborting build"
        FAILURE_REASON="Source code sync failed"
        exit 1
    fi

    # --- Build (parallel: local + remote) ---
    log "INFO" "Building images (native, no emulation)..."
    local build_pids=()

    if [[ "$BUILD_ARM64" == "true" ]]; then
        if [[ "$BUILD_ARM64_LOCAL" == "true" ]]; then
            build_local "arm64" &
        else
            build_on_node "$ARM64_NODE" "arm64" &
        fi
        build_pids+=($!)
    fi

    if [[ "$BUILD_AMD64" == "true" ]]; then
        if [[ "$BUILD_AMD64_LOCAL" == "true" ]]; then
            build_local "amd64" &
        else
            build_on_node "$AMD64_NODE" "amd64" &
        fi
        build_pids+=($!)
    fi

    for pid in "${build_pids[@]}"; do wait "$pid" || true; done

    if [[ "$BUILD_ARM64" == "true" && "$(read_status BUILD_ARM64)" == "failed" ]] || \
       [[ "$BUILD_AMD64" == "true" && "$(read_status BUILD_AMD64)" == "failed" ]]; then
        log "ERROR" "Build failed on one or more nodes"
        FAILURE_REASON="Docker build failed"
        exit 1
    fi

    # --- Push (parallel when multi-arch) ---
    if [[ "$PUSH_IMAGES" == "true" ]]; then
        log "INFO" "Pushing arch-specific images..."
        local push_pids=()

        if [[ "$BUILD_ARM64" == "true" ]]; then
            if [[ "$BUILD_ARM64_LOCAL" == "true" ]]; then
                push_local "arm64" &
            else
                push_from_node "$ARM64_NODE" "arm64" &
            fi
            push_pids+=($!)
        fi
        if [[ "$BUILD_AMD64" == "true" ]]; then
            if [[ "$BUILD_AMD64_LOCAL" == "true" ]]; then
                push_local "amd64" &
            else
                push_from_node "$AMD64_NODE" "amd64" &
            fi
            push_pids+=($!)
        fi

        for pid in "${push_pids[@]}"; do wait "$pid" || true; done

        if [[ "$BUILD_ARM64" == "true" && "$(read_status PUSH_ARM64)" == "failed" ]] || \
           [[ "$BUILD_AMD64" == "true" && "$(read_status PUSH_AMD64)" == "failed" ]]; then
            log "ERROR" "Push failed on one or more nodes"
            FAILURE_REASON="Docker push failed"
            exit 1
        fi

        # Create manifest: multi-arch when both platforms, single-arch when one
        if [[ "$BUILD_ARM64" == "true" && "$BUILD_AMD64" == "true" ]]; then
            if ! create_manifest; then
                FAILURE_REASON="Manifest creation/push failed"
                exit 1
            fi
        else
            # Single-platform: create a manifest for the base tag so that
            # docker pull IMAGE:TAG works (not just IMAGE:TAG-arch)
            if ! create_single_arch_manifest; then
                FAILURE_REASON="Single-arch manifest creation/push failed"
                exit 1
            fi
        fi

        verify_image
        update_compose_tag
    else
        log "INFO" "Skipping push (--no-push)"
        [[ "$BUILD_ARM64" == "true" ]] && write_status "PUSH_ARM64" "skipped"
        [[ "$BUILD_AMD64" == "true" ]] && write_status "PUSH_AMD64" "skipped"
        write_status "MANIFEST" "skipped"
    fi

    # --- Cleanup (remote nodes only) ---
    if [[ "$BUILD_ARM64" == "true" && "$BUILD_ARM64_LOCAL" == "false" ]]; then
        cleanup_remote "$ARM64_NODE" "arm64" &
    fi
    if [[ "$BUILD_AMD64" == "true" && "$BUILD_AMD64_LOCAL" == "false" ]]; then
        cleanup_remote "$AMD64_NODE" "amd64" &
    fi
    wait

    # --- Post-build hook ---
    run_hook "build-post.sh" || true

    BUILD_END_TIME=$(date +%s)
}

main "$@"
