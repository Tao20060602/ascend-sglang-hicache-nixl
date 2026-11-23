#!/usr/bin/env bash
# 启动 B 臂服务:SGLang launch_server(attention-backend ascend + HiCache NIXL L3)
# 用法:
#   bash scripts/30_serve.sh              # L1+L2(host 内存)+ NIXL L3
# 可选环境变量: TP=1 PORT=3000 HI_CACHE_RATIO=2 STORAGE_DIR=$HOME/sg_hicache_storage
# 终止服务用 scripts/90_teardown.sh(按 PID 终止,禁止 pgrep/pkill 模式匹配)。
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../versions.env
source "$SCRIPT_DIR/../versions.env"

TP="${TP:-1}"
PORT="${PORT:-30000}"
HI_CACHE_RATIO="${HI_CACHE_RATIO:-2}"
MODEL_ROOT="${MODEL_ROOT:-$HOME/models}"
MODEL_DIR="$MODEL_ROOT/$MODEL_DIR_NAME"
STORAGE_DIR="${STORAGE_DIR:-$HOME/sg_hicache_storage}"
RUNDIR="$SCRIPT_DIR/../run"
mkdir -p "$RUNDIR" "$STORAGE_DIR"

if [ ! -d "$MODEL_DIR" ]; then
  echo "[错误] 模型目录不存在: $MODEL_DIR,先执行 scripts/20_download_model.sh" >&2
  exit 1
fi

# 激活安装脚本创建的环境
if [ -f "$(conda info --base 2>/dev/null)/etc/profile.d/conda.sh" ]; then
  # shellcheck disable=SC1091
  source "$(conda info --base)/etc/profile.d/conda.sh"
  conda activate sg-npu
fi

# 启动参数说明:
#   --device npu --attention-backend ascend:SGLang 昇腾后端(文档标准写法)
#   --hicache-ratio: host 内存 L2 容量 = 显存池的倍数
#   --hicache-storage-backend nixl:L3 走 NIXL(POSIX AIO 队列实现)
# TODO(上机前对照你 x86 已验证配置补齐,3 项):
#   1) NIXL 后端的存储路径/预取参数如何传入——对照 lpl 的 x86 脚本与当前版本 server args 文档;
#   2) --hicache-io-backend:layer-wise kernel 路径按 CUDA kernel 实现,NPU 上大概率需要 direct;
#   3) 0.5.23 起 --hicache-size 语义变为 KV+Mamba 共享预算,若设置需复核当前版本语义。
nohup python -m sglang.launch_server \
  --model-path "$MODEL_DIR" \
  --device npu \
  --attention-backend ascend \
  --hicache-ratio "$HI_CACHE_RATIO" \
  --hicache-storage-backend nixl \
  --tp "$TP" \
  --port "$PORT" \
  --host 0.0.0.0 \
  > "$RUNDIR/sglang.log" 2>&1 < /dev/null &
echo $! > "$RUNDIR/sglang.pid"

sleep 8
SG_PID=$(cat "$RUNDIR/sglang.pid")
if ! kill -0 "$SG_PID" 2>/dev/null; then
  echo "[错误] sglang 进程立即退出,日志末尾:" >&2
  tail -n 40 "$RUNDIR/sglang.log" >&2
  exit 1
fi
echo "sglang 已启动(PID=$SG_PID),模型加载约需数分钟。"
echo "就绪检测: bash scripts/40_smoke.sh"
echo "  日志: $RUNDIR/sglang.log"
