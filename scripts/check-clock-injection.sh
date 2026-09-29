#!/usr/bin/env bash
# 门禁：lib/core 下的时间逻辑必须走可注入时钟（见 lib/core/clock.dart）。
#
# 为什么要有这条门禁：`HostFailoverTracker.evaluate()` 此前直接读 DateTime.now()，
# 于是「房主失联 6 秒后接管」这条规则只能靠**真的等 6 秒**来验证，覆盖率长期为 0。
# 口头约定拦不住下一次，所以把「时钟必须注入」变成可执行检查。
#
# 例外只有两种，且都必须写在代码里能被复审：
#   1. lib/core/clock.dart —— 系统时钟适配器本身（白名单）
#   2. 同一行带 `// clock-exempt: <理由>` 的调用点（协议/日志/模型的默认值）
set -uo pipefail

cd "$(dirname "$0")/.."

ALLOWLIST=("lib/core/clock.dart")

violations=0

report() {
  local file="$1" line="$2" reason="$3"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error file=${file},line=${line}::${reason}"
  else
    echo "VIOLATION  ${file}:${line}  ${reason}"
  fi
}

while IFS= read -r hit; do
  file="${hit%%:*}"
  rest="${hit#*:}"
  line="${rest%%:*}"
  content="${rest#*:}"

  # 只认代码，不认注释里提到的 DateTime.now()。
  trimmed="${content#"${content%%[![:space:]]*}"}"
  case "$trimmed" in
    //* | '*'*) continue ;;
  esac

  skip=0
  for allowed in "${ALLOWLIST[@]}"; do
    [[ "$file" == "$allowed" ]] && skip=1
  done
  [[ "$skip" == 1 ]] && continue
  [[ "$content" == *"clock-exempt:"* ]] && continue

  report "$file" "$line" \
    "lib/core 下直接调用 DateTime.now()：请注入 Clock（见 lib/core/clock.dart），或在同一行写明 // clock-exempt: <理由>"
  violations=$((violations + 1))
done < <(grep -rn --include='*.dart' -E 'DateTime\.now\(\)' lib/core || true)

if [[ "$violations" -gt 0 ]]; then
  echo
  echo "共 $violations 处直接读取系统时间；门禁实现见 scripts/check-clock-injection.sh。"
  exit 1
fi

echo "时钟门禁通过：lib/core 下没有未豁免的 DateTime.now() 调用。"
