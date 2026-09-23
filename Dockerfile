FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update
RUN apt-get install -y \
    build-essential \
    gcc-10 \
    g++-10 \
    gcc-9 \
    g++-9 \
    ncurses-dev \
    bc \
    git \
    libssl-dev \
    libc6-i386 \
    libncurses-dev \
    libelf-dev \
    curl \
    libproc-processtable-perl \
    wget \
    kmod \
    jq \
    cifs-utils \
    python3 \
    python3-pip \
    python-is-python3 \
    flex \
    bison \
    pkg-config \
    perl \
 && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 100 \
 && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 100 \
 && rm -rf /var/lib/apt/lists/*

ENV HOSTCFLAGS="-Wno-error"

RUN mkdir /synology-toolkit
RUN mkdir /synology-toolkit/toolchains

WORKDIR /synology-toolkit
COPY platforms.json .
COPY entrypoint.sh .
COPY config_modification.json .
COPY apply_patches.sh .
RUN chmod +x apply_patches.sh entrypoint.sh

ENV PLATFORM=""
ENV IMAGE_TYPE="standard"

ENTRYPOINT ["/synology-toolkit/entrypoint.sh"]
