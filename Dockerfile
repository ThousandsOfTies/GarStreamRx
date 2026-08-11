FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/opt/platformio/bin:${PATH}

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates; \
    dpkg --add-architecture arm64; \
    if [ -f /etc/apt/sources.list.d/ubuntu.sources ] && ! grep -q '^Architectures:' /etc/apt/sources.list.d/ubuntu.sources; then \
      sed -i '/^Types: deb/a Architectures: amd64' /etc/apt/sources.list.d/ubuntu.sources; \
    fi; \
    printf '%s\n' \
      'Types: deb' \
      'Architectures: arm64' \
      'URIs: http://ports.ubuntu.com/ubuntu-ports/' \
      'Suites: noble noble-updates noble-backports' \
      'Components: main universe restricted multiverse' \
      'Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg' \
      '' \
      'Types: deb' \
      'Architectures: arm64' \
      'URIs: http://ports.ubuntu.com/ubuntu-ports/' \
      'Suites: noble-security' \
      'Components: main universe restricted multiverse' \
      'Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg' \
      > /etc/apt/sources.list.d/ubuntu-ports-arm64.sources; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      build-essential \
      ccache \
      cmake \
      dfu-util \
      file \
      gcc-aarch64-linux-gnu \
      g++-aarch64-linux-gnu \
      git \
      libffi-dev \
      libfuse3-dev \
      libfuse3-dev:arm64 \
      libglib2.0-dev:arm64 \
      libgstreamer1.0-dev:arm64 \
      libgstreamer-plugins-base1.0-dev:arm64 \
      libssl-dev \
      libusb-1.0-0 \
      make \
      ninja-build \
      openssh-client \
      pkg-config \
      python3 \
      python3-pip \
      python3-venv; \
    python3 -m venv /opt/platformio; \
    /opt/platformio/bin/python -m pip install --no-cache-dir --upgrade pip; \
    /opt/platformio/bin/pip install --no-cache-dir --upgrade platformio; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /work
