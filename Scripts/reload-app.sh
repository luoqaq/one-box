#!/bin/bash
# Package (optional) -> quit running OneBox -> open the new .app.
# Usage:
#   ./Scripts/reload-app.sh              # package-app.sh then replace
#   ./Scripts/reload-app.sh --no-build   # replace existing Scripts/build/OneBox.app only
#   ./Scripts/reload-app.sh /path/to/out # package into OUT then replace
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="OneBox"
BUNDLE_ID="com.onebox.app"
DO_BUILD=1
OUT_DIR="$REPO_ROOT/Scripts/build"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build) DO_BUILD=0; shift ;;
    -h|--help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    *)
      OUT_DIR="$1"
      shift
      ;;
  esac
done

APP_ROOT="${OUT_DIR}/${APP_NAME}.app"

if [[ "$DO_BUILD" -eq 1 ]]; then
  echo "==> package"
  "$REPO_ROOT/Scripts/package-app.sh" "$OUT_DIR"
fi

if [[ ! -d "$APP_ROOT" ]]; then
  echo "error: missing ${APP_ROOT} (package first, or drop --no-build)" >&2
  exit 1
fi

# Package first, then quit: a failed build must not kill the running app.
pids="$(pgrep -x "$APP_NAME" 2>/dev/null || true)"
if [[ -n "$pids" ]]; then
  echo "==> quit running ${APP_NAME} (pid: ${pids})"
  osascript -e "tell application id \"${BUNDLE_ID}\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 50); do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "==> still alive, SIGTERM"
    pkill -x "$APP_NAME" || true
    sleep 0.3
  fi
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "error: could not quit old process; quit manually and retry" >&2
    exit 1
  fi
else
  echo "==> no running ${APP_NAME}"
fi

echo "==> open ${APP_ROOT}"
open "$APP_ROOT"

for _ in $(seq 1 40); do
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    new_pid="$(pgrep -x "$APP_NAME" | tr '\n' ' ')"
    echo "==> replaced: ${APP_NAME} running (pid: ${new_pid})"
    exit 0
  fi
  sleep 0.1
done

echo "warn: open ran but process not seen yet; check Dock / menu bar" >&2
exit 0
