#!/usr/bin/env bash
# iterate.sh — Inner-loop dev script for the bc-copilot-blueprint.
#
# This is the ONE command Copilot (or a human) runs after editing AL
# code. It compiles your app + test, publishes them to the running BC
# instance, and runs the tests. BC is expected to already be up; if not,
# this script brings it up once and reuses it for the rest of the session.
#
# Typical inner loop:
#   1. Edit AL files in app/src/ or test/src/
#   2. ./scripts/iterate.sh
#   3. Read output, fix, repeat
#
# BC is NEVER restarted between iterations — that's the whole point.
# A clean BC takes ~5 minutes to boot; an iteration here takes seconds.

set -uo pipefail

# === Paths ===
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BC_LINUX_DIR="${BC_LINUX_DIR:-$REPO_DIR/.bc-linux}"
BC_ARTIFACTS_DIR="${BC_ARTIFACTS_DIR:-$REPO_DIR/.bc-artifacts}"
SYMBOLS_DIR="${SYMBOLS_DIR:-$REPO_DIR/.symbols}"
BUILD_DIR="${BUILD_DIR:-$REPO_DIR/build}"

# Pull defaults from setup-time cache if available (BC_KEEP_APP_IDS, etc.)
if [ -f "$REPO_DIR/.bc-cache/env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$REPO_DIR/.bc-cache/env"
    set +a
fi

BC_VERSION="${BC_VERSION:-27.5}"
BC_COUNTRY="${BC_COUNTRY:-w1}"
BC_TYPE="${BC_TYPE:-sandbox}"
APP_DIR="${APP_DIR:-app}"
TEST_DIR="${TEST_DIR:-test}"
CODEUNIT_RANGE="${CODEUNIT_RANGE:-50000..99999}"

AUTH="BCRUNNER:Admin123!"
DEV="http://localhost:7049"

mkdir -p "$BUILD_DIR"

# === Sanity checks ===
if [ ! -d "$BC_LINUX_DIR" ]; then
    echo "ERROR: bc-linux clone not found at $BC_LINUX_DIR"
    echo "       (copilot-setup-steps.yml should have placed it there)"
    echo "       To set up locally: git clone https://github.com/StefanMaron/MsDyn365Bc.On.Linux $BC_LINUX_DIR"
    exit 1
fi
if [ ! -d "$BC_ARTIFACTS_DIR/$BC_VERSION" ]; then
    echo "ERROR: BC artifacts not found at $BC_ARTIFACTS_DIR/$BC_VERSION"
    echo "       (copilot-setup-steps.yml should have downloaded them)"
    exit 1
fi
if ! command -v AL >/dev/null 2>&1; then
    echo "ERROR: AL compiler not on PATH. Did setup install Microsoft.Dynamics.BusinessCentral.Development.Tools.Linux?"
    exit 1
fi

# === Ensure BC is running ===
ensure_bc_running() {
    local cid
    cid=$(cd "$BC_LINUX_DIR" && BC_ARTIFACTS_DIR="$BC_ARTIFACTS_DIR/$BC_VERSION" \
        BC_VERSION="$BC_VERSION" BC_COUNTRY="$BC_COUNTRY" BC_TYPE="$BC_TYPE" \
        BC_RUNNER_IMAGE="${BC_RUNNER_IMAGE:-ghcr.io/stefanmaron/msdyn365bc.on.linux/bc-runner:latest}" \
        docker compose ps -q bc 2>/dev/null | head -1)

    if [ -n "$cid" ]; then
        local status
        status=$(docker inspect --format='{{.State.Health.Status}}' "$cid" 2>/dev/null || echo unknown)
        if [ "$status" = "healthy" ]; then
            echo "[iterate] BC already running (healthy)."
            return 0
        fi
        echo "[iterate] BC container exists but not healthy yet (status: $status). Waiting..."
    else
        echo "[iterate] Starting BC (one-time per session, ~1-2 min with warm caches)..."
        ( cd "$BC_LINUX_DIR" \
          && BC_ARTIFACTS_DIR="$BC_ARTIFACTS_DIR/$BC_VERSION" \
             BC_VERSION="$BC_VERSION" BC_COUNTRY="$BC_COUNTRY" BC_TYPE="$BC_TYPE" \
             BC_CLEAR_ALL_APPS="${BC_CLEAR_ALL_APPS:-selective}" \
             BC_KEEP_APP_IDS="${BC_KEEP_APP_IDS:-}" \
             BC_RUNNER_IMAGE="${BC_RUNNER_IMAGE:-ghcr.io/stefanmaron/msdyn365bc.on.linux/bc-runner:latest}" \
             docker compose up -d ) || { echo "ERROR: docker compose up failed"; exit 1; }
    fi

    # Wait for healthy.
    for i in $(seq 1 360); do
        cid=$(cd "$BC_LINUX_DIR" && docker compose ps -q bc 2>/dev/null | head -1)
        [ -z "$cid" ] && { sleep 2; continue; }
        local status
        status=$(docker inspect --format='{{.State.Health.Status}}' "$cid" 2>/dev/null || echo unknown)
        case "$status" in
            healthy)   echo "[iterate] BC ready."; return 0 ;;
            unhealthy) echo "ERROR: BC unhealthy. Last logs:"; (cd "$BC_LINUX_DIR" && docker compose logs bc | tail -80); exit 1 ;;
        esac
        sleep 5
    done
    echo "ERROR: BC did not become healthy within 30 minutes"
    (cd "$BC_LINUX_DIR" && docker compose logs bc | tail -80)
    exit 1
}

# === Compile one AL app dir ===
compile_dir() {
    local src="$1"
    local out="$2"
    [ -f "$src/app.json" ] || { echo "skip $src (no app.json)"; return 0; }
    mkdir -p "$src/.alpackages"
    cp "$SYMBOLS_DIR"/*.app "$src/.alpackages/" 2>/dev/null || true
    # Copy any previously built apps too (so test can resolve app as a dep).
    cp "$BUILD_DIR"/*.app "$src/.alpackages/" 2>/dev/null || true
    echo "[iterate] Compiling $src → $out"
    AL compile "/project:$src" "/packagecachepath:$src/.alpackages" "/out:$out"
}

# === Publish one .app to the running BC ===
#
# Delegates to bc_publish_app from bc-linux's shared publish-app.sh
# helper. The shared helper handles 200/422 distinction (only 422s with
# "already" in the body are treated as benign), prints diagnostic dumps
# on real failures, and is the single canonical implementation that
# both this script and run-tests.sh call into.
#
# We source it lazily on first call rather than at script load time
# because refresh_bc_linux may not have pulled .bc-linux/ yet when the
# script is parsed.
publish_app() {
    local app="$1"
    [ -f "$app" ] || { echo "ERROR: $app not built"; exit 1; }
    if ! declare -F bc_publish_app >/dev/null; then
        local helper="$BC_LINUX_DIR/scripts/publish-app.sh"
        if [ ! -f "$helper" ]; then
            echo "ERROR: $helper not found — refresh_bc_linux didn't run, or"
            echo "       this bc-linux checkout predates the shared helper."
            exit 1
        fi
        # shellcheck disable=SC1090,SC1091
        . "$helper"
    fi
    echo "[iterate] Publishing $(basename "$app")"
    bc_publish_app "$app" "$DEV" "$AUTH" || exit 1
}

# === Refresh the bc-linux clone ===
#
# .bc-linux/ is checked out once during copilot-setup-steps.yml and then
# persists for the entire agent session. That means improvements pushed
# to bc-linux master AFTER setup ran are invisible until we explicitly
# fetch them. Since the blueprint deliberately consumes bc-linux from
# master (no pinning), every iterate.sh invocation should pull the
# latest. Cost is ~one second on a fast no-op fetch.
#
# Uses fetch+reset rather than `git pull` because actions/checkout makes
# a shallow clone and `git pull --rebase` is fragile on shallow histories.
refresh_bc_linux() {
    [ -d "$BC_LINUX_DIR/.git" ] || return 0
    echo -n "[iterate] Refreshing $BC_LINUX_DIR to bc-linux master... "
    if git -C "$BC_LINUX_DIR" fetch --quiet origin master --depth=1 2>/dev/null \
       && git -C "$BC_LINUX_DIR" reset --quiet --hard FETCH_HEAD 2>/dev/null; then
        local sha
        sha=$(git -C "$BC_LINUX_DIR" rev-parse --short HEAD 2>/dev/null || echo "?")
        echo "OK ($sha)"
    else
        echo "skipped (offline or non-git checkout)"
    fi
}

# === Main ===
refresh_bc_linux
ensure_bc_running

APP_OUT="$BUILD_DIR/$(basename "$APP_DIR").app"
TEST_OUT="$BUILD_DIR/$(basename "$TEST_DIR").app"

compile_dir "$REPO_DIR/$APP_DIR" "$APP_OUT"
compile_dir "$REPO_DIR/$TEST_DIR" "$TEST_OUT"

publish_app "$APP_OUT"
publish_app "$TEST_OUT"

echo ""
echo "[iterate] === Running tests ==="
# run-tests.sh expects to be invoked from inside the bc-linux clone so its
# `docker compose ps -q bc` resolves the right project. The --app path must
# be absolute since we're cd-ing.
cd "$BC_LINUX_DIR"
./scripts/run-tests.sh \
    --app "$TEST_OUT" \
    --codeunit-range "$CODEUNIT_RANGE" \
    --timeout 30
