#!/usr/bin/env bash
# FreeLLMAPI — Ubuntu / Debian VPS 一键部署
#
#   chmod +x deploy/setup.sh
#   ./deploy/setup.sh
#
# 做四件事：装 Docker → 起容器 → 装 Nginx → 签 Let's Encrypt 证书
# 前置条件：一个已解析到本机公网 IP 的域名，且 80/443 端口已放行。

set -euo pipefail

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "请用 root 运行，或 sudo ./deploy/setup.sh"

# ---------- 1. 收集信息 ----------
read -rp "你的域名（如 llm.example.com）: " DOMAIN
[ -n "$DOMAIN" ] || die "域名不能为空"

read -rp "容器镜像 [ghcr.io/tashfeenahmed/freellmapi:latest]: " IMAGE
IMAGE="${IMAGE:-ghcr.io/tashfeenahmed/freellmapi:latest}"

read -rp "签证书用的邮箱: " EMAIL
[ -n "$EMAIL" ] || die "邮箱不能为空（Let's Encrypt 需要）"

INSTALL_DIR="${FREELLMAPI_DIR:-/opt/freellmapi}"

# ---------- 2. 装 Docker ----------
if ! command -v docker >/dev/null 2>&1; then
  say "安装 Docker"
  apt-get update
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/$( . /etc/os-release && echo "$ID" )/gpg \
    -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/$( . /etc/os-release && echo "$ID" ) \
$( . /etc/os-release && echo "$VERSION_CODENAME" ) stable" > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  say "Docker 已存在，跳过"
fi

# ---------- 3. 准备目录与环境变量 ----------
say "准备 ${INSTALL_DIR}"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

if [ ! -f .env ]; then
  ENCRYPTION_KEY="$(openssl rand -hex 32)"
  umask 077
  cat > .env <<EOF
ENCRYPTION_KEY=${ENCRYPTION_KEY}
PORT=3001
FREELLMAPI_IMAGE=${IMAGE}
EOF
  say "已生成 .env（ENCRYPTION_KEY 请备份，丢了就解不开已存的厂商 Key）"
else
  say "保留已有 .env"
fi

# ---------- 4. 起容器 ----------
say "拉取并启动容器"
docker compose pull    || warn "拉取失败，尝试本地构建"
docker compose up -d

say "等待健康检查"
for i in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:3001/api/ping >/dev/null 2>&1; then
    say "本机 127.0.0.1:3001 已就绪"
    break
  fi
  sleep 2
done

# ---------- 5. 装 Nginx ----------
say "安装 Nginx"
apt-get install -y nginx

cp "$INSTALL_DIR/deploy/nginx.conf" /etc/nginx/sites-available/freellmapi
sed -i "s/your-domain.com/${DOMAIN}/g" /etc/nginx/sites-available/freellmapi
ln -sf /etc/nginx/sites-available/freellmapi /etc/nginx/sites-enabled/freellmapi
rm -f /etc/nginx/sites-enabled/default

nginx -t || die "Nginx 配置有误，请检查"

# ---------- 6. 签证书 ----------
say "申请 Let's Encrypt 证书"
if ! command -v certbot >/dev/null 2>&1; then
  apt-get install -y certbot python3-certbot-nginx
fi

systemctl reload nginx
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect

systemctl enable nginx
systemctl reload nginx

# ---------- 7. 完成 ----------
say "部署完成"
cat <<EOF

  https://${DOMAIN}

  1. 打开上面的地址，注册面板账号
  2. Keys 页面填入各家免费 Key（Groq / NVIDIA / Google / Mistral / Cloudflare …）
  3. 页面顶部复制统一 Key（freellmapi-xxx）
  4. 客户端这样填：
       base_url = https://${DOMAIN}/v1
       api_key  = freellmapi-xxx
       model    = auto

  常用命令：
      cd ${INSTALL_DIR}
      docker compose logs -f      # 看日志
      docker compose pull && docker compose up -d   # 升级

  安全建议：
      FreeLLMAPI 是单用户设计，建议编辑
      /etc/nginx/sites-available/freellmapi
      打开 IP 白名单或 Basic Auth 那两行注释。
EOF
