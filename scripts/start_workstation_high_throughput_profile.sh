#!/usr/bin/env bash
# ==============================================================================
# Colibrì GLM-5.3 Workstation High-Throughput Profile Launcher (RTX PRO 6000 + RTX 5090)
# ==============================================================================
# Architecture & Hardware Allocation:
# - Model: GLM-5.3 (744B Flagship MoE, 419.3 GB, 141 shards)
# - Dual-NVMe High-Speed Mirror: /models/glm-5.3 (primary) + /workspaces/colibri/models_mirror/glm-5.3 (mirror) -> 16+ GB/s aggregate throughput
# - GPU 0 (NVIDIA RTX PRO 6000 Blackwell 96 GB VRAM):
#     - COLI_VK_TIER_GB=72.0 (allocates 72 GiB VRAM for 3,440 resident experts)
#     - COLI_VK_TIER_RESERVE_GB=4.0 (tightened reserve margin)
#     - Reserves ~20 GB VRAM strictly for IsaacLab-Arena PhysX simulation & Omniverse sensor rendering
# - GPU 1 (NVIDIA GeForce RTX 5090 32 GB VRAM):
#     - COLI_VK_DEV2=auto, COLI_VK_EXPERTS2=1215 (allocates 25.3 GiB VRAM for 1,215 secondary resident experts)
#     - COLI_VK_STAGED=1 (DMA upload staging queue, keeps BAR1 aperture pinned to <= 10 MiB)
# - Combined Resident Pool: 4,655 hot experts (97.3 GiB) pinned directly in dual-GPU VRAM
# - Host System RAM: RAM_GB=50.0 (leaves 30+ GB free for Isaac Sim / host processes, preventing Docker cgroup OOM kills)
# - CPU Scheduling: OMP_NUM_THREADS=8 pinned at nice -n 12 (8 physical cores / 16 threads left 100% idle for simulation loops)
# - Headless Vulkan Direct Binding: DISPLAY="" with /etc/vulkan/icd.d/nvidia_icd.json
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

echo "[Workstation Profile] Stopping any running server..."
python3 c/coli stop 2>/dev/null || true

echo "[Workstation Profile] Locking GPU clocks & setting persistence mode..."
nvidia-smi -pm 1 >/dev/null 2>&1 || true
nvidia-smi -rmc >/dev/null 2>&1 || true
nvidia-smi -lgc 2100,2850 >/dev/null 2>&1 || true

echo "[Workstation Profile] Launching tuned Colibrì background server (72GB RTX PRO 6000 allocation)..."
nice -n 12 env \
  DISPLAY= \
  VK_ICD_FILENAMES=/etc/vulkan/icd.d/nvidia_icd.json \
  COLI_NO_OMP_TUNE=1 \
  COLI_VULKAN=1 \
  COLI_MODEL=/models/glm-5.3 \
  COLI_MODEL_MIRROR=/workspaces/colibri/models_mirror/glm-5.3 \
  COLI_VRAM_CACHE_MB=105000 \
  CTX=65536 \
  KV8=0 \
  RAM_GB=50 \
  DIRECT=1 \
  PIPE=1 \
  PIPE_WORKERS=16 \
  COLI_VK_STAGED=1 \
  COLI_VK_TIER_GB=72.0 \
  COLI_VK_TIER_RESERVE_GB=4.0 \
  COLI_VK_TIER_STREAM_SLOTS=16 \
  COLI_VK_TIER_STREAM_HALF=64 \
  COLI_VK_TIER_STREAM_ROWS=2 \
  COLI_VK_CHAIN_ROWS=128 \
  OMP_NUM_THREADS=8 \
  COLI_KV_SLOTS=2 \
  COLI_KV_SHARE=1 \
  COLI_VK_DEV2=auto \
  COLI_VK_EXPERTS2=1215 \
  COLI_VK_RESERVE2_GB=6.0 \
  COLI_QUEUE_TIMEOUT=1200 \
  python3 c/coli start --background --no-browser

echo "[Workstation Profile] Server started in background."
echo "[Workstation Profile] OpenAI Endpoint: http://127.0.0.1:8000/v1"
echo "[Workstation Profile] Checking status..."
python3 c/coli status
