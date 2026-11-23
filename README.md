# B 臂:SGLang + HiCache + NIXL(POSIX) 在昇腾 Atlas A3(910C) 上的可用性测试

测试目标:验证 SGLang 主线的分层 KV 缓存链路(HiCache,`--hicache-storage-backend nixl`,POSIX AIO 队列实现)能否在 GitCode CANN Lab 的 910C(A3)环境跑通,并记录不能跑通时的报错定位。

## 组件与版本锚点(CANN 9.1.0 套件,来自 SGLang 官方 Ascend 文档)

| 组件 | 作用 | 版本 |
|---|---|---|
| SGLang | 推理引擎(主线已原生含 NPU 平台代码与 HiCache NIXL 后端) | `SGLANG_REF=main`(建议固定 release tag 并记录 commit) |
| torch / torchvision / torch_npu | PyTorch 及昇腾适配插件 | 2.10.0 / 0.25.0 / 2.10.0.post6 |
| sgl-kernel-npu | SGLang 昇腾算子库 | 2026.9.0.post9(由 all_npu extra 拉取) |
| Triton-Ascend | 适配 NPU 的 Triton 后端 | 3.2.2(由 all_npu extra 拉取) |
| NIXL | 传输/存储库,POSIX 后端 = POSIX AIO 队列实现 | `NIXL_REF` |
| Python | **3.12 硬性要求**(镜像自带 3.11,用 conda 单独建环境) | 3.12 |

所有版本集中在 `versions.env`。**注意套件冲突**:本套件按 CANN 9.1.0 编写,与 A 臂(vllm-ascend,CANN 9.0.0)不同——两臂用两个独立环境,不要在同一容器混装两套 CANN。若镜像只有 9.0.0,先查 SGLang Ascend 文档版本表中 CANN 9.0.0 对应行,同步修改 `versions.env` 再安装。

## 使用顺序

```bash
bash scripts/00_env_check.sh        # 1. 体检(重点看 conda 是否可用、CANN 版本)
bash scripts/10_install_stack.sh    # 2. 安装全栈(conda 环境 sg-npu,耗时最长,可 nohup)
bash scripts/20_download_model.sh   # 3. ModelScope 下载 Qwen2.5-0.5B-Instruct

bash scripts/30_serve.sh            # 4. 启动(单卡);跑通后 TP=2 bash scripts/30_serve.sh
bash scripts/40_smoke.sh            # 5. 冒烟:同前缀两轮请求 + 命中计数 + 盘侧核对
bash scripts/90_teardown.sh         # 6. 按 PID 终止(禁止 pgrep/pkill)
```

## 上机前必须人工核对的三处(30_serve.sh 内有 TODO 注释)

1. **NIXL 后端的存储路径/预取参数如何传入**:对照你 x86 侧已跑通的 hicache+nixl 配置(lpl 的 sglang 脚本)与当前版本 server args 文档;
2. **`--hicache-io-backend`**:HiCache 的 layer-wise kernel 拷贝路径按 CUDA kernel 实现,NPU 上大概率需要 direct 路径;
3. **`--hicache-size` 语义**:0.5.23 起变为 KV+Mamba 共享预算(host 内存减半),设置前核对当前版本行为。

## 验证口径(每阶段都要留档)

1. 两轮同前缀请求的 total_time(第 2 轮应显著变快);
2. 命中计数器:/metrics、/get_server_info 与日志中的 hicache 命中/写入项;
3. 盘侧核对:`du -sh $HOME/sg_hicache_storage` 与进程读字节数对照(x86 侧出现过"盘侧读为进程读 2 倍"的未解释现象,同样的口径要在 NPU 上记录);
4. 版本清单与 sglang commit(10 号脚本末尾会打印)。

## 预期的坑(测不出来时的定位方向)

- **HiCache 设备侧代码**:L1(显存)↔ L2(host 内存)的拷贝与 KV 布局变换可能含 CUDA 专属假设,ascend attention 后端的 KV 布局与 CUDA 不同——报错优先查 `sglang/srt/mem_cache/` 相关栈帧;
- **sglang 在 910C 上的性能现状**:社区实测吞吐低于 vllm-ascend 一半以上,这是已知 gap,可用性测试先以"跑通+命中"为判据,性能对比另行设计;
- **NIXL pip 轮子**:若 aarch64 轮子缺 POSIX 后端,改 `NIXL_REF=<tag>` 源码构建(POSIX AIO 只依赖 glibc;测 io_uring 变体才需要 liburing-dev);
- **nixl 版本兼容**:历史上有 sglang + nixl 0.2.0 的挂起问题,版本以 sglang 文档为准并记录。

## 相关文档

- SGLang Ascend 安装(A3 套件表):https://lmsysorg.mintlify.app/docs/hardware-platforms/ascend-npus/getting-started/installation
- SGLang server args(--hicache-storage-backend):https://sgl-project.github.io/advanced_features/server_arguments.html
- HiCache 设计文档:https://docs.sglang.ai/advanced_features/hicache_design.html
- NIXL 仓库:https://github.com/ai-dynamo/nixl
- 昇腾 SGLang 大 EP 推理文章:https://www.hiascend.com/developer/techArticles/20250813-1
