FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    curl \
    wget \
    xz-utils \
    unzip \
    make \
    cmake \
    ninja-build \
    pkg-config \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    gcc \
    g++ \
    bison \
    flex \
    tcl \
    libreadline-dev \
    libffi-dev \
    libboost-system-dev \
    libboost-python-dev \
    libboost-filesystem-dev \
    libboost-thread-dev \
    zlib1g-dev \
    libeigen3-dev \
    libftdi1-dev \
    libusb-1.0-0-dev \
    libhidapi-dev \
    yosys \
    iverilog \
    verilator \
    gtkwave \
    nextpnr-ice40 \
    fpga-icestorm \
    gcc-riscv64-unknown-elf \
    binutils-riscv64-unknown-elf \
    opensta \
    && rm -rf /var/lib/apt/lists/*

# Build and install MuseLab iCELink programmer (icesprog)
RUN git clone --depth 1 https://github.com/wuxx/icesugar.git /tmp/icesugar \
    && make -C /tmp/icesugar/tools/src \
    && install -m 0755 /tmp/icesugar/tools/src/icesprog /usr/local/bin/icesprog \
    && rm -rf /tmp/icesugar

# Project expects riscv32-unknown-elf-* names; map from riscv64 toolchain binaries.
RUN ln -sf /usr/bin/riscv64-unknown-elf-gcc /usr/local/bin/riscv32-unknown-elf-gcc \
    && ln -sf /usr/bin/riscv64-unknown-elf-objcopy /usr/local/bin/riscv32-unknown-elf-objcopy \
    && ln -sf /usr/bin/riscv64-unknown-elf-cpp /usr/local/bin/riscv32-unknown-elf-cpp

# Python packages used by the repo flow
RUN pip3 install --no-cache-dir \
    sympy \
    numpy \
    pandas \
    matplotlib \
    tabulate

WORKDIR /workspace

COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
