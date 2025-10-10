#!/bin/bash
set -eo pipefail

echo "🔧 ci_pre_xcodebuild.sh: CI_WORKSPACE=${CI_WORKSPACE}"

# 共有環境変数チェック
if [ -z "${SUPABASE_URL:-}" ]; then
  echo "❌ SUPABASE_URL is not set"; exit 1
fi
if [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  echo "❌ SUPABASE_ANON_KEY is not set"; exit 1
fi

DEST_DIR="$CI_WORKSPACE/PollSNS/Config"
DEST_FILE="$DEST_DIR/GeneratedSecrets.xcconfig"
mkdir -p "$DEST_DIR"

cat > "$DEST_FILE" <<EOT
SUPABASE_URL = ${SUPABASE_URL}
SUPABASE_ANON_KEY = ${SUPABASE_ANON_KEY}
EOT

echo "✅ Wrote $DEST_FILE"
ls -la "$DEST_DIR"
