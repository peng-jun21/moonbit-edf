# 0.2.0 当前验证（2026-09-27）

固定工具链为 `.moonbit-version`；本机 Moon0.1.20260904、moonc0.10.12+1634b282e、Node24.11.0。全目标静态检查、格式与API生成通过；JS15项、Wasm-GC15项核心测试全部通过。3项新增事件窗口测试覆盖同名事件索引、多采样率总预算、间断/头尾缺失和小数秒右开边界。

[LOCAL-CHECKS](evidence/epoch-20260927/LOCAL-CHECKS.json)保存实际命令、原始日志、LF标准化源码哈希与实际桥接产物哈希；[public-eeg](evidence/epoch-20260927/public-eeg.json)保存PyEDFlib0.1.42独立对照。105项任务核对128万个数字值、6万个物理值、30事件/66,840窗口样本及6个应拒绝输入；完整下载已与PhysioNet官方SHA256SUMS匹配。

真实命令行例子导出8个事件、17,664行样本，重新读取CSV核对行数、哈希和右开区间，manifest保留于 [export-manifest](evidence/epoch-20260927/export-manifest.json)。原EDF与导出CSV不随源码分发，复现见 [PUBLIC-EEG](docs/PUBLIC-EEG.md)。

本轮曾发现浮点秒相加导致端点多收样本；最初对照代码也沿用了同种浮点加法，之后改用独立Decimal边界而暴露差异，核心改成整数tick相加后通过。新增测试的语法和合成首记录时间约束错误也已修复。不得把最早成功日志当作已修复版本。

既有EDF/BDF合成矩阵和间断参考位于历史evidence，因原编解码未改，本轮未重跑全部历史矩阵或基准。CI固定Linux工具链；公开数据检查仅配置在手动workflow_dispatch，远程CI未运行。Windows本地通过不等于其它系统已验收。没有生产采用、临床验证或赛事通过结论。
