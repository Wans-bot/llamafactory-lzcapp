#!/bin/bash
# LLaMA Factory · 懒猫微服启动脚本（LPK v1，上游 v0.9.5）
#
# 设计：WebUI 以持久目录 /work 作为工作目录运行，保证重启/升级不丢数据：
#   /work/data/               数据集（首次从镜像内置 /app/data 复制样例与 dataset_info.json）
#   /work/saves/              训练输出与 LoRA 检查点
#   /work/outputs/            评测输出
#   /work/llamaboard_cache/   WebUI 界面配置（含界面语言，首次预置为中文）
#   /work/llamaboard_config/  在 WebUI 中保存的训练配置
#   /work/cache/hf | ms       模型与数据集下载缓存
set -euo pipefail

WORK=/work
mkdir -p "$WORK/data" "$WORK/saves" "$WORK/outputs" \
         "$WORK/llamaboard_cache" "$WORK/llamaboard_config" \
         "$WORK/cache/hf" "$WORK/cache/ms"

# 首次运行：把镜像内置的数据集样例与 dataset_info.json 复制到持久目录
if [ ! -f "$WORK/data/dataset_info.json" ]; then
  cp -a /app/data/. "$WORK/data/" 2>/dev/null || true
fi

# 默认中文：首次运行写入界面语言配置；用户之后在界面里切换语言会保存，不会被覆盖
if [ ! -f "$WORK/llamaboard_cache/user_config.yaml" ]; then
  printf 'lang: zh\nhub_name: null\nlast_model: null\npath_dict: {}\ncache_dir: null\n' \
    > "$WORK/llamaboard_cache/user_config.yaml"
fi

# CPU 适配补丁（无 GPU 设备时）：把 Chat 页「推理数据类型」默认值 auto 改为 float32。
# 上游 auto 按模型 config 选用 bfloat16，而普通 x86 CPU（无 AVX512-BF16）上 bf16 推理极慢；
# float32 快约一个数量级。检测到 NVIDIA 设备时保持上游默认。幂等，软失败。
if [ ! -e /dev/nvidia0 ] && [ ! -e /dev/nvidiactl ]; then
  LF_INFER_PY=/app/src/llamafactory/webui/components/infer.py
  if [ -f "$LF_INFER_PY" ] && grep -q 'infer_dtype = gr.Dropdown' "$LF_INFER_PY"; then
    if grep 'infer_dtype = gr.Dropdown' "$LF_INFER_PY" | grep -q 'value="auto"'; then
      sed -i '/infer_dtype = gr.Dropdown/s/value="auto"/value="float32"/' "$LF_INFER_PY" \
        && echo "[boot] patched infer_dtype default -> float32 (no CUDA device)"
    fi
  fi
  LF_TRAIN_PY=/app/src/llamafactory/webui/components/train.py
  if [ -f "$LF_TRAIN_PY" ] && grep -q 'compute_type = gr.Dropdown' "$LF_TRAIN_PY"; then
    if grep 'compute_type = gr.Dropdown' "$LF_TRAIN_PY" | grep -q 'value="bf16"'; then
      sed -i '/compute_type = gr.Dropdown/s/value="bf16"/value="fp32"/' "$LF_TRAIN_PY" \
        && echo "[boot] patched compute_type default -> fp32 (no CUDA device)"
    fi
  fi
fi

export HF_HOME="$WORK/cache/hf"
export MODELSCOPE_CACHE="$WORK/cache/ms"
export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
export GRADIO_ANALYTICS_ENABLED=False

cd "$WORK"
echo "[boot] LLaMA-Factory v0.9.5 WebUI starting, workdir=$WORK"
exec llamafactory-cli webui
