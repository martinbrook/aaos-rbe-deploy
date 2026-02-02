# Custom AAOS runner image for Buildbarn remote execution.
# Provides Android build dependencies (JDK 17, Python 3, etc.) on Ubuntu 22.04.
#
# bb_runner and tini are NOT baked in — they are provided at runtime via the
# init container (bb-runner-installer) and mounted into /bb via emptyDir volume.
#
# Build:   docker build -t aaos-runner:local .
# Import:  k3d image import aaos-runner:local -c buildbarn

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Android build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-17-jdk \
    python3 \
    python3-pip \
    make \
    m4 \
    bison \
    flex \
    libncurses-dev \
    libssl-dev \
    zlib1g-dev \
    git \
    curl \
    zip \
    unzip \
    rsync \
    lsb-release \
    xz-utils \
    bc \
    lib32z1 \
    libc6-dev-i386 \
    locales \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Configure locale (required by some Android build scripts)
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Set JAVA_HOME for Android builds
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# Create worker directories expected by bb_runner
RUN mkdir -p /worker/build /worker/cache /bb
