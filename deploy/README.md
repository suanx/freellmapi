# 部署说明（已精简付费引导版）

本目录包含 VPS 部署所需的配置。相对于上游 `tashfeenahmed/freellmapi`，本 fork 做了如下改动。

## 一、已移除的付费引导与外链

| 位置 | 原内容 | 处理 |
|---|---|---|
| `client/src/App.tsx` | 导航栏 `/premium` 入口 | 删除 |
| `client/src/App.tsx` | 账号菜单里的「Upgrade」项（`showUpgrade` / `onUpgrade`） | 删除（含 props 与类型定义） |
| `client/src/App.tsx` | `<Route path="/premium">` 路由 | 删除 |
| `client/src/pages/PremiumPage.tsx` | 整页付费介绍 + 授权码输入框 + 外链门户按钮 | **文件删除** |
| `client/src/components/command-palette.tsx` | 命令面板 `p-premium` 条目 | 删除 |
| 59 个语言包 | 模型徽章 `Premium · free from {date}` | 改为 `Free from {date}`（中：`{date} 起免费`） |
| `docker-compose.yml` | `PREMIUM_SITE_URL` 默认值 `https://freellmapi.co` | 置空，不再产生任何外链 |

**保留了什么**（不是广告，是功能）：

- `server/src/routes/premium.ts` 后端接口 —— 客户端「检查更新」仍走 `/api/premium/sync` 拉取模型目录，删了会导致目录无法刷新
- `client/src/hooks/use-premium.ts` —— 已无引用，保留仅为避免破坏潜在依赖
- 各厂商「去这里申请 Key」的链接 —— 这是你需要的功能入口，不是推广

**未发现的广告**：全仓扫描确认，源码内**没有** telemetry 上报、赞助链接、ko-fi / Patreon、GitHub Star 求赞等常见引流内容。作者做得挺干净，唯一的变现入口就是这个 Premium 页面。

## 二、部署优化

| 项 | 说明 |
|---|---|
| **移除 watchtower** | 官方 compose 里它挂载 `/var/run/docker.sock`，等同把宿主机 root 交出去。已整个删除 |
| **只监听 127.0.0.1** | 容器不对公网暴露，全部由 Nginx 转发 |
| **`no-new-privileges` + `cap_drop: ALL`** | 容器提权防护 |
| **日志轮转** | `max-size: 10m` × 3 份，防止日志写满 VPS 磁盘 |
| **内存/进程上限** | `mem_limit: 1g`、`pids_limit: 256`，避免拖垮宿主机 |
| **`proxy_buffering off`** | SSE 流式必需，否则响应会被攒着一起吐，流式变假流式 |
| **超时放宽到 300s** | 推理可能较慢，默认 60s 会中途断开 |

Dockerfile 本身已是多阶段构建 + `npm prune --omit=dev`，无需改动。

## 三、快速部署（Ubuntu / Debian）

前置：域名已解析到本机公网 IP，防火墙放行 80 / 443。

```bash
git clone https://github.com/<你的用户名>/freellmapi.git
cd freellmapi
chmod +x deploy/setup.sh
./deploy/setup.sh
```

脚本会依次完成：装 Docker → 生成 `ENCRYPTION_KEY` → 起容器（仅本机端口）→ 装 Nginx → certbot 签证书 → 输出访问地址。

## 四、手动部署

```bash
# .env（ENCRYPTION_KEY 务必备份，丢了就解不开已存的厂商 Key）
ENCRYPTION_KEY="$(openssl rand -hex 32)"
printf 'ENCRYPTION_KEY=%s\nPORT=3001\n' "$ENCRYPTION_KEY" > .env

docker compose up -d
curl -fsS http://127.0.0.1:3001/api/ping   # 应返回 200
```

然后手动放置 Nginx 配置：

```bash
cp deploy/nginx.conf /etc/nginx/sites-available/freellmapi
sed -i 's/your-domain.com/你的域名/g' /etc/nginx/sites-available/freellmapi
ln -sf /etc/nginx/sites-available/freellmapi /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
certbot --nginx -d 你的域名
```

## 五、构建镜像

仓库自带 `.github/workflows/docker.yml`，推送到 `main` 或打 `v*.*.*` tag 会自动构建 **amd64 + arm64 双架构**镜像并推送到 GHCR（`ghcr.io/<你的用户名>/freellmapi`）。

用的是各架构原生 runner（不是 QEMU 模拟），约 3 分钟完成。首次推送后记得把包的可见性改成 Public：

> GitHub 仓库页面 → 右侧 Packages → freellmapi → Package settings → Change visibility → Public

否则 VPS 上 `docker pull` 会因为没权限失败。

## 六、客户端接入

面板 Keys 页填好各家免费 Key 后，复制页面顶部的统一 Key（`freellmapi-xxx`）：

```
base_url = https://你的域名/v1
api_key  = freellmapi-xxx
model    = auto
```

响应头 `X-Routed-Via` 会告诉你这条请求实际由哪家服务。

## 七、注意事项

- **单用户设计**，官方明确说明不支持多租户。公网暴露务必在 Nginx 里开 IP 白名单或 Basic Auth
- **免费档模型目录是月度快照**，新模型约 30 天后才出现在免费版（付费订阅可当天拿到）。目录从 `api.freellmapi.co` 拉取
- **越晚越慢**：最好的免费模型白天会被额度耗光，UTC 零点重置
- 想屏蔽目录拉取做成纯离线，可在防火墙阻断 `api.freellmapi.co`，已同步的模型仍可用
