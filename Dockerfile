FROM ubuntu:latest

# Default APT mirror - 使用 Azure 镜像（适合 GitHub Actions）
# 国内可覆盖为：http://mirrors.aliyun.com/ubuntu 或 https://mirrors.tuna.tsinghua.edu.cn/ubuntu
ARG APT_MIRROR=http://azure.archive.ubuntu.com/ubuntu
# Python deps (use venv to avoid PEP 668)
# 使用官方 PyPI（适合 GitHub Actions）
# 国内可覆盖为：https://mirrors.aliyun.com/pypi/simple/
ARG PIP_INDEX_URL=https://pypi.org/simple/

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC

# Faster APT mirrors (支持 Ubuntu 24.04 的 DEB822 格式)
RUN set -eux; \
    mirror="${APT_MIRROR%/}"; \
    # 处理传统格式 sources.list
    if [ -f /etc/apt/sources.list ]; then \
      sed -i "s|http://archive.ubuntu.com/ubuntu|${mirror}|g; s|http://security.ubuntu.com/ubuntu|${mirror}|g" /etc/apt/sources.list; \
    fi; \
    # 处理 Ubuntu 24.04+ 的 DEB822 格式
    if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then \
      sed -i "s|http://archive.ubuntu.com/ubuntu|${mirror}|g; s|http://security.ubuntu.com/ubuntu|${mirror}|g" /etc/apt/sources.list.d/ubuntu.sources; \
    fi

# Base dependencies: git/python/node/build tools + ffmpeg + supervisor + NapCat runtime libs
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg bash \
    git jq rsync \
    python3 python3-pip python3-dev python3-venv \
    build-essential libffi-dev libssl-dev \
    ffmpeg \
    supervisor nginx-full \
    xvfb libfuse2t64 \
    libglib2.0-0 libnspr4 libnss3 libatk1.0-0 libatspi2.0-0 \
    libgtk-3-0 libgdk-pixbuf-2.0-0 libpango-1.0-0 libcairo2 \
    libx11-6 libx11-xcb1 libxext6 libxrender1 libxi6 libxrandr2 \
    libxcomposite1 libxdamage1 libxkbcommon0 libxfixes3 \
    libxcb1 libxcb-render0 libxcb-shm0 \
    libdrm2 libgbm1 \
    libxss1 libxtst6 libasound2t64 \
    libsecret-1-0 libnotify4 libdbus-1-3 libgl1 \
 && rm -rf /var/lib/apt/lists/*

# Node.js LTS
RUN apt-get update && apt-get install -y curl gnupg && \
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install OpenResty (nginx with built-in LuaJIT & ngx_lua)
RUN set -eux; \
    apt-get update && apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release && \
    curl -fsSL https://openresty.org/package/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/openresty.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package/ubuntu $(lsb_release -sc) main" \
      | tee /etc/apt/sources.list.d/openresty.list > /dev/null && \
    apt-get update && apt-get install -y --no-install-recommends openresty && \
    rm -rf /var/lib/apt/lists/*

# Non-root user paths (UID 1000)
RUN mkdir -p /home/user && chown -R 1000:1000 /home/user
ENV HOME=/home/user \
    VIRTUAL_ENV=/home/user/.venv \
    PATH=/home/user/.venv/bin:/home/user/.local/bin:$PATH
WORKDIR /home/user

# X11 socket dir (for Xvfb)
RUN mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix

# Clone MaiBot (Core) - 主项目
RUN git clone https://github.com/Mai-with-u/MaiBot.git /home/user/MaiBot-Core && \
    chown -R 1000:1000 /home/user/MaiBot-Core

# Clone MaiBot-Napcat-Adapter - 适配器
RUN git clone https://github.com/Mai-with-u/MaiBot-Napcat-Adapter.git /home/user/MaiBot-Adapter && \
    chown -R 1000:1000 /home/user/MaiBot-Adapter

# Clone MaiMBot-LPMM - 知识库模块（可选，需编译）
RUN git clone https://github.com/MaiM-with-u/MaiMBot-LPMM.git /home/user/MaiMBot-LPMM && \
    chown -R 1000:1000 /home/user/MaiMBot-LPMM

# Create MaiBot data dirs
RUN mkdir -p /home/user/MaiBot-Core/data && chown -R 1000:1000 /home/user/MaiBot-Core/data
RUN mkdir -p /home/user/MaiBot-Adapter/data && chown -R 1000:1000 /home/user/MaiBot-Adapter/data



# 1. Create venv and install base tools
RUN python3 -m venv "$VIRTUAL_ENV" && \
    "$VIRTUAL_ENV/bin/pip" install --no-cache-dir --upgrade pip uv

# 2. Install MaiBot-Core dependencies
RUN uv pip install -r /home/user/MaiBot-Core/requirements.txt --no-cache-dir --index-url ${PIP_INDEX_URL}

# 3. Install MaiBot-Adapter dependencies
RUN uv pip install -r /home/user/MaiBot-Adapter/requirements.txt --no-cache-dir --index-url ${PIP_INDEX_URL}

# 4. Install and compile LPMM (optional, may fail on some systems)
RUN uv pip install -r /home/user/MaiMBot-LPMM/requirements.txt --no-cache-dir --index-url ${PIP_INDEX_URL} || true && \
    cd /home/user/MaiMBot-LPMM/lib/quick_algo && \
    "$VIRTUAL_ENV/bin/python" build_lib.py --cleanup --cythonize --install || \
    echo "LPMM compilation failed, continuing without it..."

RUN chown -R 1000:1000 "$VIRTUAL_ENV"

# Default timezone
ENV TZ=Asia/Shanghai


# NapCat AppImage: download latest release, extract and keep extracted tree
RUN LATEST_URL=$(curl -sL https://api.github.com/repos/NapNeko/NapCatAppImageBuild/releases/latest | \
    jq -r '.assets[] | select(.name | endswith("-amd64.AppImage")) | .browser_download_url' | head -1) && \
    curl -L -o /home/user/QQ.AppImage "$LATEST_URL" && \
    chown 1000:1000 /home/user/QQ.AppImage && \
    chmod +x /home/user/QQ.AppImage && \
    /home/user/QQ.AppImage --appimage-extract && \
    mv squashfs-root /home/user/napcat && \
    chown -R 1000:1000 /home/user/napcat

# Download and install FileBrowser
RUN set -eux; \
    LATEST_URL="$(curl -fsSL https://api.github.com/repos/filebrowser/filebrowser/releases/latest | \
      jq -r '.assets[] | select(.name | contains("linux-amd64-filebrowser.tar.gz")) | .browser_download_url' | \
      head -n 1 | tr -d '\r')"; \
    test -n "${LATEST_URL}"; \
    curl -fL -o /tmp/filebrowser.tar.gz "${LATEST_URL}"; \
    tar -xzf /tmp/filebrowser.tar.gz -C /tmp; \
    mv /tmp/filebrowser /home/user/filebrowser; \
    chmod +x /home/user/filebrowser; \
    chown 1000:1000 /home/user/filebrowser; \
    rm -f /tmp/filebrowser.tar.gz; \
    mkdir -p /home/user/filebrowser-data; \
    chown -R 1000:1000 /home/user/filebrowser-data

# Download and install GoTTY (Web Terminal) - DISABLED
# RUN set -eux; \
#     LATEST_URL="$(curl -fsSL https://api.github.com/repos/sorenisanerd/gotty/releases/latest | \
#       jq -r '.assets[] | select(.name | test("gotty_v.*_linux_amd64\\.tar\\.gz$")) | .browser_download_url' | \
#       head -n 1 | tr -d '\r')"; \
#     test -n "${LATEST_URL}"; \
#     curl -fL -o /tmp/gotty.tar.gz "${LATEST_URL}"; \
#     tar -xzf /tmp/gotty.tar.gz -C /tmp; \
#     mv /tmp/gotty /home/user/gotty; \
#     chmod +x /home/user/gotty; \
#     chown 1000:1000 /home/user/gotty; \
#     rm -f /tmp/gotty.tar.gz

# Supervisor and Nginx config + logs
RUN mkdir -p /home/user/logs && chown -R 1000:1000 /home/user/logs
COPY --chown=1000:1000 supervisor/supervisord.conf /home/user/supervisord.conf
RUN mkdir -p /home/user/nginx && chown -R 1000:1000 /home/user/nginx
COPY --chown=1000:1000 nginx/nginx.conf /home/user/nginx/nginx.conf
COPY --chown=1000:1000 nginx/default_admin_config.json /home/user/nginx/default_admin_config.json
COPY --chown=1000:1000 nginx/route-admin /home/user/nginx/route-admin
RUN mkdir -p \
      /home/user/nginx/tmp/body \
      /home/user/nginx/tmp/proxy \
      /home/user/nginx/tmp/fastcgi \
      /home/user/nginx/tmp/uwsgi \
      /home/user/nginx/tmp/scgi \
    && chown -R 1000:1000 /home/user/nginx

# Sync service (daemon + web)
COPY --chown=1000:1000 sync /home/user/sync
RUN chown -R 1000:1000 /home/user/sync

# NapCat runtime dirs and launcher
RUN mkdir -p /app/.config/QQ /app/napcat/config && chown -R 1000:1000 /app
RUN mkdir -p /home/user/scripts && chown -R 1000:1000 /home/user/scripts
COPY --chown=1000:1000 scripts/run-napcat.sh /home/user/scripts/run-napcat.sh
COPY --chown=1000:1000 scripts/run-sin-proxy.sh /home/user/scripts/run-sin-proxy.sh
COPY --chown=1000:1000 scripts/wait-sync-ready.sh /home/user/scripts/wait-sync-ready.sh
COPY --chown=1000:1000 scripts/wait-for-sync.sh /home/user/scripts/wait-for-sync.sh
# Convert CRLF to LF (fix Windows line endings)
RUN sed -i 's/\r$//' /home/user/scripts/*.sh && \
    chmod +x /home/user/scripts/*.sh

# Env and ports
ENV DISPLAY=:1 \
    LIBGL_ALWAYS_SOFTWARE=1 \
    NAPCAT_FLAGS=""

# Optional: admin token for updating routes at runtime (used by Lua)
ENV ROUTE_ADMIN_TOKEN=""

# Ensure OpenResty binaries present in PATH
ENV PATH=/usr/local/openresty/bin:$PATH

EXPOSE 7860

# Run supervisord as root (napcat will run as user 1000 via supervisord.conf)
CMD ["supervisord", "-c", "/home/user/supervisord.conf"]
