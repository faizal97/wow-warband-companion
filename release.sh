#!/bin/bash
set -e

# Usage: ./release.sh [major|minor|patch]

BUMP=$1
if [ -z "$BUMP" ] || [[ ! "$BUMP" =~ ^(major|minor|patch)$ ]]; then
  echo "Usage: ./release.sh [major|minor|patch]"
  echo ""
  echo "Examples:"
  echo "  ./release.sh patch   # 0.1.0 -> 0.1.1"
  echo "  ./release.sh minor   # 0.1.0 -> 0.2.0"
  echo "  ./release.sh major   # 0.1.0 -> 1.0.0"
  exit 1
fi

# Fetch remote tags and get latest version
git fetch --tags --quiet
LATEST=$(git tag --sort=-v:refname | head -1 | sed 's/^v//')
if [ -z "$LATEST" ]; then
  LATEST="0.0.0"
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$LATEST"

case $BUMP in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac

VERSION="${MAJOR}.${MINOR}.${PATCH}"
echo "==> Bumping ${LATEST} -> ${VERSION} (${BUMP})"

# Load secrets from .env
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

if [ -z "$BNET_CLIENT_ID" ] || [ -z "$AUTH_PROXY_URL" ]; then
  echo "Error: .env must have BNET_CLIENT_ID and AUTH_PROXY_URL"
  exit 1
fi

DART_DEFINES="--dart-define=BNET_CLIENT_ID=${BNET_CLIENT_ID} --dart-define=AUTH_PROXY_URL=${AUTH_PROXY_URL}"

# 0. Clean build
echo ""
echo "==> Cleaning build..."
flutter clean > /dev/null 2>&1
flutter pub get > /dev/null 2>&1

# 1. Build Android APK
echo ""
echo "==> Building Android APK..."
flutter build apk --release \
  $DART_DEFINES \
  --dart-define=BNET_REDIRECT_URI=http://localhost:8080/auth/callback

APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
APK_SIZE=$(du -h "$APK_PATH" | cut -f1 | xargs)
echo "    APK built: ${APK_SIZE}"

# 2. Build Web
echo ""
echo "==> Building Web..."
flutter build web --release \
  $DART_DEFINES \
  --dart-define=BNET_REDIRECT_URI=https://faizal97.github.io/wow-warband-companion/auth/callback \
  --base-href="/wow-warband-companion/"
echo "    Web built"

# 3. Commit and push main (if there are changes)
if [ -n "$(git status --porcelain)" ]; then
  echo ""
  echo "==> Committing changes on main..."
  git add -A
  git commit -m "Release v${VERSION}"
  git push
fi

# 4. Create GitHub Release with APK
echo ""
echo "==> Creating GitHub Release v${VERSION}..."
gh release create "v${VERSION}" \
  "${APK_PATH}#wow-warband-companion-v${VERSION}.apk" \
  --title "v${VERSION}" \
  --notes "## WoW Warband Companion v${VERSION}

### Download
- **Android**: Download the APK below
- **Web**: [faizal97.github.io/wow-warband-companion](https://faizal97.github.io/wow-warband-companion/)
"

# 5. Deploy Web to gh-pages
echo ""
echo "==> Deploying to GitHub Pages..."
cp -r build/web /tmp/wow-web-deploy-${VERSION}

git checkout gh-pages

# Remove old web files but keep .git
find . -maxdepth 1 ! -name '.git' ! -name '.' -exec rm -rf {} +

# Copy new web build
cp -r /tmp/wow-web-deploy-${VERSION}/* .
touch .nojekyll
cp index.html 404.html  # SPA routing for OAuth callback

git add -A
git commit -m "Deploy v${VERSION} to GitHub Pages"
git push

# Switch back to main
git checkout main

# Cleanup
rm -rf /tmp/wow-web-deploy-${VERSION}

echo ""
echo "==> Done! v${VERSION} released"
echo "    APK: https://github.com/faizal97/wow-warband-companion/releases/tag/v${VERSION}"
echo "    Web: https://faizal97.github.io/wow-warband-companion/"
