# 工具链固定版本更新（2026-09-28）

已将 .moonbit-version 更新为 0.10.14+7d59c7ec9。使用该固定工具链执行 moon update、moon fmt --check、严格全目标检查、JS 与 Wasm-GC 测试（各16项）、release JS 构建、moon info、生成接口差异检查、9项 Node 宿主输入检查，以及 JS/Wasm-GC 时间窗口示例，全部通过。

本次未重跑 PyEDFlib/NumPy 独立差分测试。本机只有 Python 3.14.4，而工作流固定 Python 3.12；在 Windows 临时目录安装 PyEDFlib 0.1.42 时，源代码包在生成安装元数据阶段失败。下方 2026-09-27 外部回执仅作为先前结果，不计入本次。

## Prior 0.2.1 validation (2026-09-27)

该次固定工具链见.moonbit-version，收据为 [LOCAL-CHECKS](evidence/external-bdf-20260927/LOCAL-CHECKS.json)。该次全目标静态检查、JS/Wasm-GC各16项测试及JS桥接构建通过；重新运行受转换修改影响的16组PyEDFlib合成矩阵（190项对照、2项CLI），结果另存该轮目录。

新外部BDF检查不修改源文件：20,000数字值、15,000物理值、12窗口/2,012样本，复制/选通道/裁剪/转plus写出由独立库重新读取56,000数字值。原始copy逐字节一致。参考库拒绝的另一文件保留拒绝记录，不计入通过量。来源与边界见 [EXTERNAL-BDF](docs/EXTERNAL-BDF.md)。

修复前转plus保留空patient字段，PyEDFlib拒绝输出；修复后采用标准未知子字段，非空原文本作为注释保存。新增回归同时覆盖EDF/BDF、空白和自由文本身份、数字值不变及plus幂等。

0.2.0事件窗口及PhysioNet独立证据保留在 [epoch](evidence/epoch-20260927/LOCAL-CHECKS.json)：128万个数字值、6万个物理值、30事件/66,840窗口样本，以及实际8事件17,664行CSV导出。窗口代码本轮未改，未重跑该完整外部记录。旧证据不得计作本轮重新执行。

本机验证不代表远程CI、公开发布或生产采用。外部BDF测试没有负数字值/间断BDF，负极值保留合成矩阵覆盖；设备Status只原样交换，不解释其专有位。
