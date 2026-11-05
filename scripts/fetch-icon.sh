#!/usr/bin/env bash
# Extracts the OmniWM app icon into App/Resources and generates the menu bar
# template PNGs from its alpha silhouette (PDR §7.4). Outputs are committed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RES="$ROOT/App/Resources"
OMNIWM_RES="${OMNIWM_APP:-/Applications/OmniWM.app}/Contents/Resources"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [[ -f "$OMNIWM_RES/AppIcon.icns" ]]; then
  cp "$OMNIWM_RES/AppIcon.icns" "$WORK/AppIcon.icns"
elif [[ -f "$OMNIWM_RES/Assets.car" ]]; then
  echo "No AppIcon.icns, extracting from Assets.car"
  # iconutil can export a named icon straight from a compiled asset catalog.
  NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$OMNIWM_RES/../Info.plist" 2>/dev/null || echo AppIcon)"
  xcrun --sdk macosx iconutil -c icns "$OMNIWM_RES/Assets.car" "$NAME" -o "$WORK/AppIcon.icns"
else
  echo "error: no icon found in $OMNIWM_RES" >&2
  exit 1
fi

mkdir -p "$RES"
cp "$WORK/AppIcon.icns" "$RES/AppIcon.icns"
swift "$ROOT/scripts/make-template-icon.swift" "$RES/AppIcon.icns" "$RES/MenuBarIcon.png" 18
swift "$ROOT/scripts/make-template-icon.swift" "$RES/AppIcon.icns" "$RES/MenuBarIcon@2x.png" 36

echo "Wrote:"
ls -l "$RES/AppIcon.icns" "$RES/MenuBarIcon.png" "$RES/MenuBarIcon@2x.png"
