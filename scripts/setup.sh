#!/usr/bin/env bash
# Build molmodel and its dependencies on a Debian/Ubuntu system.
# Requires: sudo apt, git, curl, a C++ compiler.
# See BUILDING.md for what this does and for non-Debian alternatives.

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
GEMMI_VERSION=0.6.2
GEMMI_DIR="third_party/gemmi-${GEMMI_VERSION}"

# 1. System packages
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential cmake git curl \
    libblas-dev liblapack-dev zlib1g-dev \
    libsimbody-dev libopenmm-dev

# 2. Fetch gemmi if not already present
if [ ! -d "${GEMMI_DIR}" ]; then
    mkdir -p third_party
    curl -sL "https://github.com/project-gemmi/gemmi/archive/refs/tags/v${GEMMI_VERSION}.tar.gz" \
        -o /tmp/gemmi-${GEMMI_VERSION}.tar.gz
    tar -xzf /tmp/gemmi-${GEMMI_VERSION}.tar.gz -C third_party/
    rm /tmp/gemmi-${GEMMI_VERSION}.tar.gz
fi

# 3. Build gemmi in place (molmodel links against this tree)
cmake -S "${GEMMI_DIR}" -B "${GEMMI_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DUSE_PYTHON=OFF
cmake --build "${GEMMI_DIR}" -j"$(nproc)"
sudo cmake --install "${GEMMI_DIR}"
sudo ldconfig

# 4. Configure and build molmodel
# GEMMI_DIR no longer needs to be passed: CMakeLists.txt defaults to
# third_party/gemmi-0.6.2 when it is unset.
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"

echo
echo "Build finished. To install system-wide (optional):"
echo "    sudo cmake --install build && sudo ldconfig"
echo "To run the test suite:"
echo "    ctest --test-dir build"
