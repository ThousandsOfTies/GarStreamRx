FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

# The repo launcher bundled in the Luckfox archive predates Python 3 support
# and imports Python 2-only modules. This image is used only for `repo sync -l`;
# all SDK compilation remains in the Ubuntu 22.04 image.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      git \
      python2; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /sdk
