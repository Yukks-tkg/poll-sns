#!/bin/bash
set -euo pipefail

# Xcode Cloud のワークスペース配下に Secrets.xcconfig を生成
mkdir -p "$CI_WORKSPACE/PollSNS/Config"

cat > "$CI_WORKSPACE/PollSNS/Config/Secrets.xcconfig" <<EOT
SUPABASE_URL = ${SUPABASE_URL}
SUPABASE_ANON_KEY = ${SUPABASE_ANON_KEY}
EOT

echo "✅ Generated PollSNS/Config/Secrets.xcconfig"
