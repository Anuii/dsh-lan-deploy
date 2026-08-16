#!/bin/sh
# DeepSeek Harness 容器入口
# - 首次启动自动写入局域网监听 patch（0.0.0.0，DSH 自动信任所有网卡 IP）
# - 支持 DSH_TRUSTED_HOSTS 环境变量：空格分隔的域名列表，自动转为 --trusted-host
set -e

mkdir -p "$DSH_HOME"

if [ ! -f "$DSH_HOME/cordis.patch.yml" ]; then
  cat > "$DSH_HOME/cordis.patch.yml" <<'EOF'
# DeepSeek Harness 局域网访问：监听所有网卡
- id: webserver
  config:
    host: 0.0.0.0
    port: 3080
EOF
fi

set -- dsh web
if [ -n "$DSH_TRUSTED_HOSTS" ]; then
  for host in $DSH_TRUSTED_HOSTS; do
    set -- "$@" --trusted-host "$host"
  done
fi

exec "$@"
