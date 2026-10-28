# Workstation High-Throughput Profile Guide (GLM-5.3 744B MoE)

This guide documents the configuration, resource budgeting, and execution steps for running **GLM-5.3 744B MoE** locally using maximal dual-GPU VRAM acceleration on the **NVIDIA RTX PRO 6000 Blackwell Workstation Edition (96 GB)** paired with the **NVIDIA GeForce RTX 5090 (32 GB)**.

---

## 1. Resource Allocation & Isolation Strategy

The workstation high-throughput profile maximizes GDDR VRAM residency while maintaining necessary headroom for IsaacLab-Arena PhysX simulation and sensor rendering:

| Resource | Total Hardware Capacity | Colibrì Allocation | Reserved for IsaacLab & OS | Protection & Acceleration Mechanism |
|---|---|---|---|---|
| **GPU 0: RTX PRO 6000 Blackwell VRAM** | 97.8 GB (~96 GiB) | **~82.8 GiB allocated** (dense chain + 3,440 resident experts) | **~15.0 GiB Free Headroom** (for PhysX rigid-body simulation & RTX sensor rendering) | `COLI_VK_TIER_GB=72.0`, `COLI_VK_TIER_RESERVE_GB=4.0` |
| **GPU 1: RTX 5090 VRAM** | 32.6 GB | **24.9 GiB allocated** (1,215 secondary resident experts) | **7.2 GiB Free Headroom**, BAR1 aperture bounded to **10 MiB** | `COLI_VK_DEV2=auto`, `COLI_VK_EXPERTS2=1215`, `COLI_VK_STAGED=1` |
| **Combined Resident VRAM Pool** | 130.4 GB | **107.7 GiB (4,655 resident experts)** | **22.2 GiB Combined Free VRAM** | 46.6% of GLM-5.3 routed experts pinned directly in GDDR VRAM |
| **Host System RAM** | 98.1 GB (91.5 GiB usable) | **50.0 GB budget** (10 cache slots/layer + warm experts) | **~35+ GB Free & Available** | `RAM_GB=50.0` (Strictly prevents Docker container cgroup OOM kills) |
| **AMD Ryzen 9 9950X CPU** | 16 Cores / 32 Threads | 8 OpenMP Threads | **8 Physical Cores / 16 Threads Dedicated to Simulation** | `OMP_NUM_THREADS=8`, pinned at `nice -n 12` |
| **Storage Engine (Dual NVMe)** | Dual Samsung 9100 PRO | `DIRECT=1`, `PIPE=1`, `PIPE_WORKERS=16` | Direct I/O streaming at **9.5–16.1 GB/s** bypassing ext4 page locks | `O_DIRECT` + 16 asynchronous worker threads across primary & mirror drives |

---

## 2. Server Configuration & Dedicated Launcher

The dedicated launcher script is located at [`scripts/start_workstation_high_throughput_profile.sh`](../../../scripts/start_workstation_high_throughput_profile.sh):

```bash
#!/usr/bin/env bash
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
  python3 c/coli start --background --no-browser

echo "[Workstation Profile] Server started in background."
echo "[Workstation Profile] OpenAI Endpoint: http://127.0.0.1:8000/v1"
echo "[Workstation Profile] Checking status..."
python3 c/coli status
```

---

## 3. Verification & Performance Monitoring

| Target | Command | Expected Output |
| :--- | :--- | :--- |
| **Server Status** | `python3 c/coli status` | `server ready (pid ...)`, `openai http://127.0.0.1:8000/v1` |
| **API Health Check** | `curl -s http://127.0.0.1:8000/v1/models` | JSON response declaring `glm-5.2-colibri` |
| **VRAM Allocation** | `nvidia-smi` | GPU 0: ~82.8 GB used (~15 GB free); GPU 1: ~24.9 GB used (~7.2 GB free) |
| **Resident Expert Count** | `grep "budget" /root/.local/share/colibri/logs/serve.log` | `budget 72.00 GiB = 3440 experts`, `second device ... budget 25.31 GiB = 1215 experts` |
| **Warm-Start Check** | `grep "warm start" /root/.local/share/colibri/logs/serve.log` | `warm start, 4655 experts from the history in 23.1s` |
