FROM ubuntu:22.04

ARG BUILDER_UID=1000
ARG BUILDER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive

# Luckfox's RK3506 SDK is validated against Ubuntu 22.04 x86_64. Keep this
# image separate from the application cross-build image: it is used to
# materialize and build the vendor Buildroot tree itself.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      bc \
      binfmt-support \
      bison \
      bsdmainutils \
      build-essential \
      bzip2 \
      ca-certificates \
      chrpath \
      cmake \
      cpp-aarch64-linux-gnu \
      curl \
      device-tree-compiler \
      diffstat \
      expect \
      expect-dev \
      expat \
      fakeroot \
      file \
      flex \
      g++ \
      g++-multilib \
      gawk \
      gcc \
      gcc-multilib \
      git \
      gnupg2 \
      libgmp-dev \
      liblz4-tool \
      libmpc-dev \
      libncurses-dev \
      libssl-dev \
      live-build \
      make \
      patch \
      patchelf \
      passwd \
      python-is-python3 \
      python3 \
      qemu-user-static \
      rsync \
      scons \
      ssh \
      sudo \
      texinfo \
      unzip \
      wget \
      xz-utils; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Some host-side Buildroot tools (notably ssh-keygen) resolve the current UID
# through /etc/passwd.  Match the invoking WSL user so bind-mounted SDK output
# remains user-owned while those tools can still identify their account.
RUN set -eux; \
    if ! getent group "${BUILDER_GID}" >/dev/null; then \
      groupadd --gid "${BUILDER_GID}" builder; \
    fi; \
    builder_group="$(getent group "${BUILDER_GID}" | cut -d: -f1)"; \
    useradd \
      --uid "${BUILDER_UID}" \
      --gid "${builder_group}" \
      --create-home \
      --shell /bin/bash \
      builder

WORKDIR /sdk
