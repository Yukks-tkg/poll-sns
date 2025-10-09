#!/bin/bash
set -eo pipefail
# ※ -u は外しています。代わりに明示的に検証するので、原因が分かりやすいログになります。

echo "🔧 ci_pre_xcodebuild.sh: CI_WORKSPACE=${CI_WORKSPACE}"

# --- 共有環境変数の検証（未設定なら分かりやすく失敗させる） ---
if [ -z "${SUPABASE_URL:-}" ]; then
  echo "❌ SUPABASE_URL is not set in Xcode Cloud shared environment variables." >&2
  exit 1
fi
if [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  echo "❌ SUPABASE_ANON_KEY is not set in Xcode Cloud shared environment variables." >&2
  exit 1
fi
echo "✅ Found envs: SUPABASE_URL length=$(echo -n "$SUPABASE_URL" | wc -c), ANON_KEY length=$(echo -n "$SUPABASE_ANON_KEY" | wc -c)"

# --- Secrets.xcconfig を生成 ---
DEST_DIR="$CI_WORKSPACE/PollSNS/Config"
DEST_FILE="$DEST_DIR/Secrets.xcconfig"
mkdir -p "$DEST_DIR"

cat > "$DEST_FILE" <<EOT
SUPABASE_URL = ${SUPABASE_URL}
SUPABASE_ANON_KEY = ${SUPABASE_ANON_KEY}
EOT

echo "✅ Wrote $DEST_FILE"
echo "📂 Listing $DEST_DIR:"
ls -la "$DEST_DIR"
