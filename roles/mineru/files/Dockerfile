# syntax=docker/dockerfile:1
#
# MinerU — image CPU (backend « pipeline »).
#
# Pourquoi une image maison plutôt que l'image officielle ?
#   L'image officielle d'opendatalab est basée sur vLLM/CUDA (GPU obligatoire).
#   Sur un VPS sans GPU NVIDIA, on construit une image CPU minimale.
#
# Le backend « pipeline » (modèles classiques layout + OCR) tourne en CPU.
# Le backend « vlm » (modèle multimodal) n'est PAS installé : il exige un GPU.
#
# Construit nativement sur le VPS amd64 (pas de --platform : sinon warning et
# build potentiellement émulé).
FROM python:3.12-slim

# Version de MinerU épinglée pour la reproductibilité (passée en build-arg par
# Ansible depuis mineru_version ; cf. roles/mineru/defaults/main.yml).
ARG MINERU_VERSION=3.4.0

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    # Force l'inférence CPU (aucun GPU disponible).
    MINERU_DEVICE_MODE=cpu \
    # Source des modèles au 1er téléchargement (huggingface | modelscope | local).
    MINERU_MODEL_SOURCE=huggingface \
    # Caches modèles + config sur le volume monté (cf. compose) → persistants
    # entre redémarrages, donc téléchargés une seule fois.
    HF_HOME=/models/huggingface \
    MODELSCOPE_CACHE=/models/modelscope \
    MINERU_TOOLS_CONFIG_JSON=/models/mineru.json

# Dépendances système : OpenCV (libgl/libglib), OpenMP (libgomp), wget (healthcheck).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libgl1 \
      libglib2.0-0 \
      libgomp1 \
      wget \
 && rm -rf /var/lib/apt/lists/*

# IMPORTANT : installer torch/torchvision en version CPU depuis l'index dédié
# PyTorch AVANT mineru. La roue PyPI par défaut de torch tire tout le stack CUDA
# (nvidia-cublas, nvidia-cudnn, cuda-toolkit… ≈ 6 Go) — inutile sur un VPS sans
# GPU et qui sature le disque. Une fois torch CPU présent, `mineru[core]` le voit
# satisfait et ne retélécharge pas la variante CUDA.
# Versions alignées sur ce que résout mineru[core]==3.4.0 (à ré-aligner si bump).
#
# mineru[core] = backend pipeline + serveur API + gradio, SANS les moteurs GPU
# (vllm/sglang/lmdeploy).
RUN pip install --upgrade pip \
 && pip install --index-url https://download.pytorch.org/whl/cpu \
      "torch==2.12.1" "torchvision==0.27.1" \
 && pip install "mineru[core]==${MINERU_VERSION}"

# Répertoire de sortie par défaut de mineru-api (monté en volume dans compose).
WORKDIR /app
RUN mkdir -p /app/output /models

EXPOSE 8000

# Le serveur démarre vite ; les modèles se chargent à la 1re requête de parsing.
# IMPORTANT : le backend par défaut de l'API exige un GPU → les requêtes doivent
# passer backend=pipeline (géré côté consommateur, cf. README).
CMD ["mineru-api", "--host", "0.0.0.0", "--port", "8000"]
