#!/bin/bash
# ============================================================================
# 把备份打包成 AES-256 加密 dmg
# 用法:  bash ~/macos-backup/encrypt-backup.sh [备份时间戳]
#   - 默认取最新备份; 交互时会弹出 macOS 密码框让你输入密码(推荐,不进命令行)
#   - 脚本化: PASSWORD='你的密码' bash encrypt-backup.sh [ts]
#        (密码会出现在进程参数,只用于自动化; 日常请用弹窗方式)
# 产物:  backups/<时间戳>-encrypted.dmg
# ============================================================================
set -uo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-$HOME/macos-backup}"
TS="${1:-}"
if [ -z "$TS" ]; then
  TS=$(ls -1t "$BACKUP_ROOT/backups" | grep -vE '\.tar|\.dmg' | head -1)
fi
SRC="$BACKUP_ROOT/backups/$TS"
[ -d "$SRC" ] || { echo "备份不存在: $SRC" >&2; exit 1; }
DMG="$BACKUP_ROOT/backups/$TS-encrypted.dmg"
[ -e "$DMG" ] && { echo "已存在 $DMG,先删除再重打" >&2; exit 1; }

echo "==> 加密打包"
echo "    源:  $SRC -> $DMG"
if [ -n "${PASSWORD:-}" ]; then
  printf '%s' "$PASSWORD" | hdiutil create -encryption AES-256 -stdinpass \
    -srcfolder "$SRC" -volname macbackup "$DMG"
else
  hdiutil create -encryption AES-256 \
    -srcfolder "$SRC" -volname macbackup "$DMG"
fi
[ -e "$DMG" ] && echo "==> 完成: $DMG" || { echo "加密失败" >&2; exit 1; }