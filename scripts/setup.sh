#!/usr/bin/env bash
# Build molmodel and its dependencies on a Debian/Ubuntu system.
# Requires: sudo apt, git, curl, a C++ compiler.
# See BUILDING.md for what this does and for non-Debian alternatives.
#
# Dependency policy (matches the Dockerfile):
# - Simbody 3.9 and gemmi 0.6.2 from pinned source releases
#   (docs/DECISION-simbody-3.9.md explains why 3.9)
# - OpenMM from apt (pinning deferred, see docs/PLAN-pinned-build.md)

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
SIMBODY_VERSION=3.9
GEMMI_VERSION=0.6.2

# 1. System packages
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential cmake git curl \
    libblas-dev liblapack-dev zlib1g-dev \
    libopenmm-dev

# 2. gemmi 0.6.2 from pinned source (molmodel requires 0.6.x)
if [ ! -d "third_party/gemmi-${GEMMI_VERSION}" ]; then
    mkdir -p third_party
    curl -sL "https://github.com/project-gemmi/gemmi/archive/refs/tags/v${GEMMI_VERSION}.tar.gz" \
        -o /tmp/gemmi-${GEMMI_VERSION}.tar.gz
    tar -xzf /tmp/gemmi-${GEMMI_VERSION}.tar.gz -C third_party/
    rm /tmp/gemmi-${GEMMI_VERSION}.tar.gz
fi
cmake -S "third_party/gemmi-${GEMMI_VERSION}" -B "third_party/gemmi-${GEMMI_VERSION}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DUSE_PYTHON=OFF
cmake --build "third_party/gemmi-${GEMMI_VERSION}" -j"$(nproc)"
sudo cmake --install "third_party/gemmi-${GEMMI_VERSION}"

# 3. Simbody from pinned source. Ubuntu's packaged Simbody (3.7) crashes
#    most of molmodel's test suite; see docs/DECISION-simbody-3.9.md.
if [ ! -d "third_party/simbody-Simbody-${SIMBODY_VERSION}" ]; then
    mkdir -p third_party
    curl -sL "https://github.com/simbody/simbody/archive/refs/tags/Simbody-${SIMBODY_VERSION}.tar.gz" \
        -o /tmp/simbody-${SIMBODY_VERSION}.tar.gz
    tar -xzf /tmp/simbody-${SIMBODY_VERSION}.tar.gz -C third_party/
    rm /tmp/simbody-${SIMBODY_VERSION}.tar.gz
fi
cmake -S "third_party/simbody-Simbody-${SIMBODY_VERSION}" \
      -B "third_party/simbody-Simbody-${SIMBODY_VERSION}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_TESTING=OFF
cmake --build "third_party/simbody-Simbody-${SIMBODY_VERSION}" -j"$(nproc)"
sudo cmake --install "third_party/simbody-Simbody-${SIMBODY_VERSION}"
sudo ldconfig

# 4. Configure and build molmodel.
# GEMMI_DIR defaults to third_party/gemmi-0.6.2 in CMakeLists.txt.
# Simbody_DIR is passed explicitly so the freshly built 3.9 is used
# rather than any system copy.
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
    -DSimbody_DIR=/usr/local/lib/cmake/simbody
cmake --build build -j"$(nproc)"

echo
echo "Build finished. To install system-wide (optional):"
echo "    sudo cmake --install build && sudo ldconfig"
echo "To run the test suite:"
echo "    ctest --test-dir build"
