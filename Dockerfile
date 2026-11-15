# Container image for building and running molmodel.
#
# Replaces the previous Dockerfile, which built Simbody and OpenMM from
# source and passed a GEMMI_PATH variable that molmodel's CMakeLists.txt
# does not read. This version installs Simbody and OpenMM from apt and
# builds gemmi 0.6.2 from source, matching the recipe in BUILDING.md.
#
# Build:
#   docker build -t molmodel .
# Run an example:
#   docker run --rm molmodel ExampleTwoEthanes
# Open a shell:
#   docker run -it --rm molmodel bash

FROM ubuntu:24.04

ARG GEMMI_VERSION=0.6.2

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        build-essential cmake git curl ca-certificates \
        libblas-dev liblapack-dev zlib1g-dev \
        libsimbody-dev libopenmm-dev

# Build gemmi in place under /opt/third_party so its headers and libraries
# live in one tree, which is what molmodel's GEMMI_DIR expects.
RUN mkdir -p /opt/third_party && \
    curl -sL "https://github.com/project-gemmi/gemmi/archive/refs/tags/v${GEMMI_VERSION}.tar.gz" \
        -o /tmp/gemmi.tar.gz && \
    tar -xzf /tmp/gemmi.tar.gz -C /opt/third_party && \
    rm /tmp/gemmi.tar.gz && \
    cmake -S "/opt/third_party/gemmi-${GEMMI_VERSION}" \
          -B "/opt/third_party/gemmi-${GEMMI_VERSION}" \
          -DCMAKE_BUILD_TYPE=Release \
          -DBUILD_SHARED_LIBS=ON \
          -DUSE_PYTHON=OFF && \
    cmake --build "/opt/third_party/gemmi-${GEMMI_VERSION}" -j"$(nproc)" && \
    cmake --install "/opt/third_party/gemmi-${GEMMI_VERSION}" && \
    ldconfig

# Copy the source in and build. GEMMI_DIR defaults to third_party/gemmi-0.6.2
# inside the source tree (see CMakeLists.txt), so point it at the image's
# copy instead.
WORKDIR /opt/molmodel
COPY . /opt/molmodel
RUN cmake -S . -B build \
        -DGEMMI_DIR="/opt/third_party/gemmi-${GEMMI_VERSION}" \
        -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build -j"$(nproc)" && \
    cmake --install build && \
    ldconfig

ENV LD_LIBRARY_PATH=/usr/local/lib

# Smoke test: run a program that does not need a visualizer.
CMD ["build/tests/TestEthane"]
