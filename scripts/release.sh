#!/usr/bin/env bash
# make release VERSION=x.y.z — PDR §7.3. Aborts on any failed precondition.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

die() { echo "error: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

VERSION="${1:-}"
[[ -n "$VERSION" ]] || die "usage: make release VERSION=x.y.z"
TAG="v$VERSION"
APP_NAME="OmniWM Extension"
ZIP_NAME="OmniWM-Extension-$VERSION.zip"
OUT_DIR="$ROOT/build/release"
REPO="hanswug/omniwm-extension"

command -v gh >/dev/null || die "gh not installed"

# 1. On main, clean tree, in sync with origin/main.
step "Checking git state"
[[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || die "not on main"
[[ -z "$(git status --porcelain)" ]] || die "working tree not clean"
git fetch --quiet origin main --tags
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die "main is not in sync with origin/main"

# 2. VERSION is valid SemVer and greater than the latest tag.
step "Checking version $VERSION"
SEMVER='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
[[ "$VERSION" =~ $SEMVER ]] || die "\"$VERSION\" is not SemVer (x.y.z)"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "tag $TAG already exists"
LATEST="$(git tag -l 'v*' --sort=-v:refname | head -n1)"
if [[ -n "$LATEST" ]]; then
  LATEST="${LATEST#v}"
  HIGHEST="$(printf '%s\n%s\n' "$LATEST" "$VERSION" | sort -V | tail -n1)"
  [[ "$HIGHEST" == "$VERSION" && "$LATEST" != "$VERSION" ]] || die "$VERSION is not greater than latest tag v$LATEST"
  echo "latest tag: v$LATEST"
else
  echo "no previous tags"
fi

# 3. CHANGELOG has a "## [x.y.z] - YYYY-MM-DD" section; its body becomes the notes.
step "Extracting release notes"
ESCAPED="${VERSION//./\\.}"
grep -Eq "^## \[$ESCAPED\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" CHANGELOG.md \
  || die "CHANGELOG.md has no '## [$VERSION] - YYYY-MM-DD' section"
mkdir -p "$OUT_DIR"
NOTES="$OUT_DIR/notes-$VERSION.md"
awk -v hdr="## [$VERSION] - " '
  index($0, hdr) == 1 { inside = 1; next }
  inside && /^## \[/ { exit }
  inside { print }
' CHANGELOG.md | sed -e '/./,$!d' > "$NOTES"   # drop leading blank lines
[[ -n "$(tr -d '[:space:]' < "$NOTES")" ]] || die "release notes for $VERSION are empty"
cat "$NOTES"

# 4. Tests pass.
step "Running tests"
make test

# 5. Write VERSION, commit, annotated tag. Undo both if anything fails before the push.
step "Committing $TAG"
PUSHED=0
rollback() {
  if [[ "$PUSHED" == 0 ]]; then
    echo "Release failed before push; removing local tag and release commit." >&2
    git tag -d "$TAG" >/dev/null 2>&1 || true
    if [[ "$(git log -1 --format=%s)" == "chore(release): $TAG" ]]; then
      git reset --hard --quiet HEAD~1
    fi
  fi
}
trap rollback ERR

echo "$VERSION" > VERSION
git add VERSION
git commit --quiet -m "chore(release): $TAG"
git tag -a "$TAG" -m "$TAG"

# 6. Build, zip, checksum.
step "Building"
make build
APP="$ROOT/build/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "error: $APP missing after build" >&2; false; }
rm -f "$OUT_DIR/$ZIP_NAME" "$OUT_DIR/$ZIP_NAME.sha256"
ditto -c -k --keepParent "$APP" "$OUT_DIR/$ZIP_NAME"
(cd "$OUT_DIR" && shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256")
cat "$OUT_DIR/$ZIP_NAME.sha256"

# 7. Push.
step "Pushing"
git push origin main --follow-tags
PUSHED=1
trap - ERR

# 8. GitHub release.
step "Creating GitHub release"
gh release create "$TAG" "$OUT_DIR/$ZIP_NAME" "$OUT_DIR/$ZIP_NAME.sha256" \
  -R "$REPO" --title "$TAG" --notes-file "$NOTES"

echo
echo "Released $TAG: $(gh release view "$TAG" -R "$REPO" --json url -q .url)"
