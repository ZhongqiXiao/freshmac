# 重装电脑前，给配置留一份备份

这台电脑装了不少软件：Codex、Claude Code、Starship、fastfetch、eza、zsh……它们的设定（终端提示符、命令行别名、登录状态、SSH 密钥）都藏在各个配置文件里。重装系统会把它们全部清空。

这套东西就干两件事：

1. **备份**：把配置文件收进一个文件夹，顺带记一份"装过哪些软件"的清单。
2. **恢复**：重装完之后，把配置文件放回原位，再照清单把软件重新装一遍。

所有文件都在 `~/macos-backup/` 这个文件夹里。

## 一、先认识这些文件

### 1. 这套东西一共 5 个文件

| 文件 | 作用 |
|---|---|
| `backup.sh` | 备份：把配置复制出来 + 生成软件清单 |
| `restore.sh` | 恢复：放回配置 + 按清单装回软件 |
| `encrypt-backup.sh` | 给备份上锁，打成加密 dmg（可选，推荐） |
| `decrypt-restore.sh` | 解锁加密 dmg 并调用 restore.sh（可选） |
| `README.md` | 就是本说明 |

### 2. 每次备份会生成什么

每次运行 `backup.sh`，都会在 `backups/` 下新建一个按时间命名的文件夹（比如 `backups/20260929-225641`）。里面有两样东西，各管各的。

**`config/` —— 配置的复印件**

它的目录结构和你的用户目录一样（也都从 `.zshrc`、`.ssh` 这种点开头的东西开始），备份的是：

| 类别 | 备份了哪些 | 放在哪 |
|---|---|---|
| 终端设置 | `.zshrc`/`.zshenv`/`.zprofile`/`.zsh_history`、`.p10k.zsh`、整个 `.oh-my-zsh`（含自定义插件/主题）、补全 `.zsh/completions`、`.zsh_sessions` | `config/` |
| Git 与 SSH | `.gitconfig`、`.git-templates/`、整个 `.ssh/`（含私钥和 config） | `config/` |
| 终端软件 | Starship `~/.config/starship.toml`、Ghostty、iTerm2（配置 + 偏好 plist）、Zed、VS Code（设置/快捷键/代码片段/mcp.json）、lazygit | `config/` + `AppSupport/` |
| 编辑器 | Neovim `~/.config/nvim/`、Vim `~/.vim`、`.viminfo` | `config/` |
| 键盘布局 | Karabiner-Elements `~/.config/karabiner/`（含自动备份） | `config/` |
| AI 工具登录 | Claude Code（`~/.claude/` 配置 + 主凭证 `~/.claude.json`）、Codex（`~/.codex/` 的 config\*.toml、auth\*.json、memories/rules/skills）、`~/.config/gh/hosts.yml`、`.cc-switch`/`.aliyun`/`.codeium`/`.continue`/`.kube`(K8s 集群凭据) | `config/` |
| 开发环境 | `.npmrc`（npm 镜像源）、Maven `~/.m2/settings.xml`（含阿里云镜像）、`~/.mcp.json`（MCP 服务器设置） | `config/` |
| 自己的脚本 | `~/scripts/`、`~/.local/bin` 下的 `ssh-menu`/`skillhub`/`thermal-guard`/`solomd` | `config/` |
| 其它小配置 | `~/.config` 下的一批程序目录（fish、goose、opencode、gemini、crush、otty、snapzy、github-copilot、superpowers 的日志/配置等）整目录备份 | `config/` |

**`manifest/` —— 软件"购物清单"**

这里放一份份清单，不是配置。恢复时照着把软件装回来：

| 清单 | 有什么 | 怎么用 |
|---|---|---|
| `Brewfile` | 所有 Homebrew 软件（本次 83 项显式配方：命令行工具 + 图形应用 + tap，依赖自动补齐到原来约 234 个包） | `restore.sh` 里 `brew bundle` 一键装回 |
| `npm-globals.sh` | 之前全局装过的 29 个 node 包（带版本号） | 可直接执行 |
| `cargo-install.txt` | cargo 装过的工具 | 装好 rustup 后执行 |
| `versions.txt` | 各工具当时的版本号 | 恢复后对比用 |
| `manifest.txt` | 这次备份了哪些文件，逐条列出 | 检查用 |

> 有些东西**故意不备份**，要么太大、要么一条命令就能重新装：
> - AI 工具的历史会话：`.codex/sessions`、`.claude/projects`、superpowers 归档（要用加参数，见下）
> - `~/.bun`（536M）、`.cargo`/`.rustup` 的二进制文件
> - Raycast 完整配置默认不含（约 700M，官方有更靠谱的导出，见下文）
> - eza、fastfetch 没有配置文件：软件靠 Brewfile 装回，命令别名在 `.zshrc` 里自动回来

### AI 工具：除了登录，还备份了这些

登录凭证只是很小一块，Claude Code 和 Codex 的**记忆、规则、技能、MCP 服务器设置**也都跟着走：

- **Claude Code**：规则/记忆（`CLAUDE.md`、`RTK.md`）、`skills/`（自装技能）、`hooks/`（自动化脚本）、`settings.json`（模型档位/环境变量/插件/statusLine）。**MCP**：`~/.mcp.json` 与 `.claude/mcp.json` 记录 `mysql`/`postgres`/`vibearound` 三个服务器，`env` 里是数据库账号密码 —— 备份里最敏感的部分之一。会话历史 `projects/` **默认不含**，要 `--claude-data`。
- **Codex**：供应商路由（`config.toml` + 5 个 `config-*.toml`，各家的 model_provider/模型）、`memories/`、`rules/`、`prompts/`、`skills/`、`automations/`，MCP 写在本机 `config.toml` 的 `[mcp_servers]`。会话历史 `sessions/` **默认不含**，要 `--codex-data`。
- **其他工具**：`.cc-switch`（服务商切换）、`.gemini`（含自己的 mcp.json）、`.codeium`、`.continue`、`.config/opencode`、`.config/goose`、`.kube`（K8s 凭据）整目录带走。

**Raycast 怎么备份 / 迁移（单独说）**

官方导出最可靠（推荐，别手动抄数据库）：
1. 打开 Raycast，在命令面板搜 **Export**，选 **Export Data & Configuration**（中文"导出数据和配置"）
2. 选个保存位置，生成一个 `rayconfig` 文件
3. 新机器上搜 **Import Data & Configuration** 选它即可

找不到入口时：新版可能收进了 Settings，先搜"Export"定位；开了 Raycast Pro 的话，Settings 登录账户可开**云同步**，比手动导出一劳永逸。想顺手让"这套备份"一起带走，就加 `--raycast` 参数（把 `~/.config/raycast` 和 `Library/Application Support/com.raycast.macos` 都收进 config/，恢复时原样放回）。

## 二、怎么用（按顺序）

### 第 1 步：备份

```bash
bash ~/macos-backup/backup.sh
```

默认把上面所有配置和清单都备份，约 0.6G。想连历史会话一起打包，就加开关：

| 参数 | 备份什么 | 体积 |
|---|---|---|
| `--codex-data` | Codex 全部会话 + 插件 | ~2.7G |
| `--claude-data` | Claude 全部会话（`projects/`）+ 插件 | ~2.6G |
| `--superpowers` | superpowers 对话归档 + 索引 | ~4.3G |
| `--all` | `~` 下其余所有小于 100MB 的隐藏文件和目录，兜底 | 不定 |
| `--defaults` | iTerm2 / Raycast / Surge 的 macOS 偏好（plist） | 很小 |
| `--raycast` | Raycast 配置与数据整目录带走（见下文说明） | ~700M |
| `--archive` | 备份完顺手打一个 tar.gz | 压缩后 |

全都要就一把开满：

```bash
bash ~/macos-backup/backup.sh --all --codex-data --claude-data --superpowers --defaults --archive
```

### 第 2 步（推荐）：加密打包

备份里有 SSH 私钥和 AI 工具的登录凭证，等于一捆钥匙。要带到 U 盘或网盘上，最好上把锁：

```bash
bash ~/macos-backup/encrypt-backup.sh
```

运行后弹出密码输入框，输入一个自己记得住的密码，生成 `backups/<时间戳>-encrypted.dmg`（AES-256 加密）。**密码一定要自己收好**（macOS 钥匙串或密码管理器），丢了这包就再也打不开。

生成加密包之后，同目录的明文 `tar.gz` 和明文备份文件夹记得清理（移废纸篓并倒掉），别让"上了锁的包"旁边还躺着一份明文。

> `hdiutil` 在新系统会打印 "deprecated" 警告，不影响使用，忽略即可。

### 第 3 步：恢复到新电脑

前提：

1. 新系统先装 **Xcode 命令行工具**：`xcode-select --install`（Homebrew 安装脚本也会顺带装）。
2. 用户名保持和原来一致（这台机器是 `%USERNAME%`）。改名了就用 `--fix-user` 一次性替换路径。

把 `backups/` 整个文件夹拷到新机器的 `~/macos-backup/` 下，然后：

```bash
bash ~/macos-backup/restore.sh
```

**恢复脚本替你做的事，按这个顺序：**

| 顺序 | 干什么 | 为什么排这里 |
|---|---|---|
| 1 | 把 `config/` 里的配置一个个放回 `~` | 纯复制，不依赖软件是否已装 |
| 2 | 修正 `~/.ssh` 权限（目录 700、私钥 600） | 不然私钥可能不被系统接受 |
| 3 | 装 **Homebrew**（没有才装；官方脚本自动带 Xcode 命令行工具） | 后面装软件全靠它 |
| 4 | `brew bundle --file manifest/Brewfile` **把软件全部装回**（含图形应用） | 清单自动生成，不用人肉逐个装 |
| 5 | 装回 npm 全局 29 个包、cargo 工具（cargo 需先装 rustup） | 和 brew 是两套工具链 |
| 6 | 有 `--defaults` 的偏好就导入 | 得等对应软件装好，所以放最后 |

**"先装软件，还是先恢复？"** —— 不用你自己决定，直接跑 `restore.sh`，顺序它自己排好（配置 → brew → 软件 → 偏好）。要是你特别想先装软件，也可以：先自己 `brew bundle --file manifest/Brewfile` 装齐，再 `restore.sh --skip-brew` 只回配置，结果一样。

个别软件没装上，脚本结尾会提示重跑的命令（多半是要 sudo 授权）。

**常用变体：**

```bash
bash ~/macos-backup/restore.sh --dry-run       # 只"演练"，不改任何东西
bash ~/macos-backup/restore.sh --no-overwrite  # 已存在的文件不覆盖
bash ~/macos-backup/restore.sh 20260929-225641 # 指定某一份备份
bash ~/macos-backup/restore.sh --fix-user 旧名  # 换过用户名才用（批量替换 /Users/旧名 路径）
bash ~/macos-backup/restore.sh --skip-brew     # brew 已装好、只想回配置
```

从加密 dmg 恢复，一条命令搞定（自动挂载 → 恢复 → 卸载，不用手动管）：

```bash
bash ~/macos-backup/decrypt-restore.sh --dry-run       # 先演练
bash ~/macos-backup/decrypt-restore.sh --no-overwrite  # 不覆盖已有文件
bash ~/macos-backup/decrypt-restore.sh -pass '密码'     # 非交互给出密码
```

### 第 4 步：验证

```bash
source ~/.zshrc            # 让新配置生效（starship 提示符、eza 别名）
starship --version && eza --version && fastfetch
brew list | wc -l          # 应接近原来的 234
kubectl config get-contexts   # K8s 凭据已带回
ssh -T git@github.com      # 私钥生效（不通就 gh auth login）
ll                         # eza 别名
nvim                       # 配置已恢复
gh auth status             # GitHub CLI 登录还在就直接可用
claude                     # 登录态一般在，偶发需要重新登录
```

## 三、这些装不回来，得手动

| 东西 | 怎么办 |
|---|---|
| Xcode 命令行工具 / Homebrew | 脚本自动装 |
| Rust（rustup）和 cargo 工具 | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh`，再 `bash manifest/cargo-install.sh` |
| Bun | `curl -fsSL https://bun.sh/install \| bash`（一条命令，没进备份） |
| Raycast | 用 App 内"Export Configuration…"导出 |
| Surge / Docker / 部分 VPN | 各自在 App 里导出或重建 |
| 输入法 / 触控板 / 壁纸 / Dock | 系统设置里手动（或备份时加 `--defaults`） |

## 四、常见问题

**备份有 0.6G，算大吗？** 主要花在 oh-my-zsh 完整历史和 opencode 数据上，算配置的合理开销。真正大的会话历史没进默认备份，要才加参数。

**`.zcompdump`、`.claude.json.backup` 这些也要吗？** 不要。zsh 补全索引会自动重建，脚本也没收录它们。

**想留多份备份？** 每次运行各成一个时间戳文件夹，互相不覆盖；清理直接删旧文件夹即可。

**`--all` 会把回收站也备进去吗？** 不会，常见缓存大目录已排除，`.Trash` 也在排除名单里。