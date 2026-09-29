#!/bin/bash
# ============================================================================
# macOS 重装后配置恢复脚本
# 用法:  bash ~/macos-backup/restore.sh [备份时间戳] [选项]
#   备份时间戳 省略时自动取 latest (backups/ 下最新的一个; 支持直接传路径)
#   --dry-run       只预览会做什么,不写入/不执行任何东西
#   --no-overwrite  目标已存在的文件/目录一律跳过,不覆盖(默认是覆盖)
#   --skip-brew     跳过 Homebrew 重装 + brew bundle
#   --fix-user 旧名 把备份里硬编码的 /Users/旧名/... 替换为当前用户(重命名过才需要)
#
# 前置条件: 新系统已装好 Xcode 命令行工具 (xcode-select --install),
#           且当前用户名与备份时一致(不一致用 --fix-user)。
# ============================================================================
set -uo pipefail
cd "$HOME" || exit 1

BACKUP_ROOT="${BACKUP_ROOT:-$HOME/macos-backup}"
SKIP_BREW=0; DRY=0; NO_OVERWRITE=0; FIX_USER=""; TS=""
while [ $# -gt 0 ]; do case "$1" in
  --skip-brew)      SKIP_BREW=1 ;;
  --dry-run)        DRY=1 ;;
  --no-overwrite)   NO_OVERWRITE=1 ;;
  --fix-user)       shift; FIX_USER="${1:-}" ;;
  --*)              echo "未知参数: $1" >&2 ;;
  *)                [ -z "$TS" ] && TS="$1" || echo "多余参数: $1" >&2 ;;
esac; shift; done
[ "$DRY" = 1 ] && echo "==> [DRY-RUN] 仅预览,不写入任何文件、不执行任何安装"
[ "$DRY" = 0 ] && { [ -d "$HOME/.local/bin" ] || mkdir -p "$HOME/.local/bin"; }

# ---- 定位备份目录 ----
# 顺序: 用户传参 > backups/ 下最新 > Finder 挂载的 dmg(/Volumes 里的 config/ 父目录)
if [ -z "$TS" ]; then
  TS=$(ls -1t "$BACKUP_ROOT/backups" 2>/dev/null | grep -vE '\.tar' | head -1)
  if [ -n "$TS" ]; then
    B="$BACKUP_ROOT/backups/$TS"
  else
    # 兜底: Finder 挂载的加密 dmg -> 找 config/ 与 manifest/ 同级的目录
    for d in $(find /Volumes -maxdepth 2 -type d -name config 2>/dev/null); do
      if [ -d "$(dirname "$d")/manifest" ]; then B=$(dirname "$d"); break; fi
    done
    [ -n "$B" ] || { echo "未找到备份: 传参 restore.sh <时间戳>, 或先双击挂载加密 dmg" >&2; exit 1; }
    echo "==> 自动识别到已挂载的备份: $B"
  fi
else
  ! [[ "$TS" =~ ^/ ]] && B="$BACKUP_ROOT/backups/$TS" || B="$TS"
fi
[ -d "$B/config" ] || { echo "无效备份目录: $B" >&2; exit 1; }
MAN="$B/manifest"; CFG="$B/config"
echo "==> 从 $B"

# ---- 用户名修正 ----
CUR_USER=$(whoami)
if [ -n "$FIX_USER" ] && [ "$FIX_USER" != "$CUR_USER" ]; then
  echo "==> 旧路径 /Users/$FIX_USER → /Users/$CUR_USER"
  if [ "$DRY" = 1 ]; then
    echo "     (dry-run: 会批量替换上述路径后再复制)"
  else
    grep -rl "$FIX_USER" "$CFG" 2>/dev/null | while read -r f; do
      case "$f" in
        *.plist|*.png|*.jpg|*.icns|*.woff*|*.ttf|*.otf|*.pyc) continue ;;
      esac
      sed -i '' "s|/Users/$FIX_USER|/Users/$CUR_USER|g" "$f"
    done
  fi
fi

# ---- 1. 恢复点文件与配置 (backup 的 config/ 就是 $HOME 的镜像) ----
echo "==> 1. 配置"
# 用 find 遍历而不是 "$CFG"/*,否则点文件(.zshrc/.ssh 等)不会被 glob 匹配
while IFS= read -r item; do
  name=$(basename "$item")
  [ "$name" = ".DS_Store" ] && continue
  case "$name" in
    AppSupport) dst="$HOME/Library/Application Support" ;;
    Prefs)      dst="$HOME/Library/Preferences" ;;
    *)          dst="$HOME/$name" ;;
  esac
  if [ "$DRY" = 1 ]; then
    echo "   计划复制: $name → $dst"
    continue
  fi
  if [ "$NO_OVERWRITE" = 1 ] && [ -e "$dst" ]; then
    echo "   跳过(本地已存在,不覆盖): $name"
    continue
  fi
  ditto "$item" "$dst" && echo "   ✓ $name"
done < <(find "$CFG" -mindepth 1 -maxdepth 1 | sort)

# ---- 2. SSH 权限修正 ----
if [ "$DRY" = 1 ]; then
  [ -d "$HOME/.ssh" ] && echo "==> 2. 计划: 修正 .ssh 权限 (目录700 / 私钥600)"
elif [ -d "$HOME/.ssh" ]; then
  chmod 700 "$HOME/.ssh"
  find "$HOME/.ssh" -type f \( -name 'id_*' -o -name '*.pem' \) -exec chmod 600 {} \;
  [ -f "$HOME/.ssh/config" ] && chmod 600 "$HOME/.ssh/config"
  chmod 644 "$HOME/.ssh/known_hosts" 2>/dev/null || true
  echo "==> 2. .ssh 权限已修正"
fi

# ---- 3. Homebrew: 装本体 → 设镜像源 → brew bundle, 全程不走官方源 ----
# 镜像源与 ~/.zshrc、本机 brew 磁盘 origin 一致 —— 当前生效的是 USTC(中科大)。
# 换镜像(如清华 TUNA)只改下面 5 行 URL 即可。
# 说明: install.sh 脚本本体只能从 raw.githubusercontent.com 取(镜像站不存),
#       但 brew 本体的 git 克隆和之后一切瓶子(bottles)下载都走 USTC, 不碰官方 github/ghcr。
#       USTC 官方已停供 homebrew-core / homebrew-cask 的 git 镜像(裸路径 404,
#       非拼写错误, help/brew.git.html 只收录 brew.git + bottles/api 三域)。
#       现代 brew 走 JSON API 本不 clone tap, 下面两行仅作兜底 → 指向可用的清华。
export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"
export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
export HOMEBREW_CASK_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-cask.git"
export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
if [ "$DRY" = 1 ]; then
  echo "==> 3. 计划: ①装 Homebrew 本体(若缺) ②套用镜像源(当前: USTC) ③brew bundle 恢复全部软件"
elif [ "$SKIP_BREW" = 1 ]; then
  echo "==> 3. 已跳过 Homebrew(--skip-brew)"
else
  # ① 装 Homebrew 本体(没有才装; install.sh 尊重上面的 HOMEBREW_*_GIT_REMOTE, 克隆走 USTC 镜像)
  command -v brew >/dev/null 2>&1 || { [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"; }
  if ! command -v brew >/dev/null 2>&1; then
    echo "==> 3. 未检测到 Homebrew, 需装本体才能恢复全部工具。"
    read -r -p "    是否现在安装?(需要网络 + sudo, 输入 y): " yn
    if [ "$yn" = y ]; then
      echo "    安装 Homebrew / Xcode CLT ..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
    else
      echo "    跳过安装。之后装好 brew, 手动执行: brew bundle --file '$MAN/Brewfile'"
    fi
  fi
  # ② 套用镜像源: 若 tap 以 git 克隆形式存在, 把 origin 切到镜像(现代 brew 走 API, 通常为空操作)
  if command -v brew >/dev/null 2>&1; then
    HB="$(brew --prefix)"
    git -C "$HB/Library/Taps/homebrew/homebrew-core" remote set-url origin "$HOMEBREW_CORE_GIT_REMOTE" 2>/dev/null || true
    git -C "$HB/Library/Taps/homebrew/homebrew-cask" remote set-url origin "$HOMEBREW_CASK_GIT_REMOTE" 2>/dev/null || true
  fi
  # ③ brew bundle 恢复(瓶子走 HOMEBREW_BOTTLE_DOMAIN=USTC, 不再连官方源)
  if command -v brew >/dev/null 2>&1; then
    echo "==> 3. brew bundle 恢复安装"
    brew bundle --file "$MAN/Brewfile" --verbose 2>&1 | tail -5 || echo "!! brew bundle 有失败项, 重跑: brew bundle --file '$MAN/Brewfile'"
  fi
fi

# ---- 4. npm / cargo 全局包 ----
if [ "$DRY" = 1 ]; then
  command -v node >/dev/null && [ -f "$MAN/npm-globals.sh" ] \
    && echo "==> 4. 计划: 执行 manifest/npm-globals.sh 恢复 npm 全局包"
  [ -f "$MAN/cargo-install.txt" ] && echo "==> 5. 计划: 恢复 cargo 包 (manifest/cargo-install.sh)"
else
  command -v node >/dev/null && [ -f "$MAN/npm-globals.sh" ] && {
    echo "==> 4. 恢复 npm 全局包"
    bash "$MAN/npm-globals.sh" 2>&1 | tail -3
    echo "     (manifest/npm-globals.sh)"
  }
  [ -f "$MAN/cargo-install.txt" ] && {
    awk '/^[A-Za-z0-9_.-]+:$/{gsub(/:/,"");print "cargo install "$0}' "$MAN/cargo-install.txt" > "$MAN/cargo-install.sh"
    if command -v rustup >/dev/null; then
      echo "==> 5. 恢复 cargo 包 (manifest/cargo-install.sh)"
      bash "$MAN/cargo-install.sh" 2>&1 | tail -3
    else
      echo "==> 5. 未检测到 rustup。先装 Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
      echo "      然后执行: bash '$MAN/cargo-install.sh'"
    fi
  }
fi

# ---- 6. defaults 导入 ----
if [ "$DRY" = 1 ]; then
  ls "$MAN"/defaults-*.plist >/dev/null 2>&1 && echo "==> 6. 计划: defaults import 恢复偏好(plist)"
else
  if ls "$MAN"/defaults-*.plist >/dev/null 2>&1; then
    for p in "$MAN"/defaults-*.plist; do
      dom=$(basename "$p" | sed 's/^defaults-//; s/\.plist$//')
      defaults import "$dom" "$p" 2>/dev/null && echo "==> 恢复偏好: $dom" || echo "    × $dom"
    done
  fi
fi

# ---- 汇总 ----
[ -f "$MAN/versions.txt" ] && echo
if [ "$DRY" = 1 ]; then
  echo "==== DRY-RUN 预览完成 ===="
  echo "  未写入任何文件,可放心重跑真实恢复:"
  echo "  bash $0 $TS --no-overwrite   # 不覆盖现有文件"
  echo "  bash $0 $TS                  # 完全覆盖回拷(用于全新系统)"
else
  echo "==== 恢复完成 ===="
  echo "  备份版本基线: 请对照 $MAN/versions.txt"
  echo "  未做/需手动:"
  echo "    - brew 有失败项时重跑 brew bundle"
  echo "    - AI 工具个别 token 过期则重新登录(claude/codex/gh auth login)"
  echo "    - Rust: 装 rustup 后执行 manifest/cargo-install.sh"
  echo "    - macOS 偏好未备份的部分见 README(触控板/输入法/壁纸等)"
  echo "    - 重启终端使 shell/starship/eza/fastfetch 生效"
fi