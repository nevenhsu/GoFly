#!/bin/bash
set -euo pipefail

APP_SOURCE="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$APP_SOURCE/GoFly.app"
INSTALL_TARGET="/Applications/GoFly.app"
APPLICATIONS_DIR="$(/usr/bin/dirname "$INSTALL_TARGET")"

if [ ! -d "$SOURCE_APP" ] || [ ! -x "$SOURCE_APP/Contents/MacOS/GoFlyMac" ]; then
  echo "GoFly.app must be next to install.sh on the mounted GoFly disk image." >&2
  exit 1
fi

if [ -e "$INSTALL_TARGET" ]; then
  printf 'Replace %s? This replaces only the app bundle and keeps GoFly user data. [y/N] ' "$INSTALL_TARGET" > /dev/tty
  IFS= read -r answer < /dev/tty || answer=""
  case "$answer" in
    y|Y|yes|YES|Yes) ;;
    *) echo "Installation cancelled."; exit 0 ;;
  esac
fi

TEMP_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/GoFly-install.XXXXXX")"
STAGED_APP="$TEMP_ROOT/GoFly.app"
STAGED_TARGET="$APPLICATIONS_DIR/.GoFly.app.install-$$"
BACKUP_TARGET="$APPLICATIONS_DIR/.GoFly.app.previous-$$"
BACKUP_CREATED=0
TARGET_PUBLISHED=0

cleanup() {
  status=$?
  if [ "$status" -ne 0 ] && [ "$BACKUP_CREATED" -eq 1 ] && [ ! -e "$INSTALL_TARGET" ]; then
    /bin/mv "$BACKUP_TARGET" "$INSTALL_TARGET" || true
  fi
  if [ "$TARGET_PUBLISHED" -eq 0 ]; then /bin/rm -rf "$STAGED_TARGET"; fi
  /bin/rm -rf "$TEMP_ROOT"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

/usr/bin/ditto "$SOURCE_APP" "$STAGED_APP"
/usr/bin/ditto "$STAGED_APP" "$STAGED_TARGET"
/usr/bin/xattr -dr com.apple.quarantine "$STAGED_TARGET"

if [ -e "$INSTALL_TARGET" ]; then
  /bin/mv "$INSTALL_TARGET" "$BACKUP_TARGET"
  BACKUP_CREATED=1
fi
if ! /bin/mv "$STAGED_TARGET" "$INSTALL_TARGET"; then
  if [ "$BACKUP_CREATED" -eq 1 ]; then
    /bin/mv "$BACKUP_TARGET" "$INSTALL_TARGET"
    BACKUP_CREATED=0
  fi
  echo "Could not install GoFly in /Applications. Check your account's write access; do not use sudo." >&2
  exit 1
fi
TARGET_PUBLISHED=1

if [ "$BACKUP_CREATED" -eq 1 ]; then
  /bin/rm -rf "$BACKUP_TARGET"
  BACKUP_CREATED=0
fi

open "$INSTALL_TARGET"
echo "Installed GoFly at $INSTALL_TARGET. GoFly user data was not changed."
