#!/usr/bin/env bash
# B 臂 CPU 档尝试(限时判定):SGLang 在 aarch64 CPU 上是否可支持
# 判据:venv 安装 → import → launch_server(--device cpu) 10 分钟内 /health 返回 200 = 可支持;
# 任一步失败:打印报错原文,结论 = 跳过引擎(用户决策:不能支持就跳过)。
# 注意:使用 /usr/bin/python3.12(Ubuntu 真身)。镜像默认 python3 软链指向损坏的解释器,
# 详见 A 臂 ascend-vllm-lmcache-nixl/scripts/11_install_cpu_stack.sh 头部说明。
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../versions.env
source "$SCRIPT_DIR/../versions.env"

RUNDIR="$SCRIPT_DIR/../run"
mkdir -p "$RUNDIR"
PYBIN=/usr/bin/python3.12
VENV="$HOME/venv-sg-cpu"
MODEL_DIR="$HOME/models/qwen2.5-0.5b"
PORT=30001

"$PYBIN" -m venv "$VENV" 2>/dev/null || { sudo apt-get install -y -q python3.12-venv; "$PYBIN" -m venv "$VENV"; }
# shellcheck disable=SC1091
source "$VENV/bin/activate"
pip install -U pip setuptools wheel -q

echo "== [1/4] 安装 sglang(CPU extra)"
if pip install "sglang[all_cpu]"; then
  echo "    all_cpu extra 安装成功"
else
  echo "    all_cpu extra 失败,降级尝试:本体 --no-deps + 最小依赖"
  pip install sglang --no-deps || { echo "[结论] sglang 包本体安装失败 → 跳过引擎"; exit 1; }
  pip install torch --index-url https://download.pytorch.org/whl/cpu || true
  pip install fastapi uvicorn transformers numpy pyzmq requests tqdm || true
fi

echo "== [2/4] import 测试"
python -c "import sglang; print('sglang import OK', getattr(sglang, '__version__', '?'))" || { echo "[结论] import 失败 → 跳过引擎"; exit 1; }

echo "== [3/4] 冒烟模型"
if [ ! -d "$MODEL_DIR" ] || [ -z "$(ls -A "$MODEL_DIR" 2>/dev/null)" ]; then
  pip install -q modelscope
  modelscope download --model "$MODEL_ID" --local_dir "$MODEL_DIR"
fi

echo "== [4/4] CPU 启动测试(健康检查最长 10 分钟)"
nohup python -m sglang.launch_server \
  --model-path "$MODEL_DIR" \
  --device cpu \
  --host 127.0.0.1 \
  --port "$PORT" \
  > "$RUNDIR/sglang_cpu.log" 2>&1 < /dev/null &
echo $! > "$RUNDIR/sglang_cpu.pid"

ok=0
for i in $(seq 1 60); do
  if curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then ok=1; break; fi
  PID=$(cat "$RUNDIR/sglang_cpu.pid")
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "[结论] 服务进程退出 → 不支持;日志末尾:"
    tail -n 30 "$RUNDIR/sglang_cpu.log"
    exit 1
  fi
  sleep 10
done

if [ "$ok" = "1" ]; then
  echo "[结论] SGLang aarch64 CPU:可支持(health 200),服务保留运行 PID=$(cat "$RUNDIR/sglang_cpu.pid")"
else
  echo "[结论] 10 分钟未就绪 → 视为不支持;日志末尾:"
  tail -n 30 "$RUNDIR/sglang_cpu.log"
fi
