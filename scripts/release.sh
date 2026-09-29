#!/bin/sh
# Publishes the version in VERSION: builds the app, attaches it to a GitHub
# release, and points the Homebrew cask (bilal-psd/homebrew-tap) at it.
#
#   echo 1.0.1 > VERSION && git commit -am "Popnote 1.0.1" && scripts/release.sh
set -e
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
TAG="v$VERSION"

if [ -n "$(git status --porcelain)" ]; then
    echo "Commit or stash your changes first." >&2
    exit 1
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "$TAG already exists. Change VERSION first." >&2
    exit 1
fi

swift test
sh scripts/bundle.sh

# The asset keeps the same name every release, so install.sh can always
# download releases/latest/download/Popnote.zip.
ZIP=build/Popnote.zip
rm -f "$ZIP"
ditto -c -k --keepParent build/Popnote.app "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

git tag "$TAG"
git push origin HEAD "$TAG"
gh release create "$TAG" "$ZIP" --title "Popnote $VERSION" --generate-notes

TAP=$(mktemp -d)
trap 'rm -rf "$TAP"' EXIT
gh repo clone bilal-psd/homebrew-tap "$TAP" -- --quiet
mkdir -p "$TAP/Casks"
sed -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/$SHA/" scripts/popnote.rb.in > "$TAP/Casks/popnote.rb"
git -C "$TAP" add Casks/popnote.rb
# Same identity as this repo, not whatever the machine defaults to.
git -C "$TAP" -c user.name="$(git config user.name)" -c user.email="$(git config user.email)" \
    commit --quiet -m "Popnote $VERSION"
git -C "$TAP" push --quiet

echo "Released Popnote $VERSION"
