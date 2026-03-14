#!/bin/bash
# Run Flutter web with CORS disabled for Battle.net OAuth token exchange.
# This is for LOCAL DEVELOPMENT ONLY — never use --disable-web-security in production.

# Load secrets from .env file
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

flutter run -d chrome \
  --web-port=8080 \
  --dart-define=BNET_CLIENT_ID="${BNET_CLIENT_ID}" \
  --dart-define=BNET_REDIRECT_URI="${BNET_REDIRECT_URI}" \
  --dart-define=AUTH_PROXY_URL="${AUTH_PROXY_URL}" \
  --web-browser-flag="--disable-web-security" \
  --web-browser-flag="--user-data-dir=/tmp/flutter-chrome-dev"
