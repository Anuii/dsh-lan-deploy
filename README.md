# dsh-lan-deploy

在 Linux Docker 主机上**一条命令**部署 [DeepSeek Harness](https://github.com/deepseek-ai/DeepSeek-Harness)（DeepSeek 官方开源 Agent 框架的浏览器 UI），让局域网内任意设备通过网页使用 AI 编码助手。

```bash
docker compose up -d    # 完成：构建镜像 → 生成 HTTPS 证书 → 启动 DSH → 启动反代
```

---

## 它是什么

**DeepSeek Harness（DSH）** 是 DeepSeek 官方的开源 Agent 框架：一个浏览器里的 AI 编码助手，能读写文件、执行命令、调用工具完成实际任务。

**这个项目** 是 DSH 在容器化 + 局域网部署场景下的完整方案，解决 DSH 的 5 个官方限制：

| DSH 的默认限制 | 本项目的处理 |
|---|---|
| Web UI 只监听 `127.0.0.1`，且官方明确禁止 `--host 0.0.0.0` | 配置层 patch 绑定所有网卡，局域网直接可达 |
| 前端依赖 `crypto.randomUUID`，**HTTP 下浏览器不可用**（需 HTTPS 安全上下文） | 内置 nginx HTTPS 反代（自签证书自动生成） |
| 设置/Models 等配置接口**只信任本机回环**，局域网访问被 403 | 反代强制回环身份，网页配置可用 |
| bash 工具需要沙箱后端（bwrap/landlock），**常见 Linux 内核未启用 landlock** | 镜像内置 bubblewrap + 容器能力补全 |
| 会话/配置数据易丢失 | 全部持久化到主机数据目录 |

## 测试环境

| 项目 | 版本 |
|---|---|
| 主机 | Unraid 7.3.2（x86_64，内核 6.18.38-Unraid） |
| 容器运行时 | Docker Engine + Compose v2 |
| DSH | `0.1.0-rc.6`（Dockerfile 锁定） |
| 访问端 | Chrome / Edge（局域网 HTTPS） |

> 原理上适用于任意支持 Docker Compose 的 Linux 主机；需要宿主机支持 `network_mode: host` 与容器 `cap_add`（主流 Docker 安装均支持）。

## 做了什么

- **一键编排**：单个 `docker-compose.yml` 管理三个服务
  - `dsh` —— DSH 本体（镜像自动构建，锁定已验证版本 `0.1.0-rc.6`）
  - `dsh-certgen` —— 一次性服务，自动生成 HTTPS 证书（幂等）
  - `dsh-proxy` —— nginx HTTPS 反代（含 WebSocket 事件通道转发）
- **局域网开箱即用**：绑定 `0.0.0.0` 后 DSH 自动把本机所有网卡 IP 加入 `/api` 信任名单
- **网页全功能**：设置页、Models 页（API key 配置）、流式对话（WebSocket）均可用
- **Agent 可执行命令**：bwrap 沙箱内运行 bash，支持 `git clone`/`npm install` 等（沙箱不隔离网络，工作区可写）
- **Tailscale 友好**：`.env` 填域名即可同时放行 Tailscale 访问
- **数据持久化**：配置/API key/会话存主机数据目录，工作文件存主机共享目录，容器重建不丢
- **升级可控**：版本锁定 + 无缓存重建一条命令

## 架构

```
浏览器（局域网任意设备）
    │  https://<NAS IP>:8443（自签证书）
    ▼
┌──────────────────────────────┐
│ dsh-proxy (nginx:alpine)     │  HTTPS 终结、WebSocket 升级、
│  host 网络 · 0.0.0.0:8443    │  强制回环身份（配置平面可用）
└──────────────┬───────────────┘
               │  http://127.0.0.1:3080
               ▼
┌──────────────────────────────┐
│ dsh (DSH web UI)             │  /api 信任栅栏、agent 会话
│  host 网络 · 0.0.0.0:3080    │  bwrap 沙箱执行 bash
└──────────────────────────────┘
```

## 快速开始

### 前置要求

- Linux 主机 + Docker Compose（Unraid 实测通过）
- 设备与主机在同一局域网

### 部署

```bash
# 1. 拷贝本目录到主机（Unraid 用户可放 /boot/config/plugins/compose.manager/projects/ 下）
cp -r dsh-lan-deploy /mnt/user/appdata/dsh-deploy
cd /mnt/user/appdata/dsh-deploy

# 2. 配置（可选，见下节）
cp .env.example .env
nano .env

# 3. 一键启动（首次构建约 3-5 分钟，含 node-pty 编译）
docker compose up -d
```

### 访问

浏览器打开 **`https://<主机 IP>:8443`**（自签证书警告点"继续访问"）→ 设置 → Models → 填入 DeepSeek API key → 开始对话。

### 配置（.env）

```dotenv
# DeepSeek API key（或留空，启动后在网页 设置→Models 填写）
DEEPSEEK_API_KEY=

# 额外信任的域名（空格分隔），如 Tailscale 域名；仅局域网 IP 访问可留空
DSH_TRUSTED_HOSTS=

# 国内网络构建失败时切换 npm 镜像源
NPM_REGISTRY=https://registry.npmjs.org
```

### 常用命令

```bash
docker compose up -d                  # 启动 / 应用 .env 变更
docker compose logs -f dsh            # 查看日志
docker compose build --no-cache dsh && docker compose up -d   # 升级 DSH
docker compose down                   # 停止并删除容器（数据保留）
```

### 数据位置

| 内容 | 位置（compose 中可改） |
|---|---|
| DSH 配置 / API key / 会话 | `/mnt/user/appdata/dsh`（容器内 `/data`） |
| Agent 工作目录 | compose `volumes` 中指定（容器内 `/workspace`） |
| HTTPS 证书 | `./certs/`（自动生成，删除后重启自动重建） |

## 安全说明（必读）

- DSH 的 agent 能执行 shell 命令、读写工作区文件；`/api` 信任检查**不是登录认证**——**局域网内能访问 8443/3080 的任何设备都等于获得一台可执行命令的 agent**
- 为启用 bash 沙箱，容器以 `cap_add: SYS_ADMIN` + `seccomp:unconfined` 运行（bwrap 需要），容器隔离性弱于默认配置，请勿暴露到公网
- 如需收紧：反代层加 `auth_basic` 登录认证，或用 SSH 隧道 `ssh -L 3080:127.0.0.1:3080 root@<主机 IP>` 访问
- 外网访问请使用 Tailscale 等组网方案，不要直接映射端口

## 排障速查

| 症状 | 原因与解决 |
|---|---|
| 构建失败 `gyp ERR! find Python` | node-pty 需编译，确认使用本仓库 Dockerfile 并 `build --no-cache` |
| 构建超时 | 国内网络：`.env` 设 `NPM_REGISTRY=https://registry.npmmirror.com` 后重建 |
| 页面报 `crypto.randomUUID is not a function` | 用了 `http://IP:3080` 访问，必须走 `https://IP:8443` |
| 设置页 403 `transport failure for /api/settings.describe` | 配置平面仅信任回环，反代已强制回环身份；确认 dsh-proxy 使用本仓库 nginx.conf |
| 对话无响应 | 反代缺少 WebSocket 升级头（本仓库 nginx.conf 已含 `Upgrade`/`Connection`）；修改后 `docker restart dsh-proxy` |
| Agent 提示沙箱后端不可用 | 确认 compose 含 `cap_add: SYS_ADMIN` + `security_opt: seccomp:unconfined`，镜像含 bubblewrap |
| 反代启动失败 `bind() 443 failed` | 443 常被 NAS/路由管理界面占用，本项目固定使用 8443 |

## 目录结构

```
.
├── docker-compose.yml   # 编排：dsh + dsh-proxy + dsh-certgen
├── Dockerfile           # DSH 镜像（编译链 + bubblewrap，锁定 0.1.0-rc.6）
├── entrypoint.sh        # 容器入口（局域网 patch + 信任域名参数）
├── nginx.conf           # HTTPS 反代（8443，WebSocket，强制回环）
├── .env.example         # 配置模板（复制为 .env）
└── certs/               # HTTPS 证书（自动生成，不入库）
```

## 致谢

- [DeepSeek Harness](https://github.com/deepseek-ai/DeepSeek-Harness) —— DeepSeek 官方开源 Agent 框架
