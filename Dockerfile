# Dockerfile para compilar FFmpeg com s6-overlay - Versão Parametrizada
ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION} as rootfs-stage

# Build args com valores padrão
ARG BUILD_MODE=compile
ARG USER_ID=1001
ARG GROUP_ID=1001
ARG USERNAME=builduser

# set version for s6 overlay
ARG S6_OVERLAY_VERSION="3.2.0.2"
ARG S6_OVERLAY_ARCH="x86_64"

# add s6 overlay
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_OVERLAY_ARCH}.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-${S6_OVERLAY_ARCH}.tar.xz

# add s6 optional symlinks
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-noarch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-symlinks-noarch.tar.xz && unlink /usr/bin/with-contenv
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-arch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-symlinks-arch.tar.xz

# LinuxServer mod scripts
ARG MODS_VERSION="v3"
ARG PKG_INST_VERSION="v1"
ARG LSIOWN_VERSION="v1"
ARG WITHCONTENV_VERSION="v1"
ADD --chmod=755 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/docker-mods.${MODS_VERSION}" "/docker-mods"
ADD --chmod=755 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/package-install.${PKG_INST_VERSION}" "/etc/s6-overlay/s6-rc.d/init-mods-package-install/run"
ADD --chmod=755 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/lsiown.${LSIOWN_VERSION}" "/usr/bin/lsiown"
ADD --chmod=755 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/with-contenv.${WITHCONTENV_VERSION}" "/usr/bin/with-contenv"

# Definir variáveis de ambiente
ARG DEBIAN_FRONTEND="noninteractive"
ENV HOME="/root" \
    LANGUAGE="en_US.UTF-8" \
    LANG="en_US.UTF-8" \
    TERM="xterm" \
    TZ="America/Maceio" \
    PATH="/root/.cargo/bin:$PATH" \
    S6_CMD_WAIT_FOR_SERVICES_MAXTIME="0" \
    S6_VERBOSITY=1 \
    S6_STAGE2_HOOK=/docker-mods \
    PUID=${USER_ID} \
    PGID=${GROUP_ID} \
    VIRTUAL_ENV=/lsiopy \
    PATH="/lsiopy/bin:$PATH"

# Informações da versão para debugging
RUN echo "=== BUILD INFORMATION ===" && \
    echo "Building on Ubuntu: $(cat /etc/os-release | grep VERSION= | cut -d\" -f2)" && \
    echo "Build Arguments:" && \
    echo "  BUILD_MODE=${BUILD_MODE}" && \
    echo "  USER_ID=${USER_ID}" && \
    echo "  GROUP_ID=${GROUP_ID}" && \
    echo "  USERNAME=${USERNAME}" && \
    echo "  S6_OVERLAY_VERSION=${S6_OVERLAY_VERSION}" && \
    echo "=========================="

# copy sources
COPY sources.list /etc/apt/

# Atualizar sistema e instalar dependências básicas
RUN echo "**** Ripped from Ubuntu Docker Logic ****" && \
    rm -f /etc/apt/sources.list.d/ubuntu.sources && \
    set -xe && \
    echo '#!/bin/sh' > /usr/sbin/policy-rc.d && \
    echo 'exit 101' >> /usr/sbin/policy-rc.d && \
    chmod +x /usr/sbin/policy-rc.d && \
    dpkg-divert --local --rename --add /sbin/initctl && \
    cp -a /usr/sbin/policy-rc.d /sbin/initctl && \
    sed -i 's/^exit.*/exit 0/' /sbin/initctl && \
    echo 'force-unsafe-io' > /etc/dpkg/dpkg.cfg.d/docker-apt-speedup && \
    echo 'DPkg::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' > /etc/apt/apt.conf.d/docker-clean && \
    echo 'APT::Update::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' >> /etc/apt/apt.conf.d/docker-clean && \
    echo 'Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache "";' >> /etc/apt/apt.conf.d/docker-clean && \
    echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/docker-no-languages && \
    echo 'Acquire::GzipIndexes "true"; Acquire::CompressionTypes::Order:: "gz";' > /etc/apt/apt.conf.d/docker-gzip-indexes && \
    echo 'Apt::AutoRemove::SuggestsImportant "false";' > /etc/apt/apt.conf.d/docker-autoremove-suggests && \
    mkdir -p /run/systemd && \
    echo 'docker' > /run/systemd/container && \
    echo "**** install apt-utils, locales and extras tools ****" && \
    apt-get update && apt-get upgrade -y && \
    apt-get install -y \
    apt-utils \
    locales \
    catatonit \
    cron \
    gnupg \
    jq \
    netcat-openbsd \
    systemd-standalone-sysusers \
    sudo \
    tzdata && \
    echo "**** install packages ****" && \
    apt-get update && apt-get upgrade -y && \
    apt-get install -y \
    autoconf \
    automake \
    build-essential \
    libtool \
    pkg-config \
    texi2html \
    yasm \
    cmake \
    curl \
    git \
    wget \
    gperf \
    ninja-build \
    nasm \
    meson \
    rsync \
    libssl-dev \
    xxd \
    coreutils \
    python3 \
    cython3 && \
    echo "**** generate locale ****" && \
    locale-gen en_US.UTF-8 && \
    echo "**** create builduser and make our folders ****" && \
    useradd -u ${USER_ID} -U -d /ffmpeg-build -s /bin/bash ${USERNAME} && \
    echo "**** user perms ****" && \
    sed -e 's/%sudo	ALL=(ALL:ALL) ALL/%sudo ALL=(ALL:ALL) NOPASSWD: ALL/g' \
        -i /etc/sudoers && \
    echo "builduser:linux" | chpasswd && \
    usermod -aG sudo ${USERNAME} && \
        mkdir -p \
        /config \
        /defaults \
        /ffmpeg-build \
        /lsiopy && \
    echo "**** proot-apps ****" && \
    mkdir /proot-apps/ && \
    PAPPS_RELEASE=$(curl -sX GET "https://api.github.com/repos/linuxserver/proot-apps/releases/latest" \
        | awk '/tag_name/{print $4;exit}' FS='[""]') && \
    curl -L https://github.com/linuxserver/proot-apps/releases/download/${PAPPS_RELEASE}/proot-apps-x86_64.tar.gz \
        | tar -xzf - -C /proot-apps/ && \
    echo "${PAPPS_RELEASE}" > /proot-apps/pversion && \
    echo "**** cleanup ****" && \
    if id ubuntu >/dev/null 2>&1; then userdel ubuntu; fi && \
    apt-get autoremove && \
    apt-get clean && \
    rm -rf \
        /tmp/* \
        /var/lib/apt/lists/* \
        /var/tmp/* \
        /var/log/*

# Instalar Rust apenas se necessário
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
    rustup target add x86_64-unknown-linux-musl && \
    cargo install cargo-c && \
    cargo install cargo-cache && \
    cargo cache --autoclean

# Criar estrutura s6-overlay para init-adduser (substitui abc por builduser)
RUN mkdir -p /etc/s6-overlay/s6-rc.d/init-adduser && \
    echo "oneshot" > /etc/s6-overlay/s6-rc.d/init-adduser/type && \
    echo "init-adduser" > /etc/s6-overlay/s6-rc.d/user/contents.d/init-adduser

# Script init-adduser customizado para builduser
RUN cat > /etc/s6-overlay/s6-rc.d/init-adduser/run << 'EOF'
#!/usr/bin/with-contenv bash

PUID=${PUID:-1001}
PGID=${PGID:-1001}
USERNAME=${USERNAME:-builduser}

# Verificar se o usuário existe
if id "$USERNAME" >/dev/null 2>&1; then
    echo "User $USERNAME exists, modifying UID/GID..."
    groupmod -o -g "$PGID" $USERNAME
    usermod -o -u "$PUID" $USERNAME
else
    echo "User $USERNAME doesn't exist, creating..."
    groupadd -g "$PGID" $USERNAME
    useradd -u "$PUID" -g "$PGID" -d /ffmpeg-build -s /bin/bash $USERNAME
fi

echo '
-------------------------------------
        FFmpeg Build Container
           with s6-overlay
-------------------------------------
PUID/PGID
-------------------------------------'
echo "
User uid:    $(id -u $USERNAME)
User gid:    $(id -g $USERNAME)
Username:    $USERNAME
-------------------------------------
"

# Ajustar permissões dos diretórios
chown -R $USERNAME:$USERNAME /ffmpeg-build
EOF

RUN chmod +x /etc/s6-overlay/s6-rc.d/init-adduser/run

# Criar serviço s6 para FFmpeg build
RUN mkdir -p /etc/s6-overlay/s6-rc.d/svc-ffmpeg-build && \
    echo "longrun" > /etc/s6-overlay/s6-rc.d/svc-ffmpeg-build/type && \
    echo "init-adduser" > /etc/s6-overlay/s6-rc.d/svc-ffmpeg-build/dependencies.d/init-adduser

# Script do serviço FFmpeg build
RUN cat > /etc/s6-overlay/s6-rc.d/svc-ffmpeg-build/run << 'EOF'
#!/usr/bin/with-contenv bash

USERNAME=${USERNAME:-builduser}

cd /ffmpeg-build

# Se entrypoint.sh existir, executar com s6-setuidgid
if [ -f "/entrypoint.sh" ]; then
    exec s6-setuidgid $USERNAME /entrypoint.sh "$@"
else
    # Caso contrário, manter shell ativo
    exec s6-setuidgid $USERNAME /bin/bash
fi
EOF

RUN chmod +x /etc/s6-overlay/s6-rc.d/svc-ffmpeg-build/run

# Configurar para que o serviço seja iniciado automaticamente
RUN echo "svc-ffmpeg-build" > /etc/s6-overlay/s6-rc.d/user/contents.d/svc-ffmpeg-build

# Script de entrada para modos diferentes
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x