<!-- 默认中文文档。English version: README_EN.md -->

# mofox-huggingface：NapCat + MaiBot + Sync 持久化网关

本仓库提供一个可直接用于本地 Docker 或 Hugging Face Spaces（Docker SDK）的镜像：用 `supervisord` 在单容器内编排多进程，并用 OpenResty（nginx + Lua）统一对外暴露一个端口（`7860`）。

容器内主要组件：
- OpenResty 网关：对外端口 `7860`（所有服务都通过它转发）
- Sync 同步服务：将重要数据/配置通过 GitHub 仓库持久化（并提供 `/sync/` 管理页）
- NapCat（QQ/OneBot 桥接）：通过 `/webui/`、`/api/ws/` 等路径访问
- MaiBot-Core / MaiBot-Napcat-Adapter：按你的路由规则转发到对应端口
- FileBrowser：通过 `/filebrowser/` 访问
- GoTTY（Web 终端）：通过 `/t/` 访问
- 可选：sin-proxy（临时 sing-box ws 代理，自动添加 `/ws` 路由后运行 60 秒退出）

上游项目参考：
- NapCat AppImage Build: https://github.com/NapNeko/NapCatAppImageBuild
- MaiBot: https://github.com/Mai-with-u/MaiBot
- MaiBot-Napcat-Adapter: https://github.com/Mai-with-u/MaiBot-Napcat-Adapter

---

## 端口与入口

对外只需要映射一个端口：`7860`。

常用入口（由 `nginx/default_admin_config.json` 决定，可在 `/admin/ui/` 修改）：
- `/admin/ui/`：路由管理界面（请求头 `X-Admin-Password`，默认 `admin`）
- `/webui/`：NapCat WebUI（扫码登录/配置）
- `/sync/`：同步管理页（查看同步状态/手动操作）
- `/filebrowser/`：文件管理（根目录 `/`）
- `/t/`：Web 终端（默认账号见环境变量）

## 必备：配置 GitHub 同步持久化（推荐）

这个项目默认会等待 Sync 完成首次同步后再启动 NapCat/MaiBot/FileBrowser 等服务；因此强烈建议配置 GitHub 同步，否则首次启动可能会等待较久（默认最长 30 分钟后才放行）。

1) 准备一个 GitHub 仓库（建议 Private）。
2) 创建 PAT（Personal Access Token），确保对该仓库有读写权限。
3) 运行容器/Space 时设置：
- `GITHUB_REPO`：形如 `owner/repo`
- `GITHUB_PAT`：你的 token
- 可选：`GIT_BRANCH`（默认 `main`）

Sync 默认同步目标见 `sync/core/config.py`，包括：
- NapCat 配置与 QQ 数据（`/app/napcat/config/`、`/app/.config/QQ/`、`/home/user/config/`）
- MaiBot 配置/数据/插件（`/home/user/MaiBot-Core/...`、`/home/user/MaiBot-Adapter/...`）
- 网关路由配置（`/home/user/nginx/admin_config.json`）
- FileBrowser 数据库（`/home/user/filebrowser-data/filebrowser.db`）

你可以用环境变量覆盖同步目标：
- `SYNC_TARGETS`：空格分隔的路径列表（目录以 `/` 结尾）
- `EXCLUDE_PATHS`：相对 `HIST_DIR` 的黑名单路径（空格分隔）

---

## 环境变量一览（表格）

NapCat（可选）

| 名称 | 必填 | 默认值 | 参考值 | 说明 |
| --- | --- | --- | --- | --- |
| `NAPCAT_FLAGS` | 否 | 空 | `--disable-gpu` | 传给 QQ AppImage 的额外参数。以非 root 运行，一般无需 `--no-sandbox`。 |
| `TZ` | 否 | `Asia/Shanghai` | `Asia/Shanghai` | 时区。 |

Sync（建议配置）

| 名称 | 必填 | 默认值 | 参考值 | 说明 |
| --- | --- | --- | --- | --- |
| `GITHUB_REPO` | 是 | 空 | `moyang1/my-sync-data` | 用于持久化数据的 GitHub 仓库（owner/repo）。 |
| `GITHUB_PAT` | 是 | 空 | `ghp_xxx` | GitHub Token，需要对该仓库有读写权限。 |
| `GIT_BRANCH` | 否 | `main` | `main` | 同步分支。 |
| `HIST_DIR` | 否 | `/home/user/.sync-backup` |  | 同步仓库在容器内的路径。 |
| `SYNC_INTERVAL` | 否 | `180` | `60` | 周期同步间隔（秒）。 |
| `SYNC_WAIT_TIMEOUT` | 否 | `1800` | `0` | 其他服务等待首次同步的最长时间（秒）；设为 `0` 可禁用等待。 |

GoTTY（Web 终端）

| 名称 | 必填 | 默认值 | 参考值 | 说明 |
| --- | --- | --- | --- | --- |
| `GOTTY_USERNAME` | 否 | `admin` | `admin` | `/t/` 登录用户名。 |
| `GOTTY_PASSWORD` | 否 | `adminadminadmin` | `***` | `/t/` 登录密码。 |

---

## 本地快速开始（Docker）
1）构建镜像：
```
docker build -t napcat-hf:latest .
```
2）启动容器（按需替换示例值）：
```
docker run -d \
  -p 7860:7860 \
  -e GITHUB_REPO="<owner>/<repo>" \
  -e GITHUB_PAT="<token>" \
  --name napcat napcat-hf:latest
```
3）打开 `http://localhost:7860/`：
- `/webui/` NapCat 管理界面（登录/扫码）。
- `/admin/ui/` 路由管理界面（默认密码 `admin`）。
- `/sync/` 同步管理页（查看同步进度）。

---

## Hugging Face 部署（Docker SDK）
1）创建 Space：
- SDK 选 Docker；若涉及隐私，建议 Private。
2）推送本仓库到 Space（或连接 GitHub）。
3）在 Settings → Variables and secrets 配置：
- 可选：`NAPCAT_FLAGS`（如 `--disable-gpu`）。
- 建议：`GITHUB_REPO`、`GITHUB_PAT`（用于持久化同步）。
4）硬件：CPU Basic 即可；如需常驻在线，关闭自动休眠。
5）启动 Space，等待构建完成，访问 Space URL（内部监听 7860）。
6）首次建议：
- 打开 `/admin/ui/` 修改路由管理密码。
- NapCat：在 `/webui/` 完成登录与绑定。
- Sync：在 `/sync/` 确认首次同步完成。

---

## 路由管理 API 速查
- 获取路由：
```
curl -H "X-Admin-Password: <pass>" https://<host>/admin/routes.json
```
- 替换路由：
```
curl -X POST -H "X-Admin-Password: <pass>" -H "Content-Type: application/json" \
  -d '{"default_backend":"http://127.0.0.1:6185","rules":[...]}' \
  https://<host>/admin/routes.json
```
- 修改密码：
```
curl -X POST -H "X-Admin-Password: <old>" -H "Content-Type: application/json" \
  -d '{"new_password":"<new>"}' https://<host>/admin/password
```

## 常见问题（FAQ）
- **为什么会“覆盖/替换”同步下来的 `admin_config.json`？**
  - 现象通常发生在：OpenResty 启动早于 Sync，先加载了默认路由；当你随后通过 `/admin/ui/` 保存配置（或脚本调用 `/admin/routes.json` 写回）时，会把“内存里的旧配置”持久化到 `admin_config.json`，看起来像覆盖了刚同步下来的文件。
  - 本仓库已在 `nginx/nginx.conf` 增加“检测 `admin_config.json` 变更并自动刷新”的逻辑；如果你升级到最新版镜像，Sync 拉取/切换配置后通常会在几秒内生效。
- **我已经被覆盖了怎么办？**
  - 以 GitHub 仓库版本为准：在你的同步仓库里把 `home/user/nginx/admin_config.json` 恢复到正确提交；Sync 会再次拉取并应用。
- **访问 502 或空白页**
  - 到 `/admin/ui/` 检查路由配置（`default_backend` 和规则优先级）。
- **NapCat 启动异常**
  - 已使用 `--appimage-extract-and-run` 与 Xvfb；无 GPU 环境建议 `NAPCAT_FLAGS=--disable-gpu`。

---

## 许可证
本仓库集成上游项目（各自遵循其许可协议），本仓库仅提供配置与自动化胶合代码。请查阅上游仓库了解各自许可。
