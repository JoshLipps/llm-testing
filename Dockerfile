# Custom llama.cpp build for AMD Strix Halo (gfx1151, RDNA 3.5, unified memory).
# The official ghcr.io/ggml-org/llama.cpp:server-rocm image targets older AMD GPUs
# and is not compiled with gfx1151 in AMDGPU_TARGETS. We build from source against
# a recent ROCm so HIP picks the right kernels and we can flip on UMA.

ARG ROCM_VERSION=7.2.2
FROM rocm/dev-ubuntu-24.04:${ROCM_VERSION}-complete AS build

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake git ninja-build pkg-config \
        libcurl4-openssl-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ARG LLAMA_CPP_REF=master
WORKDIR /src
RUN git clone --depth 1 --branch ${LLAMA_CPP_REF} https://github.com/ggml-org/llama.cpp.git

WORKDIR /src/llama.cpp
# GPU_TARGETS=gfx1151 — explicit Strix Halo target (no HSA_OVERRIDE needed at runtime).
# GGML_HIP_UMA=ON — let HIP allocate from the unified memory pool instead of carving VRAM.
# GGML_NATIVE=ON — pick up Zen 5 AVX-512 / VNNI for prompt-processing CPU paths.
RUN cmake -S . -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_HIP=ON \
        -DGGML_HIP_UMA=ON \
        -DGGML_NATIVE=ON \
        -DGPU_TARGETS=gfx1151 \
        -DAMDGPU_TARGETS=gfx1151 \
        -DLLAMA_CURL=ON \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_EXAMPLES=ON \
    && cmake --build build --config Release -j

# ---- Runtime stage ----------------------------------------------------------
FROM rocm/dev-ubuntu-24.04:${ROCM_VERSION}-complete

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        libcurl4 ca-certificates tini \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/llama.cpp/build/bin/ /tmp/llamabuild/
RUN set -eux; \
    install -d /usr/local/bin /usr/local/lib; \
    cp -av /tmp/llamabuild/*.so* /usr/local/lib/; \
    find /tmp/llamabuild -maxdepth 1 -type f -executable ! -name '*.so*' -exec cp -av {} /usr/local/bin/ \; ; \
    rm -rf /tmp/llamabuild; \
    ldconfig

ENV PATH=/usr/local/bin:/opt/rocm/bin:${PATH}
EXPOSE 8080
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/llama-server"]
