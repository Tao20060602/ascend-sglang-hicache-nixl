#!/usr/bin/env bash
# 环境体检:只采集信息,不做任何修改。每个新环境先跑这个,输出留档进报告。
set -uo pipefail

echo "== NPU =="
npu-smi info || echo "[warn] npu-smi 不可用"

echo "== CANN / 驱动 =="
for f in \
  /usr/local/Ascend/driver/version.info \
  /usr/local/Ascend/ascend-toolkit/latest/version.cfg \
  /usr/local/Ascend/ascend-toolkit/latest/ascend_toolkit_install.info; do
  if [ -f "$f" ]; then
    echo "-- $f"
    cat "$f" 2>/dev/null || true
  else
    echo "-- $f (不存在)"
  fi
done

echo "== 系统 =="
uname -m
head -n 2 /etc/os-release 2>/dev/null || true
python3 --version 2>&1 || true
echo "-- 磁盘"
df -h /root "$HOME" 2>/dev/null | sed -n '1p;/\//p' || true
echo "-- 内存(GiB)"
free -g 2>/dev/null | sed -n '1,2p' || true

echo "== 工具链 =="
for t in git pip pip3 conda gcc ninja curl; do
  if command -v "$t" >/dev/null 2>&1; then
    echo "$t: $(command -v "$t")"
  else
    echo "$t: 缺失"
  fi
done
# B 臂硬性要求 python 3.12(CANN 9.1.0 套件);镜像若是 3.11,需 conda/uv 建 3.12 环境
if command -v conda >/dev/null 2>&1; then
  echo "conda: 可用 -> 安装脚本将创建 py3.12 环境"
else
  echo "conda: 缺失 -> 需先安装 Miniconda(SGLang NPU 套件要求 Python 3.12,镜像自带 3.11 不满足)"
fi

echo "== 已装 Python 包(相关项) =="
pip list 2>/dev/null | grep -Ei '^(sglang|nixl|torch|triton|torch-npu|torchvision|sgl-kernel)' || echo "(无相关包)"

echo "== 网络 =="
for u in https://mirrors.aliyun.com/pypi/simple/ https://download.pytorch.org/whl/cpu/ https://github.com https://www.modelscope.cn; do
  code=$(curl -s -o /dev/null -m 8 -w '%{http_code}' "$u" 2>/dev/null || echo timeout)
  echo "$u -> HTTP $code"
done

echo "体检完成。若 NPU/CANN/conda 项异常,先解决再执行 10_install_stack.sh。"
