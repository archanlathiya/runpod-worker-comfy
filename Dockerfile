# Stage 1: Base image with common dependencies
FROM nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04 as base

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1 
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Install Python, git and other necessary tools
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    git \
    wget \
    libgl1 \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    && ln -sf /usr/bin/python3.10 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Install comfy-cli
RUN pip install comfy-cli

# Install ComfyUI
RUN /usr/bin/yes | comfy --workspace /comfyui install --cuda-version 11.8 --nvidia

# Change working directory to ComfyUI
WORKDIR /comfyui

# Install runpod
RUN pip install runpod requests

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Go back to the root
WORKDIR /

# Add scripts
ADD src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
# Fix line endings
RUN sed -i 's/\r$//' /restore_snapshot.sh /start.sh
RUN chmod +x /start.sh /restore_snapshot.sh

# Optionally copy the snapshot file
ADD *snapshot*.json /

# Restore the snapshot to install custom nodes
RUN /restore_snapshot.sh

# Start container
CMD ["/start.sh"]

# Stage 2: Download models
FROM base as downloader

# Change working directory to ComfyUI
WORKDIR /comfyui

# Create necessary directories
RUN mkdir -p models/checkpoints models/clip models/clip_vision models/configs models/controlnet models/diffusers models/diffusion_models models/embeddings models/gligen models/hypernetworks models/loras models/photomaker models/style_models models/text_encoders models/unet models/upscale_models models/vae models/vae_approx

# Use build argument for Hugging Face token
ARG HUGGINGFACE_ACCESS_TOKEN

# Download unet model
RUN wget --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/unet/flux1-dev-Q8_0.gguf https://huggingface.co/city96/FLUX.1-dev-gguf/resolve/main/flux1-dev-Q8_0.gguf

# Download the Clip models
RUN wget --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/clip/clip_l.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors
RUN wget --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/clip/t5-v1_1-xxl-encoder-Q8_0.gguf https://huggingface.co/city96/t5-v1_1-xxl-encoder-gguf/resolve/main/t5-v1_1-xxl-encoder-Q8_0.gguf

# Download the VAE model
RUN wget --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/vae/ae.safetensors https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors

# Download the Style Model
RUN wget --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/style_models/flux1-redux-dev.safetensors https://huggingface.co/second-state/FLUX.1-Redux-dev-GGUF/resolve/c7e36ea59a409eaa553b9744b53aa350099d5d51/flux1-redux-dev.safetensors

# Download the Clip Vision model
RUN wget --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/clip_vision/sigclip_vision_patch14_384.safetensors https://huggingface.co/Comfy-Org/sigclip_vision_384/resolve/main/sigclip_vision_patch14_384.safetensors

# Download the Ghibli model
RUN wget --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/loras/studiochatgpt-ghibli-v1.safetensors https://huggingface.co/archanlathiya/main/resolve/main/studiochatgpt-ghibli-v1.safetensors

# Stage 3: Final image
FROM base as final

# Copy models from stage 2 to the final image
COPY --from=downloader /comfyui/models /comfyui/models

# Start container
CMD ["/start.sh"]