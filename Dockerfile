# Dockerfile para compilar FFmpeg no Ubuntu 24.04
FROM ubuntu:24.04

# Definir variáveis de ambiente
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=America/Maceio
ENV PATH="/root/.cargo/bin:$PATH"

# Atualizar sistema e instalar dependências básicas
RUN apt-get update && apt-get upgrade -y && \
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
    cython3 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    && rustup target add x86_64-unknown-linux-musl

RUN cargo install cargo-c && \
    cargo install cargo-cache && \
    cargo cache --autoclean

# Criar diretório de trabalho
WORKDIR /ffmpeg-build

# Copiar o script de compilação
#COPY compile-ffmpeg.sh /ffmpeg-build/
#COPY build_config.txt /ffmpeg-build/

# Tornar o script executável
#RUN chmod +x /ffmpeg-build/compile-ffmpeg.sh

# Definir o comando padrão
CMD ["/bin/bash", "-c", "./compile-ffmpeg.sh --optimize=y && echo 'Compilação concluída! Os diretórios build e local estão disponíveis.'"]

#VOLUME ["/sys/fs/cgroup"]
# Expor volumes para os diretórios build e local
VOLUME ["/ffmpeg-build/build", "/ffmpeg-build/local"]
