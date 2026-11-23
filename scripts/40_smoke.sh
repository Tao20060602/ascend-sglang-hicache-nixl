#!/usr/bin/env bash
# 冒烟测试:等待服务就绪 -> 同一长前缀两轮请求 -> 对比时延并抓取缓存计数
# 判读口径:第 2 轮应显著变快;命中必须双源核对(计数器 + 盘侧字节数,x86 侧教训)。
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PORT="${PORT:-30000}"
BASE="http://127.0.0.1:$PORT"
RUNDIR="$SCRIPT_DIR/../run"
STORAGE_DIR="${STORAGE_DIR:-$HOME/sg_hicache_storage}"

echo "==> 等待服务就绪(最长 30 分钟,模型首次加载较慢)..."
ok=0
for i in $(seq 1 180); do
  if curl -sf "$BASE/health" >/dev/null 2>&1; then ok=1; break; fi
  sleep 10
done
if [ "$ok" != "1" ]; then
  echo "[错误] 服务未就绪。日志末尾:" >&2
  tail -n 40 "$RUNDIR/sglang.log" >&2 || true
  exit 1
fi
echo "服务就绪。"

# 构造约 2k token 的公共前缀
LINE="The quick brown fox jumps over the lazy dog. Ascend hierarchical KV cache smoke test."
PREFIX=""
for i in $(seq 1 120); do PREFIX+="$LINE "; done

chat() {
  local question="$1" out="$2"
  curl -s -o "$out" -w '%{time_total}' \
    "$BASE/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"$MODEL\", \"max_tokens\": 64, \"messages\": [{\"role\": \"user\", \"content\": \"$PREFIX $question\"}]}"
}

MODEL=$(curl -s "$BASE/get_model_info" 2>/dev/null | grep -o '"model_path"[^,]*' | head -n1 || true)
MODEL="${MODEL:-test}"

echo "==> 第 1 轮(冷:写入前缀)"
T1=$(chat "What color is the fox? Answer in one word." "$RUNDIR/resp1.json")
echo "    total_time = ${T1}s,响应: $(head -c 200 "$RUNDIR/resp1.json")"

echo "==> 第 2 轮(热:同一前缀,不同问题)"
T2=$(chat "What animal jumps? Answer in one word." "$RUNDIR/resp2.json")
echo "    total_time = ${T2}s,响应: $(head -c 200 "$RUNDIR/resp2.json")"

echo "==> 缓存计数(尽力抓取)..."
curl -s "$BASE/metrics" 2>/dev/null | grep -Ei 'hicache|cache.*(hit|store|load)' | head -n 20 || true
curl -s "$BASE/get_server_info" 2>/dev/null | grep -Ei 'cache|hit' | head -n 20 || true
grep -Ei 'hit|hitrate|store|load' "$RUNDIR/sglang.log" 2>/dev/null | tail -n 10 || true

echo "==> 盘侧核对:"
du -sh "$STORAGE_DIR" 2>/dev/null || echo "STORAGE_DIR 不存在(若后端未落盘,记录进报告)"

awk -v a="$T1" -v b="$T2" 'BEGIN{ if (b+0 < a+0) printf "结论: 第2轮比第1轮快 %.2f%%,符合命中预期;请再核对上面计数器非 0。\n", (a-b)/a*100; else printf "结论: 第2轮未变快,前缀缓存未命中——按 README 的定位清单排查。\n" }'
