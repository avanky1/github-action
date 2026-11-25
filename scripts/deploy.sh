#!/usr/bin/env bash
# Runs ON THE EC2 instance. Activates a new release atomically, verifies it,
# and rolls back to the previous release if the health check fails.
#
# Usage: deploy.sh <app_root> <release_id>
set -euo pipefail

APP_ROOT="${1:?usage: deploy.sh <app_root> <release_id>}"
RELEASE_ID="${2:?usage: deploy.sh <app_root> <release_id>}"
KEEP="${KEEP_RELEASES:-5}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:3000/api/health}"

RELEASES_DIR="$APP_ROOT/releases"
RELEASE_DIR="$RELEASES_DIR/$RELEASE_ID"
CURRENT_LINK="$APP_ROOT/current"

if [ ! -f "$RELEASE_DIR/server.js" ]; then
  echo "Release '$RELEASE_ID' not found at '$RELEASE_DIR'" >&2
  exit 1
fi

PREV_TARGET="$(readlink -f "$CURRENT_LINK" 2>/dev/null || true)"

echo "==> Activating release $RELEASE_ID"
ln -sfn "$RELEASE_DIR" "$CURRENT_LINK"

cd "$APP_ROOT"
pm2 startOrReload ecosystem.config.js --update-env

echo "==> Waiting for health: $HEALTH_URL"
healthy=0
for _ in $(seq 1 15); do
  if curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
    healthy=1
    break
  fi
  sleep 1
done

if [ "$healthy" -ne 1 ]; then
  echo "!! Health check FAILED for $RELEASE_ID" >&2
  if [ -n "$PREV_TARGET" ] && [ -d "$PREV_TARGET" ]; then
    echo "==> Rolling back to $PREV_TARGET" >&2
    ln -sfn "$PREV_TARGET" "$CURRENT_LINK"
    pm2 startOrReload ecosystem.config.js --update-env
  fi
  exit 1
fi

echo "==> Release $RELEASE_ID is healthy"
pm2 save

echo "==> Pruning old releases (keeping $KEEP)"
ls -1dt "$RELEASES_DIR"/*/ 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -rf
