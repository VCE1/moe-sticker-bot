# ----------------- 阶段 1: 编译 Go 二进制 -----------------
FROM golang:1.20-bookworm AS go-builder

ENV GOPROXY=https://goproxy.cn,direct

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /moe-sticker-bot ./cmd/moe-sticker-bot/

# ----------------- 阶段 2: 编译 Python 依赖轮子 -----------------
FROM debian:bookworm-slim AS py-builder

# 改用阿里云镜像源，并增加 apt 超时和重试参数
RUN sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources 2>/dev/null || \
    sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list 2>/dev/null; \
    sed -i 's/security.debian.org/mirrors.aliyun.com\/debian-security/g' /etc/apt/sources.list.d/debian.sources 2>/dev/null || \
    sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list 2>/dev/null

RUN echo 'Acquire::http::Timeout "30";\nAcquire::Retries "3";' > /etc/apt/apt.conf.d/99timeout

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-dev \
    build-essential \
    cmake \
    ca-certificates

# 直接编译打包 wheel 到临时目录，加速后续复用
RUN pip3 wheel --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple \
    --wheel-dir=/wheels \
    emoji rlottie-python Pillow

# ----------------- 阶段 3: 最终精简运行镜像 -----------------
FROM debian:bookworm-slim

RUN sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources 2>/dev/null || \
    sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list 2>/dev/null; \
    sed -i 's/security.debian.org/mirrors.aliyun.com\/debian-security/g' /etc/apt/sources.list.d/debian.sources 2>/dev/null || \
    sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list 2>/dev/null

RUN echo 'Acquire::http::Timeout "30";\nAcquire::Retries "3";' > /etc/apt/apt.conf.d/99timeout

# 最终层仅安装运行时依赖，不再安装 gcc/cmake 等大体积编译器
RUN apt-get update && apt-get install -y --no-install-recommends \
    imagemagick \
    ffmpeg \
    libarchive-tools \
    gifsicle \
    python3 \
    python3-pip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 从阶段 2 复制 wheel 包并离线安装
COPY --from=py-builder /wheels /wheels
RUN pip3 install --no-cache-dir --break-system-packages --no-index --find-links=/wheels /wheels/* \
    && rm -rf /wheels

COPY --from=go-builder /moe-sticker-bot /moe-sticker-bot
COPY tools/msb_emoji.py /usr/local/bin/msb_emoji.py
COPY tools/msb_kakao_decrypt.py /usr/local/bin/msb_kakao_decrypt.py
COPY tools/msb_rlottie.py /usr/local/bin/msb_rlottie.py

ENTRYPOINT ["/moe-sticker-bot"]
