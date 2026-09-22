# MoonEDF

纯 MoonBit 的 EDF、EDF+C/D、BDF、BDF+C/D 数据交换和记录检查工具。用于科研记录导入、通道筛选、事件时间线、整记录裁剪和 CSV 交换，保留不同通道的采样率和间断。只处理数据，不做生理信号诊断。

本地模块 `localreview/edf` 尚未发布。Node.js 只读写文件和处理命令参数；头解析、16/24 位样本、物理换算、TAL、时间操作和统计全部由 MoonBit 实现。

## 快速运行

需要 MoonBit 与 Node 24。原验证使用 moonc 0.10.12；
2026-09-22 已补显式 trait 方法声明，适配当前 0079 警告规则，
并在 moon 0.1.20260920 / moonc 0.10.14+7d59c7ec9 上重新核验。
旧证据保留日期，新工具链回执见 evidence/toolchain-20260922.json。

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
```

输出必须是新路径，不覆盖输入或既有文件。成功退出 0，错误写 stderr 并退出 2。格式由文件签名确定，不靠扩展名猜测；输出后缀请与格式一致。

## 已实现的常用流程

- 原始 EDF/BDF 和连续/间断 plus 格式；16/24 位 little-endian 补码；每通道单独的样本数、采样率、单位、正/负物理增益。
- TAL 分组注释、UTF-8、起点/可选持续时间、记录时间戳和间断检测；未知记录数 -1 仅在完整文件长度吻合时推断。
- `copy` 保留原始头的数值拼写、保留字段和 TAL 字节，只把未知记录数写成实际值。
- `select` 保留所选普通通道和全部注释通道，重组数据记录；使用通道索引，可区分同名标签。
- `crop` 以完整记录为单位，推进日期/时间（含跨日与闰年）、重新定位所有保留 TAL，不悄悄压缩间断。
- `plus` 将普通 EDF/BDF 提升为连续 plus，加入时间通道，保留样本与校准字段；原始 recording ID 作为注释保留，主 recording ID 改为标准 Startdate 形式。
- 原始数字值、物理值、每样本时间；Welford 均值/总体方差、RMS、极值、饱和端点和超范围计数；按数字值检查平坦段，绝不跨缺失时间拼接；多采样率长表 CSV。

## 命令与选项

读命令形式为 `node tools/edf.mjs COMMAND INPUT [OPTIONS.json]`，写命令为 `COMMAND INPUT OUTPUT [OPTIONS.json]`。`create OUTPUT OPTIONS.json` 从合成/自有数字样本新建文件，示例描述全部必需字段。

| 命令 | JSON 选项 |
|---|---|
| inspect / validate / annotations / gaps / copy / plus | 无 |
| stats | `signal`（普通通道索引） |
| channel | `signal`、可选 `start`/`count`（最多65536）、`physical`（默认false）；返回值和时间 |
| flat | `signal`、`minimum_samples`（至少2） |
| csv | `signals` 数组，可选 `first_record`/`records`/`physical`（默认true），最多一百万行 |
| select | `signals` 普通通道索引数组；不允许重复，注释自动保留 |
| crop | `first_record`、`records`（正数） |
| create | `format: "edf"或"bdf"`、`continuity: "plain"/"continuous"/"discontinuous"`、`duration`、`signals`、`records`；可选 date/time/patient |

CSV 不把通道上采样到共同网格，每行包含通道、标签、记录、样本索引、相对头起点的秒数、值和单位。标签/单位进行 CSV 引号转义。`validate` 检查容器、校准、TAL 与时间一致性；信号超范围和平坦段请另看 `stats`/`flat`，这些不等价于诊断结果。

普通 EDF/BDF 头只能表达整秒起点。如果裁剪会产生小数秒起点，先 `plus` 再 `crop`；库会明确拒绝无损表达不了的普通格式裁剪。plus 裁剪保留小数秒，更新头的整秒时间。事件在所保留记录内按原始位置保留，即使它的起点在记录之前，也可成为负的相对时间。

## 库 API

导入 `"localreview/edf" @edf`，公共接口见 `pkg.generated.mbti`。核心入口为 `parse_header`、`decode`、`create`、`parse_tals`/`encode_tals`；`Recording` 提供 `digital`/`physical`/`sample_time`/`sample_rate`、`select`/`crop`/`to_plus` 和分析方法。

`Signal` 描述数字与物理校准，`Record` 包含记录起点、每普通通道的整数样本数组和事件。`create` 自动加入 plus 注释通道。返回结构中的数组用于只读访问，不应原地修改内部元数据。失败抛出 `EdfError`，不会自动裁剪越界的物理值。

## 边界

- 完整文件最多256 MiB，4096通道、1000000记录、单记录8 MiB、1000000注释。整文件操作，不承诺恒定内存；上限是数据限额，不是进程内存保证。
- 日期覆盖1985–2084，按Gregorian日历推进；不猜测无效日期、未知时区或夏令时。时间是文件记录的本地壁钟时间。
- TAL 原始十进制时间在复制中保持；新建/重写采用100 ns精度，超精度修改报错。极长时间轴的Double运算仍受机器精度约束，相邻记录比较容差为100 ns。
- 普通头字段是可打印ASCII，注释是UTF-8。写头字段过宽会报错，不截断名称或校准精度。plus患者身份子字段保持原文，不自动改写或认证其行政语义。
- 支持注释专用的零时长记录，以及间断格式中每普通通道仅一个样本的零时长事件记录；后者没有定义采样率，调用 `sample_rate` 报错。
- BDF按24位交换格式处理，保留通道；不解释某个BioSemi设备的Trigger/Status专有位，也不模拟采集设备。
- 不含GDF、压缩容器、任意样本级裁剪、滤波/分类/医学决策。间断文件不会因老查看器只懂连续EDF而被自动压平。

## 独立验证与工程状态

```sh
python -m venv .venv
# 激活虚拟环境后：
python -m pip install -r tools/requirements.txt
python tools/differential.py
python tools/example-smoke.py
```

本机用pyedflib 0.1.42（底层EDFlib）/NumPy生成16组EDF/BDF、普通/plus、正负增益和两种记录长度，再读取MoonBit写出的文件；190项对照检查、2项CLI检查，以及README示例通过。该版本pyedflib明确拒绝EDF+D，本项目的间断时间线使用独立`struct`字节样本与官方布局核验，不能说成通过了C库间断读取验证。详情见 [验收](docs/REVIEW.md) 和 `evidence/`。

已提供三系统CI配置；本机运行了JS/Wasm-GC测试和所有目标的静态检查。尚未执行远程CI、公开仓库、发布Mooncakes或正式参赛提交。

MIT许可，独立实现并使用AI辅助开发，无复制第三方库源码。规范与编码前查重见 [PLAN](docs/PLAN.md)。pyedflib/EDFlib与NumPy仅开发对照依赖，不包装为本项目运行时核心。
