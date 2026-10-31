#!/bin/bash
# ============================================================================
# macOS 重装前配置备份脚本
# 用法:  bash ~/macos-backup/backup.sh [--all] [--codex-data] [--claude-data]
#                      [--superpowers] [--defaults] [--archive]
#
# 默认: 备份全部"关键配置"(体积小)。大数据可选开关见文档。
#    --all         对 ~ 下所有其它 <100MB 的 dotfile/dir 做兜底全量备份
#   --codex-data   连同 Codex 会话历史 (sessions/, plugins/, ~2.7G)
#   --claude-data  连同 Claude 会话历史 (projects/, plugins/, ~2.6G)
#   --superpowers  连同 superpowers 对话归档 (archive+index, ~4.3G)
#   --raycast      连同 Raycast 配置与数据 (~/.config/raycast + AppSupport, ~700M)
#   --defaults     额外用 defaults export 备份若干系统偏好(plist)
#   --archive      完成后把备份目录打成 tar.gz
# ============================================================================
set -uo pipefail
cd "$HOME" || exit 1

START=$(date +%s)
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/macos-backup}"
TS=$(date +%Y%m%d-%H%M%S)
DST="$BACKUP_ROOT/backups/$TS"
CFG="$DST/config"          # 配置的镜像目录(目录结构同 $HOME)
MAN="$DST/manifest"        # 清单 / 可重装清单 / Brewfile
mkdir -p "$CFG" "$MAN"

SKIP_ALL=1; SKIP_CODEX=1; SKIP_CLAUDE=1; SKIP_SPW=1; SKIP_RC=1; SKIP_DEF=1; DO_ARCHIVE=0
for a in "$@"; do case "$a" in
  --all) SKIP_ALL=0 ;;  --codex-data) SKIP_CODEX=0 ;;
  --claude-data) SKIP_CLAUDE=0 ;;  --superpowers) SKIP_SPW=0 ;;
  --raycast) SKIP_RC=0 ;;  --defaults) SKIP_DEF=0 ;;  --archive) DO_ARCHIVE=1 ;;
  *) echo "未知参数: $a" >&2; exit 2 ;;
esac; done

WARN=()
log() { printf '  %s\n' "$*"; }
note() { WARN+=("$*"); }

# ---- 复制小工具: ditto 保留 macOS 元数据(xattr/ACL/资源fork) ----
# 注: .ssh/agent、iterm2 有活动 socket,ditto 会报非零但不影响,统一按产物存在与否判定
bk()   { local s="$HOME/$1" d="$2"
         [ -e "$s" ] || { log "  – $1 (跳过,不存在)"; return 0; }
         ditto "$s" "$CFG/$d" 2>/dev/null || true
         [ -e "$CFG/$d" ] && log "  ✓ $1" || note "复制失败: $1"; }
bkraw(){ [ -e "$1" ] || { log "  – $2 (不存在)"; return 0; }
         ditto "$1" "$CFG/$2" 2>/dev/null || true
         [ -e "$CFG/$2" ] && log "  ✓ $2" || note "复制失败: $2"; }
# 只复制指定子项(用于超大的目录)
bk_children() {
  local base="$HOME/$1" dst="$2"; shift 2
  [ -d "$base" ] || { log "  – $1 不存在"; return 0; }
  local ch
  for ch in "$@"; do
    [ -e "$base/$ch" ] || continue
    ditto "$base/$ch" "$CFG/$dst/$ch" 2>/dev/null || true
    [ -e "$CFG/$dst/$ch" ] && log "  ✓ $dst/$ch" || note "复制失败: $dst/$ch"
  done
}

echo "==> 备份目录: $DST"

# ---------- 1. Shell / Git / 环境点文件 ----------
echo "==> 1. 点文件"
for f in .zshrc .zshenv .zprofile .bash_profile .bashrc .profile \
         .gitconfig .npmrc .mcp.json .claude.json \
         .p10k.zsh; do bk "$f" "$f"; done
bk .git-templates .git-templates
bk .vim .vim
bk .zsh .zsh                      # ~/.zsh/completions 等
bk scripts scripts                # ~/scripts(expect 脚本等)

# ---------- 2. ~/.config 下的小配置(整目录) ----------
echo "==> 2. ~/.config 配置"
for d in starship.toml fish nvim ghostty zed karabiner git gh github-copilot \
         configstore uv openspec gemini gc otty snapzy devin; do bk ".config/$d" ".config/$d"; done
# superpowers: 只取配置与日志,归档目录很大单独走开关
bk_children ".config/superpowers" ".config/superpowers" \
            logs config.json agent-config.json system-config.json

# ---------- 3. AI 工具配置(选要项,避开 GB 级缓存) ----------
echo "==> 3. AI 工具配置"
if [ "$SKIP_CLAUDE" = 0 ]; then
  bk_children ".claude" ".claude" projects plugins file-history shell-snapshots
else
  bk_children ".claude" ".claude" settings.json settings.local.json CLAUDE.md \
              RTK.md mcp.json hooks skills IDE.json
fi
if [ "$SKIP_CODEX" = 0 ]; then
  bk_children ".codex" ".codex" sessions plugins worktrees attachments visualizations
else
  bk_children ".codex" ".codex" config.toml rules prompts skills memories automations
  for f in "$HOME"/.codex/auth*.json "$HOME"/.codex/config-*.toml; do
    [ -e "$f" ] && ditto "$f" "$CFG/.codex/$(basename "$f")"
  done
fi
for d in .aliyun .kube .ansible .bundle; do
  [ -d "$HOME/$d" ] && bk "$d" "$d"
done
[ -f "$HOME/.m2/settings.xml" ] && bk .m2/settings.xml .m2/settings.xml
# Raycast(可选, ~700M): 官方 Export 命令更彻底, 这里作为脚本式兜底
if [ "$SKIP_RC" = 0 ]; then
  [ -d "$HOME/.config/raycast" ] && { ditto "$HOME/.config/raycast" "$CFG/.config/raycast" 2>/dev/null; log "  ✓ Raycast 配置 (~/.config/raycast)"; }
  [ -d "$HOME/Library/Application Support/com.raycast.macos" ] && \
    { ditto "$HOME/Library/Application Support/com.raycast.macos" "$CFG/AppSupport/com.raycast.macos" 2>/dev/null; log "  ✓ Raycast 数据 (Library/AppSupport)"; }
fi

# ---------- 4. 密钥与 Git 凭据 ----------
echo "==> 4. SSH / Git 凭据"
bk .ssh .ssh    # 私钥必须保留 600 权限,restore 时会修正
[ -f "$HOME/.config/gh/hosts.yml" ] && bk .config/gh/hosts.yml .config/gh/hosts.yml
[ -f "$HOME/.config/gh/config.yml" ] && bk .config/gh/config.yml .config/gh/config.yml

# ---------- 5. 用户自己的小脚本(从 .local/bin) ----------
echo "==> 5. 自定义脚本"
for s in ssh-menu update-ssh-menu skillhub thermal-guard solomd; do
  shopt -s nullglob
  for f in "$HOME/.local/bin/$s"*; do bkraw "$f" ".local/bin/$(basename "$f")"; done
done

# ---------- 6. 图形应用配置 (Library/Application Support) ----------
echo "==> 6. 图形应用配置"
bkraw "$HOME/Library/Application Support/iTerm2"               "AppSupport/iTerm2"
bkraw "$HOME/Library/Preferences/com.googlecode.iterm2.plist"  "Prefs/com.googlecode.iterm2.plist"
bkraw "$HOME/Library/Application Support/lazygit"              "AppSupport/lazygit"
# Deepseek Harness Desktop: 只备份 profile 配置文件
bk_children "Library/Application Support/dsh-desktop/harness/profiles/web" "AppSupport/dsh-desktop/harness/profiles/web" \
            cordis.yml cordis.patch.yml
# VS Code: 只要用户配置,不要几百 MB 的工作区缓存
bk_children "Library/Application Support/Code/User" "AppSupport/Code-User" \
            settings.json keybindings.json snippets mcp.json chatLanguageModels.json

# ---------- 7. (可选) macOS 系统偏好 ----------
if [ "$SKIP_DEF" = 0 ]; then
  echo "==> 7. defaults export (可选)"
  for dom in com.googlecode.iterm2 com.raycast.macos com.nssurge.surge-mac; do
    if defaults export "$dom" "$MAN/defaults-$dom.plist" 2>/dev/null; then
      log "  ✓ $dom"; else log "  – $dom (无权限/未安装)"; fi
  done
fi

# ---------- 8. (可选) 兜底: ~ 下其余小 dotfile/dir --------
if [ "$SKIP_ALL" = 0 ]; then
  echo "==> 8. 兜底全量 (~ 下 <100MB 的其它隐藏项)"
  while IFS= read -r d; do
    name=$(basename "$d")
    case "$name" in
      . | .. | .Trash | .cache | .local | .config | .claude | .codex | .cargo | \
      .rustup | .bun | .npm | .oh-my-zsh | .orbstack | .docker ) continue ;;
    esac
    size=$(du -sk "$d" 2>/dev/null | cut -f1); [ -z "$size" ] && continue
    if [ -d "$d" ]; then
      if [ "$size" -le 102400 ]; then ditto "$d" "$CFG/$name" 2>/dev/null
        log "  ✓ $name ($((size/1024))MB)"; else note "跳过大目录: $name ($(((size+1023)/1024))MB)"; fi
    else
      if [ "$size" -le 20480 ]; then ditto "$d" "$CFG/$name" 2>/dev/null
        log "  ✓ $name"; fi
    fi
  done < <(find "$HOME" -maxdepth 1 -name '.*' ! -name '.DS_Store' | sort)
fi

# ---------- 9. 可重装清单(Brew/cargo/npm/版本) ----------
echo "==> 9. 生成重装清单"
if command -v brew >/dev/null; then
  brew bundle dump --force --file="$MAN/Brewfile" 2>/dev/null \
    || note "brew bundle dump 失败"
  n=$(grep -cE '^(brew|cask|tap)' "$MAN/Brewfile" 2>/dev/null || echo 0)
  [ "$n" -gt 0 ] && log "  ✓ Brewfile ($n 项配方)" || note "Brewfile 为空"
fi
if command -v npm >/dev/null && command -v jq >/dev/null; then
  npm ls -g --json 2>/dev/null | jq -r '.dependencies // {} | keys[] as $k |
        "npm install -g \($k)@\(.dependencies[$k].version)"' > "$MAN/npm-globals.sh" && chmod +x "$MAN/npm-globals.sh"
  log "  ✓ npm 全局包 -> manifest/npm-globals.sh ($(wc -l < "$MAN/npm-globals.sh" 2>/dev/null | tr -d ' ') 个)"
fi
if command -v cargo >/dev/null; then
  cargo install --list > "$MAN/cargo-install.txt" 2>/dev/null
  n=$(grep -cE '^[A-Za-z0-9_.-]+:' "$MAN/cargo-install.txt" 2>/dev/null || true)
  log "  ✓ cargo 包清单 ($((10#${n:-0})) 个)"
fi
{
  sw_vers; echo "ARCH: $(uname -m)"
  for c in brew node bun deno go rustc python3 java rg fzf eza git lazygit starship; do
    command -v "$c" >/dev/null && printf '%-8s %s\n' "$c" "$($c --version 2>/dev/null | head -1)"
  done
} > "$MAN/versions.txt" 2>/dev/null
log "  ✓ 版本基线 -> manifest/versions.txt"

# ---------- 10. 清点 ----------
{
  echo "# 备份清单 $TS"
  echo "位置: $DST"
  echo "本文件 = 完整文件清单(相对 config/ 目录):"
  echo
  find "$CFG" \( -type f -o -type l \) | sort | sed "s|$CFG/|config/|"
} > "$MAN/manifest.txt"
N=$(find "$CFG" \( -type f -o -type l \) | wc -l | tr -d ' ')
SZ=$(du -sh "$DST" 2>/dev/null | cut -f1)
EL=$(( $(date +%s) - START ))
echo
echo "==== 备份完成 ===="
echo "  位置:  $DST"
echo "  文件:  $N 项, 磁盘占用 $SZ, 耗时 ${EL}s"
echo "  校验:  cat '$MAN/manifest.txt'   查看备份内容"
echo "  恢复:  bash $BACKUP_ROOT/restore.sh '$TS'"
echo
echo "==== 提醒 ===="
echo "  1. 备份含 SSH 私钥 / AI 工具登录 token(.claude.json, .codex/auth*)"
echo "     — 拷到移动盘或网盘时请加密归档(见 README「归档与加密」)"
echo "  2. eza/fastfetch 无独立配置文件,brew 重装即恢复(已在 Brewfile)"
if [ "${#WARN[@]}" -gt 0 ]; then
  echo "  3. 已跳过:"; printf '     - %s\n' "${WARN[@]}"
fi
echo "  可选会话历史未备份,需要时加 --codex-data / --claude-data / --superpowers"
if [ "$DO_ARCHIVE" = 1 ]; then
  ( cd "$BACKUP_ROOT/backups" && tar czf "$TS.tar.gz" "$TS" )
  echo "  已归档: $BACKUP_ROOT/backups/$TS.tar.gz"
fi