#!/bin/bash
# ============================================================================
# 一键解密加密 dmg 并恢复到 ~
# 用法:  bash ~/macos-backup/decrypt-restore.sh [dmg] [选项...]
#   默认 dmg = backups/ 下最新的 *-encrypted.dmg
#   -pass/-p 密码  不传则弹出 macOS 密码输入框
#   其余选项透传给 restore.sh:
#     --dry-run / --no-overwrite / --skip-brew / --fix-user 旧名
# 流程:  挂载 -> 定位备份 -> 调 restore.sh -> 自动卸载
# ============================================================================
set -uo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-$HOME/macos-backup}"
PASS=""; DMG=""; FLAGS=()
while [ $# -gt 0 ]; do case "$1" in
  -pass|-p) shift; PASS="${1:-}" ;;
  *.dmg)    DMG="${1:-}" ;;
  *)        FLAGS+=("$1") ;;
esac; shift; done

[ -n "$DMG" ] || DMG=$(ls -1t "$BACKUP_ROOT/backups/"*encrypted.dmg 2>/dev/null | head -1)
[ -n "$DMG" ] && [ -f "$DMG" ] || { echo "找不到加密 dmg (先跑 encrypt-backup.sh 打包)" >&2; exit 1; }
echo "==> 解密: $DMG"

MNTPT=$(mktemp -d /tmp/macbackup-mnt.XXXXXX)
cleanup(){ hdiutil detach "$MNTPT" >/dev/null 2>&1; rmdir "$MNTPT" 2>/dev/null; }
trap cleanup EXIT

if [ -n "$PASS" ]; then
  printf '%s' "$PASS" | hdiutil attach -readonly -stdinpass -nobrowse -mountpoint "$MNTPT" "$DMG" >/dev/null \
    || { echo "密码错误或挂载失败" >&2; exit 1; }
else
  hdiutil attach -readonly -nobrowse -mountpoint "$MNTPT" "$DMG" >/dev/null \
    || { echo "挂载失败" >&2; exit 1; }
fi
echo "==> 已挂载 $MNTPT"

BDIR=$(find "$MNTPT" -maxdepth 2 -type d -name config -exec dirname {} \; 2>/dev/null | head -1)
[ -n "$BDIR" ] || { echo "dmg 内未找到备份(config/)" >&2; exit 1; }
echo "==> 定位备份: $(basename "$BDIR")"

bash "$BACKUP_ROOT/restore.sh" "$BDIR" "${FLAGS[@]}"
if [[ " ${FLAGS[*]:-} " == *"--dry-run"* ]]; then
  echo
  echo "==> 真实恢复: 去掉 --dry-run 重跑本脚本即可"
  echo "    bash $0 --no-overwrite   # 不覆盖已存在的本地文件"
  echo "    bash $0                  # 完全覆盖回拷(用于全新系统)"
fi