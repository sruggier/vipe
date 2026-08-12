FROM runpod/pytorch:1.1.0-cu1281-torch291-ubuntu2404

# Below lines adapted from
# https://github.com/astral-sh/uv-docker-example/blob/main/Dockerfile

ENV UV_TOOL_BIN_DIR=/usr/local/bin
ENV UV_NO_DEV=1
ENV UV_LINK_MODE=copy
ENV UV_NO_EDITABLE=1
ENV UV_COMPILE_BYTECODE=1

COPY <<EOF /etc/uv/uv.toml
[extra-build-variables.nvidia-vipe]
# The set of architectures that are both available as pods and
# supported by Cuda 12.8's nvcc.
TORCH_CUDA_ARCH_LIST= "Ampere;Ada;10.0;12.0"
EOF

# Install dependencies separately, to optimize layer caching
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=/vipe/uv.lock \
    --mount=type=bind,source=pyproject.toml,target=/vipe/pyproject.toml \
    --mount=type=bind,source=.python-version,target=/vipe/.python-version \
	cd /vipe && \
	uv sync --locked --no-install-project --group lyra && \
	uv pip install 'https://github.com/nvidia-isaac/cuVSLAM/releases/download/v17.0.0/cuvslam-17.0.0+cu12-cp312-abi3-manylinux_2_39_x86_64.whl'

COPY . /vipe
RUN --mount=type=cache,target=/root/.cache/uv \
	uv sync --directory /vipe --locked --inexact

ENV PATH="/vipe/.venv/bin:$PATH"
