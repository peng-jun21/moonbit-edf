# MoonEDF · 0.2.2

项目仓库：[https://github.com/peng-jun21/moonbit-edf](https://github.com/peng-jun21/moonbit-edf) 本地交付版 0.2.2 仅补全已存在公开仓库的包元数据地址，算法未改；尚未推送或发布，公开版仍为 0.2.1。

评审/首次使用请先看[实际任务、替代方案与可运行证据](REVIEW.md)：读取EDF/BDF与TAL事件，按事件前后时间选多通道样本，导出带原记录号、采样时间和物理单位的长表。

纯 MoonBit 的 EDF、EDF+C/D、BDF、BDF+C/D 数据交换和记录检查工具。用于科研记录导入、通道筛选、事件时间窗提取、整记录裁剪和 CSV 交换，保留不同通道的采样率和间断。只处理数据，不做生理信号诊断。

已发布模块为 `peng-jun21/edf@0.2.1`，本地 0.2.2 尚未发布。Node.js 只读写文件和处理命令参数；头解析、16/24 位样本、物理换算、TAL、事件窗口、时间操作和统计全部由 MoonBit 实现。

## 本轮公开输入与核心扩展

新增纯MoonBit `event_window`：按注释索引提取多通道事件段，共享容量、默认拒绝缺失时间，并修复小数秒相加导致右端多收样本的问题。以PhysioNet固定EDF+记录与PyEDFlib对照，覆盖64通道、30事件、128万个数字样本和6万个物理值。可运行导出、数据署名和限制见 [PUBLIC-EEG](docs/PUBLIC-EEG.md)，[申报草稿](PROPOSAL.md)对应当前换题项目；是否获准换题尚未核实。

0.2.1修复普通记录转plus时患者标识不符合结构要求的问题：plus头写未知子字段，原非空患者/记录标识保存在注释中，转换不是匿名化。外部MNE四通道BDF通过PyEDFlib全量读取与四种写出对照；另一个被参考库拒绝的输入单独记录，不计通过。见 [外部BDF与修复](docs/EXTERNAL-BDF.md)。

## 快速运行

当前固定 MoonBit 版本见 `.moonbit-version`，Node24。旧0.1.0工具链/合成验证记录保留在evidence；0.2.1当前检查见 [TESTING](TESTING.md)，不混用历史版本成绩。

```sh
moon check --target all --deny-warn
moon test --target js --deny-warn
moon test --target wasm-gc --deny-warn
moon build --target js --release --deny-warn
node tools/edf.mjs create demo.edf examples/create.json
node tools/edf.mjs inspect demo.edf
node tools/edf.mjs annotations demo.edf
node tools/edf.mjs stats demo.edf examples/stats.json
node tools/edf.mjs flat demo.edf examples/flat.json
node tools/edf.mjs select demo.edf selected.edf examples/select.json
node tools/edf.mjs crop demo.edf cropped.edf examples/crop.json
node tools/edf.mjs csv demo.edf examples/csv.json > samples.csv
node tools/edf.mjs window demo.edf examples/window.json
node tools/edf.mjs window-csv demo.edf examples/window-csv.json > window.csv
moon run examples/time_window --target js
```

输出必须是新路径，不覆盖输入或既有文件。成功退出 0，错误写 stderr 并退出 2。格式由文件签名确定，不靠扩展名猜测；输出后缀请与格式一致。

## 已实现的常用流程

- 原始 EDF/BDF 和连续/间断 plus 格式；16/24 位 little-endian 补码；每通道单独的样本数、采样率、单位、正/负物理增益。
- TAL 分组注释、UTF-8、起点/可选持续时间、记录时间戳和间断检测；未知记录数 -1 仅在完整文件长度吻合时推断。
- `copy` 保留原始头的数值拼写、保留字段和 TAL 字节，只把未知记录数写成实际值。
- `select` 保留所选普通通道和全部注释通道，重组数据记录；使用通道索引，可区分同名标签。
- `crop` 以完整记录为单位，推进日期/时间（含跨日与闰年）、重新定位所有保留 TAL，不悄悄压缩间断。
- `plus` 将普通 EDF/BDF 提升为连续 plus，加入时间通道，保留样本与校准字段；原始 patient/recording ID 非空时作为注释保留，plus patient写X X X X、recording改为标准Startdate形式，不从自由文本推断身份子字段。
- 原始数字值、物理值、每样本时间；Welford 均值/总体方差、RMS、极值、饱和端点和超范围计数；按数字值检查平坦段，绝不跨缺失时间拼接；多采样率长表 CSV。
- `window` 按秒查询半开时间区间，返回数字值、物理值、原始记录/样本索引及区间内的已知间断；`window-csv` 直接导出多个通道的该区间，不插值、不补零、不压缩时间。支持部分记录、不同采样率与零时长事件记录。

## 命令与选项

读命令形式为 `node tools/edf.mjs COMMAND INPUT [OPTIONS.json]`，写命令为 `COMMAND INPUT OUTPUT [OPTIONS.json]`。`create OUTPUT OPTIONS.json` 从合成/自有数字样本新建文件，示例描述全部必需字段。

| 命令 | JSON 选项 |
|---|---|
| inspect / validate / annotations / gaps / copy / plus | 无 |
| stats | `signal`（普通通道索引） |
| channel | `signal`、可选 `start`/`count`（最多65536）、`physical`（默认false）；返回值和时间 |
| window | `signal`、`start`/`end`（相对原始头起点的秒数），可选 `max_samples`（默认65536，最多1000000）；左闭右开，超限报错 |
| window-csv | `signals`（非空且无重复）、`start`/`end` 秒数，可选 `physical`（默认true）、`max_samples`（所有通道共享，默认65536，最多1000000） |
| flat | `signal`、`minimum_samples`（至少2） |
| csv | `signals` 数组，可选 `first_record`/`records`/`physical`（默认true），最多一百万行 |
| select | `signals` 普通通道索引数组；不允许重复，注释自动保留 |
| crop | `first_record`、`records`（正数） |
| create | `format: "edf"或"bdf"`、`continuity: "plain"/"continuous"/"discontinuous"`、`duration`、`signals`、`records`；可选 date/time/patient |

CSV 不把通道上采样到共同网格，每行包含通道、标签、记录、样本索引、相对头起点的秒数、值和单位。标签/单位进行 CSV 引号转义。`validate` 检查容器、校准、TAL 与时间一致性；信号超范围和平坦段请另看 `stats`/`flat`，这些不等价于诊断结果。

时间查询中的 `start`/`end` 单位是**秒**，不同于 `channel` 命令的 `start` 样本索引。`window-csv` 按请求通道分组，每组保留源文件顺序，不强行对齐多采样率；CSV没有间断占位行，需核查缺失时间时同时查看 `window` 的 `gaps`。完整使用示例、端点规则及空结果的解释见 [时间窗口指南](docs/TIME-WINDOWS.md)。

普通 EDF/BDF 头只能表达整秒起点。如果裁剪会产生小数秒起点，先 `plus` 再 `crop`；库会明确拒绝无损表达不了的普通格式裁剪。plus 裁剪保留小数秒，更新头的整秒时间。事件在所保留记录内按原始位置保留，即使它的起点在记录之前，也可成为负的相对时间。

## 库 API

导入 `"peng-jun21/edf" @edf`，公共接口见 `pkg.generated.mbti`。核心入口为 `parse_header`、`decode`、`create`、`parse_tals`/`encode_tals`；`Recording` 提供 `digital`/`physical`/`sample_time`/`sample_rate`、`time_window`/`window_csv`、`select`/`crop`/`to_plus` 和分析方法。

`Signal` 描述数字与物理校准，`Record` 包含记录起点、每普通通道的整数样本数组和事件。`create` 自动加入 plus 注释通道。返回结构中的数组用于只读访问，不应原地修改内部元数据。失败抛出 `EdfError`，不会自动裁剪越界的物理值。

## 边界

- 完整文件最多256 MiB，4096通道、1000000记录、单记录8 MiB、1000000注释。整文件操作，不承诺恒定内存；上限是数据限额，不是进程内存保证。
- Node对数据和选项在同一文件描述符上检查并有界读取；选项JSON最多1,000,000字节。
  检测到读取期间增长或缩短则拒绝；不提供文件锁或同长度覆盖写的一致快照，请读取稳定文件。
- 日期覆盖1985–2084，按Gregorian日历推进；不猜测无效日期、未知时区或夏令时。时间是文件记录的本地壁钟时间。
- TAL 原始十进制时间在复制中保持；新建/重写采用100 ns精度，超精度修改报错。极长时间轴的Double运算仍受机器精度约束，相邻记录比较容差为100 ns。
- 普通头字段是可打印ASCII，注释是UTF-8。写头字段过宽会报错，不截断名称或校准精度。既有plus文件的身份子字段保持原文；普通转plus按上述未知字段策略处理，不认证行政语义。
- 支持注释专用的零时长记录，以及间断格式中每普通通道仅一个样本的零时长事件记录；后者没有定义采样率，调用 `sample_rate` 报错。
- BDF按24位交换格式处理，保留通道；不解释某个BioSemi设备的Trigger/Status专有位，也不模拟采集设备。
- 时间窗口为内存结果或CSV，不重写EDF/BDF头、不改变原始索引和时间轴；窗口限额是样本数量限额，不是总进程内存保证。
- 不含GDF、压缩容器、任意样本级裁剪后重写EDF/BDF、滤波/分类/医学决策。间断文件不会因老查看器只懂连续EDF而被自动压平。

## 独立验证与工程状态

```sh
python -m venv .venv
# 激活虚拟环境后：
python -m pip install -r tools/requirements.txt
python tools/differential.py
python tools/test-time-window.py
python tools/example-smoke.py
node tools/test-host-input.mjs
```

本机用pyedflib 0.1.42（底层EDFlib）/NumPy生成16组EDF/BDF、普通/plus、正负增益和两种记录长度，再读取MoonBit写出的文件；190项对照检查、2项CLI检查，以及README示例通过。该版本pyedflib明确拒绝EDF+D，本项目的间断时间线使用独立`struct`字节样本与官方布局核验，不能说成通过了C库间断读取验证。详情见 [验收](docs/REVIEW.md) 和 `evidence/`。

时间窗口专项使用独立定宽字节构造和逐样本枚举：10个小型EDF/BDF样例，另含65537样本限额样例；1008项批量检查、5项真实CLI检查。覆盖精确端点及相邻浮点数、多采样率、负增益、间断、零时长同刻样本、允许的微小时间回退、共享CSV限额和引号转义。结果见 `evidence/window-reference.json`；这不是第三方C库对间断格式的验证。

已提供三系统 CI 配置；本机运行了 JS/Wasm-GC 测试和所有目标的静态检查。公开版 0.2.1 的仓库、Mooncakes 和远程 CI 已核实，记录见下方公开状态；本地交付版 0.2.2 尚未推送或发布，报名表及审核结果尚未核实。

MIT许可，独立实现并使用AI辅助开发，无复制第三方库源码。规范与编码前查重见 [PLAN](docs/PLAN.md)，验证工具许可和合成样例来源见 [SOURCES](docs/SOURCES.md)。pyedflib/EDFlib与NumPy仅开发对照依赖，不包装为本项目运行时核心。

## 本地验收与公开交付（2026-09-28）

核心实现使用 MoonBit；[固定编译器](.moonbit-version)为 `moonc 0.10.14+7d59c7ec9`。先按本文安装宿主依赖、运行 `moon update`，再从仓库根目录执行以下与 [CI](.github/workflows/ci.yml) 对齐的检查；可运行任务和适用边界见本文前面的示例与说明。

```sh
moon check --target all --deny-warn
moon test --target js --deny-warn
moon test --target wasm-gc --deny-warn
moon build --target js --release --deny-warn
moon package
```

跨平台复核（2026-09-28，本地 Ubuntu-D 26.04 WSL2）：从当时的源码归档全新解包，固定 `moonc 0.10.14+7d59c7ec9` 下通过 `moon update`、`moon fmt --check`、`moon info`、严格检查、JS/Wasm-GC 测试及 JS release 构建；Node 24.21.0 跑通本仓一条宿主入口。本次补记仅修改文档，代码与 CI 未变；复核日志在本地交接包中，公开提交后的 GitHub Actions 仍须单独核对。

本地核验：JS/Wasm-GC 各 16 项测试、release 构建和 CLI 示例通过；隔离 Python 3.12 环境以 pyEDFlib 0.1.42 重新核对外部 BDF，结果见 [本轮回执](evidence/acceptance-20260928/EXTERNAL-BDF-RECHECK.json)。`moon package` 已完成离线打包预检，它不等于已发布到 Mooncakes。

**公开状态（2026-09-29 核对）**：GitHub [公开仓库](https://github.com/peng-jun21/moonbit-edf)、[Mooncakes 0.2.1](https://mooncakes.io/docs/peng-jun21/edf@0.2.1) 已可访问；[CI 成功记录](https://github.com/peng-jun21/moonbit-edf/actions/runs/36561847814) 对应 `31ddb71bc637`。本次材料更新尚未推送；该远端 CI 对应所列公开提交。报名表一致性及赛事审核结果尚未核实。
