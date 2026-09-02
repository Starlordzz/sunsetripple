#!/usr/bin/env bash
# 校验鸿蒙工程引用的资源与构建入口是否齐备。
# 本地直接跑：bash scripts/check-harmonyos-resources.sh
# CI 里由 .github/workflows/release.yml 的 package-harmonyos job 调用。
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0

# 在 GitHub Actions 下输出注解，本地则保持纯文本可读。
err() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::$1"
  else
    echo "MISSING  $1"
  fi
}

refs=$(grep -rhoE '\$(media|string|color|profile):[A-Za-z0-9_]+' \
         harmonyos/AppScope/app.json5 \
         harmonyos/entry/src/main/module.json5 | sort -u)

echo "发现引用："
echo "$refs" | sed 's/^/  /'
echo

for ref in $refs; do
  kind="${ref#\$}"; kind="${kind%%:*}"
  name="${ref##*:}"
  found=""
  case "$kind" in
    media)
      found=$(find harmonyos -type f -path '*/resources/*/media/*' \
                -name "${name}.*" -print -quit)
      ;;
    profile)
      found=$(find harmonyos -type f -path '*/resources/*/profile/*' \
                -name "${name}.json" -print -quit)
      ;;
    string|color)
      found=$(grep -rls --include='*.json' \
                "\"name\"[[:space:]]*:[[:space:]]*\"${name}\"" \
                harmonyos | head -n1)
      ;;
  esac
  if [[ -z "$found" ]]; then
    err "资源缺失 ${ref} —— ${kind} 下未找到 ${name}"
    fail=1
  else
    echo "ok       ${ref}  ->  ${found}"
  fi
done

echo
for f in harmonyos/build-profile.json5 \
         harmonyos/oh-package.json5 \
         harmonyos/hvigorfile.ts \
         harmonyos/hvigor/hvigor-config.json5; do
  if [[ -f "$f" ]]; then
    echo "ok       $f"
  else
    err "缺少 hvigor 构建入口文件 $f"
    fail=1
  fi
done

echo
pub_code="$(sed -nE 's/^version:.*\+([0-9]+)[[:space:]]*$/\1/p' pubspec.yaml)"
ohos_code="$(sed -nE 's/.*"versionCode"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' \
              harmonyos/AppScope/app.json5)"
pub_code="$(grep -E '^version:' pubspec.yaml | sed -nE 's/^version:.*\+([0-9]+).*/\1/p' | tr -d '\r\n ')"
ohos_code="$(grep -E '"versionCode"' harmonyos/AppScope/app.json5 | sed -nE 's/.*"versionCode"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | tr -d '\r\n ')"
echo "pubspec versionCode = '${pub_code}'   AppScope versionCode = '${ohos_code}'"
if [[ "$pub_code" != "$ohos_code" ]]; then
if [[ -z "$pub_code" || -z "$ohos_code" || "$pub_code" != "$ohos_code" ]]; then
  err "versionCode 不一致：pubspec=${pub_code}, AppScope/app.json5=${ohos_code}"
  fail=1
fi

echo
echo "exit=$fail"
exit $fail
