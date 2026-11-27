#!/usr/bin/env bash
set -euo pipefail
target="${1:-final-artifacts/release-notes.md}"
tag="${2:-}"

if [[ -z "$tag" ]]; then
  tag="${GITHUB_REF_NAME:-}"
fi

cat >> "$target" <<EOF

### 下载地址：

- **Android**：[SunsetRipple-${tag}.apk](https://github.com/Starlordzz/sunsetripple/releases/download/${tag}/SunsetRipple-${tag}.apk)
EOF