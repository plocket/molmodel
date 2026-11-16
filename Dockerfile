# Container image for building and running molmodel.
#
# Dependency policy:
# - Simbody 3.9 and gemmi 0.6.2 are built from pinned source releases
#   (docs/DECISION-simbody-3.9.md explains why 3.9).
# - OpenMM comes from Ubuntu's repository. Pinning it is deferred until
#   the Simbody pin has proven itself; see docs/PLAN-pinned-build.md.
#
# Build:
#   docker build -t molmodel .
# Run the smoke test:
#   docker run --rm molmodel
# Open a shell:
#   docker run -it --rm molmodel bash

FROM ubuntu:24.04

ARG SIMBODY_VERSION=3.9
ARG GEMMI_VERSION=0.6.2
ARG OPENMM_VERSION=8.1.2

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        build-essential cmake git curl ca-certificates \
        libblas-dev liblapack-dev zlib1g-dev \
        libopenmm-dev

# gemmi 0.6.2 from pinned source. molmodel requires 0.6.x; newer gemmi
# does not compile against this code.
RUN curl -sL "https://github.com/project-gemmi/gemmi/archive/refs/tags/v${GEMMI_VERSION}.tar.gz" \
        -o /tmp/gemmi.tar.gz && \
    mkdir /opt/gemmi && tar -xzf /tmp/gemmi.tar.gz -C /opt/gemmi --strip-components=1 && \
    rm /tmp/gemmi.tar.gz && \
    cmake -S /opt/gemmi -B /opt/gemmi/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DUSE_PYTHON=OFF && \
    cmake --build /opt/gemmi/build -j"$(nproc)" && \
    cmake --install /opt/gemmi/build

# Simbody 3.9 from pinned source. Ubuntu's packaged Simbody (3.7) crashes
# most of molmodel's test suite; see docs/DECISION-simbody-3.9.md.
RUN curl -sL "https://github.com/simbody/simbody/archive/refs/tags/Simbody-${SIMBODY_VERSION}.tar.gz" \
        -o /tmp/simbody.tar.gz && \
    mkdir /opt/simbody && tar -xzf /tmp/simbody.tar.gz -C /opt/simbody --strip-components=1 && \
    rm /tmp/simbody.tar.gz && \
    cmake -S /opt/simbody -B /opt/simbody/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_TESTING=OFF && \
    cmake --build /opt/simbody/build -j"$(nproc)" && \
    cmake --install /opt/simbody/build && \
    ldconfig

# molmodel. GEMMI_DIR points at the gemmi source tree, whose headers and
# libraries CMakeLists.txt expects to find in place.
WORKDIR /opt/molmodel
COPY . /opt/molmodel
RUN cmake -S . -B build \
        -DGEMMI_DIR=/opt/gemmi \
        -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build -j"$(nproc)" && \
    cmake --install build && \
    ldconfig

# Smoke test: a program that does not need a visualizer.
CMD ["build/tests/TestEthane"]
