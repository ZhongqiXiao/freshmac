# macOS 配置备份与恢复

本公开仓库保存 Ghostty、Otty、Starship 和 zsh 的可分享配置，以及本地备份/恢复脚本。公开的 `dotfiles/` 是经过筛选的版本，不包含本机凭据、工作环境配置或终端历史。

`backup.sh` 另会在本机生成完整备份，可能包含 SSH 私钥、登录凭据和其他私人配置。`backups/` 已加入 `.gitignore`；加密后再复制到网盘或移动硬盘，也不要把它提交到公开仓库。

## 公开 dotfiles

| 文件 | 恢复到 |
|---|---|
| `dotfiles/.zshrc` | `~/.zshrc` |
| `dotfiles/.config/starship.toml` | `~/.config/starship.toml` |
| `dotfiles/.config/ghostty/config` | `~/.config/ghostty/config` |
| `dotfiles/.config/otty/config.toml` | `~/.config/otty/config.toml` |
| `dotfiles/.config/otty/themes/` | `~/.config/otty/themes/`（当前使用的 One Dark 和 Nord 主题）|
| `dotfiles/.config/git/ignore` | `~/.config/git/ignore` |
| `dotfiles/.config/zed/settings.json` | `~/.config/zed/settings.json`（仅公开筛选过的编辑器、模型和主题偏好）|
| `dotfiles/Library/Application Support/Code/User/settings.json` | VS Code 用户设置（已剔除本机项目标识和自动批准命令）|

`.zshrc` 保留通用 shell 配置。工作集群别名、公司目录、本机工具路径和凭据不进入公开版本；本机专属设置可放在 `~/.zshrc.local`，公开 `.zshrc` 会在该文件存在时加载它。

## 换机恢复公开配置

先安装需要的应用和命令行工具（zsh、Oh My Zsh 及对应插件、Starship、Ghostty、Otty、Zed、VS Code、bat、eza、zoxide 等），然后：

```bash
git clone https://github.com/ZhongqiXiao/freshmac.git ~/macos-backup
cd ~/macos-backup
bash restore-dotfiles.sh --dry-run
bash restore-dotfiles.sh
```

默认跳过已存在的目标文件。确认需要覆盖时使用 `bash restore-dotfiles.sh --force`。恢复后重启终端，或执行 `source ~/.zshrc`。

## 本机完整备份

这部分用于本机或加密介质上的私人备份，不用于公开仓库：

```bash
bash backup.sh
bash restore.sh --dry-run
bash restore.sh <备份时间戳> --dry-run
bash encrypt-backup.sh <备份时间戳>
bash decrypt-restore.sh --dry-run
```

`backup.sh` 会把多种本机配置收进 `backups/<时间戳>/`，包括完整 Neovim、VS Code、Zed、Git、npm 和 Maven 设置；其中可能含有密钥、token、密码和账户状态。先用 `--dry-run` 检查恢复计划；离开本机前用 `encrypt-backup.sh` 加密，并妥善保存密码。不要把完整备份目录、加密密码或解密后的文件提交到 Git。

## 安全维护

- 只把经过人工检查的可公开配置放入 `dotfiles/`；不要把整个 `$HOME`、`~/.ssh`、工具登录目录或 `Library/Application Support` 复制到这里。
- 私人配置放在 `~/.zshrc.local` 等本机文件中。`.gitignore` 也排除了常见凭据文件与本机备份。
- 提交前检查 `git status --short` 和 `git diff --cached`，确认变更里没有 token、密码、私钥、历史记录或不应公开的主机/目录信息。

## 脚本

| 文件 | 用途 |
|---|---|
| `backup.sh` | 生成本机完整备份及软件清单 |
| `restore.sh` | 从本机完整备份恢复配置和软件 |
| `encrypt-backup.sh` | 将本机备份加密成 DMG |
| `decrypt-restore.sh` | 挂载加密 DMG 并调用恢复脚本 |
| `restore-dotfiles.sh` | 只恢复仓库中筛选过的公开 dotfiles |
