# dsh-lan-deploy：DeepSeek Harness 局域网一键部署
# 基础镜像：Node 22 LTS
FROM node:22-bookworm-slim

# npm 源：默认官方 registry。
# 国内网络拉包超时/失败时，在 compose 里把 NPM_REGISTRY 改为：
#   https://registry.npmmirror.com
ARG NPM_REGISTRY=https://registry.npmjs.org

# node-pty 等原生模块在 Linux 上无预编译产物，需 node-gyp 现场编译；
# bubblewrap：DSH bash 沙箱后端（常见 Linux 内核未启用 landlock，只能走 bwrap）
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 make g++ bubblewrap \
    && rm -rf /var/lib/apt/lists/*

# 锁定版本：0.1.0-rc.6 与本地实测验证版本一致（信任栅栏/patch 行为均已验证）。
# 升版本前先读 changelog，确认 --host 限制与 patch 结构未变。
RUN npm config set registry $NPM_REGISTRY \
    && npm config set fetch-retries 5 \
    && npm config set fetch-retry-mintimeout 20000 \
    && npm config set fetch-retry-maxtimeout 120000 \
    && npm install -g @deepseek-ai/dsh@0.1.0-rc.6 \
    && mkdir -p /workspace

COPY entrypoint.sh /usr/local/bin/dsh-entrypoint
RUN chmod +x /usr/local/bin/dsh-entrypoint

# HOME 指向 /workspace：网页目录选择器默认定位 homedir()，否则会显示 /root
ENV HOME=/workspace
ENV DSH_HOME=/data

VOLUME /data /workspace
WORKDIR /workspace
EXPOSE 3080

ENTRYPOINT ["/usr/local/bin/dsh-entrypoint"]
CMD ["dsh", "web"]
