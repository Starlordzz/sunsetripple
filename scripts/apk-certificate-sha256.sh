#!/usr/bin/env bash
# 读出一个 APK 的签名证书 SHA-256（64 位小写 hex），供发布流程写进签名更新清单。
#
# 为什么要单独一个脚本：`release.yml` 里「校验签名」与「签名更新清单」两处都要读同一个值，
# 而之前两处各自内联了一段 `apksigner ... | awk`。这段内联逻辑在 GitHub 的 runner 上会
# **退出码 0 且不输出任何内容**（2026-09-29 的发布实测：校验那一步拿到空 DN 却照样通过，
# 到了签名清单那一步才炸成「无法解析签名证书 SHA-256」）。因此这里做三件事：
#   1. 首选 apksigner（摘要取自实际要发布的 APK 字节），并容忍输出格式差异、捕获退出码与输出；
#   2. apksigner 拿不到就回退到 keystore 里那把钥匙的证书摘要（发布包正是用它签的）；
#   3. 两边都能读到摘要时必须一致——不一致说明这份 APK 根本不是这把密钥签的，直接失败。
#
# 用法：scripts/apk-certificate-sha256.sh <apk> [keystore] [storepass] [alias]
#   <apk>       必填，实际要发布的 APK
#   [keystore]  PKCS12 keystore；给了它才启用 keystore 回退与一致性交叉校验
# 输出：stdout 只有 64 位小写 hex；诊断信息一律走 stderr。
set -uo pipefail

apk="${1:-}"
keystore="${2:-}"
storepass="${3:-}"
alias_name="${4:-}"

log() { echo "apk-certificate-sha256: $*" >&2; }
die() {
  log "$*"
  exit 1
}

[[ -n "$apk" ]] || die "缺少 APK 参数"
[[ -f "$apk" ]] || die "APK 不存在：$apk"
[[ -s "$apk" ]] || die "APK 是空文件：$apk"

# apksigner 输出形如 `Signer #1 certificate SHA-256 digest: <hex>`；
# build-tools 37.0.0 起改为按签名方案标注：`V2 Signer: certificate SHA-256 digest: <hex>`。
# 两种标签都要认，否则在新镜像上会「有输出但解析不出摘要」（2026-09-29 的发布就是这样翻车的：
# 旧正则只认 `Signer #1`，37.0.0 写的是 `V2 Signer:`，于是摘要为空）。
# 这里只认「certificate SHA-256 digest:」这一短语 + 64 位 hex，顺带吃掉 CR、统一小写。
digest_from_apksigner_output() {
  sed -nE 's/.*certificate SHA-256 digest:[[:space:]]*([0-9a-fA-F]{64}).*/\1/p' \
    | head -1 | tr 'A-F' 'a-f'
}

# keytool 输出形如 `SHA256: AA:BB:...`（32 组，冒号分隔）。
digest_from_keytool_output() {
  sed -nE 's/.*SHA256:[[:space:]]*([0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){31}).*/\1/p' \
    | head -1 | tr -d ':' | tr 'A-F' 'a-f'
}

find_apksigner() {
  # 显式覆盖时只要求文件存在：能否执行交给真正调用时去暴露（失败会打印退出码与输出）。
  if [[ -n "${APKSIGNER:-}" && -f "${APKSIGNER}" ]]; then printf '%s' "$APKSIGNER"; return 0; fi
  if command -v apksigner >/dev/null 2>&1; then command -v apksigner; return 0; fi
  if [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
    ls "$ANDROID_SDK_ROOT"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1
  fi
}

apk_digest=""
apksigner_path="$(find_apksigner)"
if [[ -n "$apksigner_path" ]]; then
  apksigner_output="$("$apksigner_path" verify --print-certs "$apk" 2>&1)"
  apksigner_status=$?
  apk_digest="$(printf '%s\n' "$apksigner_output" | digest_from_apksigner_output)"
  if [[ "$apk_digest" =~ ^[0-9a-f]{64}$ ]]; then
    log "apksigner 读出摘要（$apksigner_path）"
  else
    log "apksigner 没给出可用摘要（路径=$apksigner_path 退出码=$apksigner_status），输出前 5 行："
    printf '%s\n' "$apksigner_output" | head -5 >&2
    apk_digest=""
  fi
else
  log "未找到 apksigner（ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT:-<unset>}）"
fi

keystore_digest=""
keytool_bin="${KEYTOOL:-keytool}"
if [[ -n "$keystore" ]]; then
  if [[ -f "$keystore" && -n "$storepass" && -n "$alias_name" ]]; then
    keytool_output="$("$keytool_bin" -list -v -keystore "$keystore" -storetype PKCS12 \
      -storepass "$storepass" -alias "$alias_name" 2>&1)"
    keytool_status=$?
    keystore_digest="$(printf '%s\n' "$keytool_output" | digest_from_keytool_output)"
    if [[ "$keystore_digest" =~ ^[0-9a-f]{64}$ ]]; then
      log "keytool 读出 keystore 证书摘要（keystore=$keystore alias=$alias_name）"
    else
      log "keytool 没给出可用摘要（退出码=$keytool_status），输出前 5 行："
      printf '%s\n' "$keytool_output" | head -5 >&2
      keystore_digest=""
    fi
  else
    log "keystore 参数不完整，跳过交叉校验（keystore=${keystore:-<empty>} storepass=${storepass:+已提供} alias=${alias_name:-<empty>}）"
  fi
fi

if [[ -n "$apk_digest" && -n "$keystore_digest" && "$apk_digest" != "$keystore_digest" ]]; then
  die "APK 的签名证书与发布密钥不一致：APK=$apk_digest keystore=$keystore_digest
      —— 这份包不是用发布的那把密钥签的，绝不允许发布。"
fi

if [[ -n "$apk_digest" ]]; then
  printf '%s\n' "$apk_digest"
  exit 0
fi

if [[ -n "$keystore_digest" ]]; then
  # 回退路径：本 runner 的 apksigner 读不出内容时只能信 keystore。
  # 这不是静默降级——上面已经把「apksigner 为什么没用上」打出来了，这里再点一次名。
  log "警告：改用 keystore 证书摘要（apksigner 在此 runner 上不可用），APK 侧交叉校验已跳过"
  printf '%s\n' "$keystore_digest"
  exit 0
fi

die "无法读出 $apk 的签名证书 SHA-256：apksigner 与 keystore 两条路都失败了"
