#!/bin/bash
set -e

# Usage: ./release.sh 0.2.0

VERSION=$1
if [ -z "$VERSION" ]; then
  echo "Usage: ./release.sh <version>"
  echo "Example: ./release.sh 0.2.0"
  exit 1
fi

# Load secrets from .env
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

if [ -z "$BNET_CLIENT_ID" ] || [ -z "$AUTH_PROXY_URL" ]; then
  echo "Error: .env must have BNET_CLIENT_ID and AUTH_PROXY_URL"
  exit 1
fi

DART_DEFINES="--dart-define=BNET_CLIENT_ID=${BNET_CLIENT_ID} --dart-define=AUTH_PROXY_URL=${AUTH_PROXY_URL}"

echo "==> Releasing v${VERSION}"

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
  --dart-define=BNET_REDIRECT_URI=https://faizal97.github.io/mobile-wow-companion/auth/callback \
  --base-href="/mobile-wow-companion/"
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
  "${APK_PATH}#wow-companion-v${VERSION}.apk" \
  --title "v${VERSION}" \
  --notes "## WoW Companion v${VERSION}

### Download
- **Android**: Download the APK below
- **Web**: [faizal97.github.io/mobile-wow-companion](https://faizal97.github.io/mobile-wow-companion/)
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

git add -A
git commit -m "Deploy v${VERSION} to GitHub Pages"
git push

# Switch back to main
git checkout main

# Cleanup
rm -rf /tmp/wow-web-deploy-${VERSION}

echo ""
echo "==> Done! v${VERSION} released"
echo "    APK: https://github.com/faizal97/mobile-wow-companion/releases/tag/v${VERSION}"
echo "    Web: https://faizal97.github.io/mobile-wow-companion/"
