#!/usr/bin/env bash
# B 臂安装:conda py3.12 + torch/torch_npu(CANN 9.1.0 套件) + SGLang 主线(NPU 方式) + NIXL
# 目标环境:GitCode CANN Lab,Atlas A3(910C)。注意:套件表按 CANN 9.1.0 编写;
# 若容器 CANN 是 9.0.0,先在 sglang Ascend 文档版本表里查 9.0.0 对应行,改 versions.env 再跑。
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../versions.env
source "$SCRIPT_DIR/../versions.env"

PIP_INDEX_URL="${PIP_INDEX_URL:-https://mirrors.aliyun.com/pypi/simple/}"
PYTORCH_INDEX="https://download.pytorch.org/whl/cpu/"
TORCH_NPU_INDEX="https://ascend.devcloud.huaweicloud.com/pypi/simple/"
export PIP_INDEX_URL
WORKROOT="${WORKROOT:-$HOME/ascend-stack}"
LOGDIR="$SCRIPT_DIR/../run"
mkdir -p "$WORKROOT" "$LOGDIR"

echo "==> [0/6] 前置检查:conda 与容器 CANN 版本"
if ! command -v conda >/dev/null 2>&1; then
  echo "[错误] 未找到 conda。SGLang NPU 套件要求 Python $PY_VER(镜像自带 3.11 不满足)。" >&2
  echo "       请先安装 Miniconda(aarch64)后重跑本脚本。" >&2
  exit 1
fi
CANN_FILE=/usr/local/Ascend/ascend-toolkit/latest/version.cfg
if [ -f "$CANN_FILE" ]; then
  echo "    容器 CANN: $(head -n 3 "$CANN_FILE" | tr '\n' ' ')"
  echo "    本脚本套件按 CANN 9.1.0 编写;若版本不符,按文档改 versions.env 后重跑。"
fi

echo "==> [1/6] 创建 conda 环境 sg-npu (Python $PY_VER)"
source "$(conda info --base)/etc/profile.d/conda.sh"
conda create -y -n sg-npu python="$PY_VER" 2>/dev/null || conda create -y -n sg-npu python="$PY_VER"
conda activate sg-npu
pip install -U pip setuptools wheel

echo "==> [2/6] 安装 torch $TORCH_VERSION / torchvision $TORCHVISION_VERSION (aarch64 CPU 轮)"
pip install "torch==$TORCH_VERSION" "torchvision==$TORCHVISION_VERSION" --index-url "$PYTORCH_INDEX"

echo "==> [3/6] 安装 torch_npu $TORCH_NPU_VERSION"
pip install "torch_npu==$TORCH_NPU_VERSION" --extra-index-url "$TORCH_NPU_INDEX"
python3 -c "import torch, torch_npu; print('torch_npu OK, device 数:', torch.npu.device_count())" \
  || echo "[warn] torch_npu import 失败:检查 CANN 环境变量是否已 source(set | grep -i ascend)"

echo "==> [4/6] 源码安装 SGLang ($SGLANG_REF, NPU 方式)"
cd "$WORKROOT"
if [ ! -d sglang ]; then
  git clone https://github.com/sgl-project/sglang.git sglang
fi
if [ "$SGLANG_REF" != "main" ]; then
  git -C sglang checkout "$SGLANG_REF"
fi
cd sglang
# 昇腾安装的关键一步:用 NPU 专用工程文件替换默认 pyproject
mv -f python/pyproject_npu.toml python/pyproject.toml
pip install -e "python[all_npu]"
# all_npu extra 应已拉入 sgl-kernel-npu / triton-ascend;若报缺失,按文档补装:
#   pip install sgl-kernel-npu==2026.9.0.post9 triton-ascend==3.2.2

echo "==> [5/6] 安装 NIXL"
if [ -n "${NIXL_REF:-}" ]; then
  if [ ! -d nixl ]; then
    git clone https://github.com/ai-dynamo/nixl.git nixl
  fi
  git -C nixl checkout "$NIXL_REF"
  pip install -e ./nixl
else
  pip install nixl
fi
python3 -c "import nixl; print('nixl import OK')" || echo "[warn] nixl import 失败:检查 aarch64 轮子是否带 POSIX 后端,必要时源码构建"

echo "==> [6/6] 版本清单(复制进报告)"
pip list 2>/dev/null | grep -Ei '^(sglang|sgl-kernel|nixl|torch|triton|torch-npu|torchvision)' || true
git -C "$WORKROOT/sglang" log -1 --format='sglang commit: %H %cd' || true
echo "安装完成。下一步:scripts/20_download_model.sh"
