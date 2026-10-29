# French 600k 的真实词形和 ASCII 撇号练习

`LANG-FRENCH-LARGE-45`，起点 `37349708c7613d711c74f09940cba83d4d8fb508`。移除 `frenchScaleLexicon` 的词根／编号及伪装统计，保留基本 French／1k／2k／10k。完整重写目标仍在进行。

## 来源与字符合同

参考固定在 Monkeytype `91bd24bb8513785c7364cbea29296ff7adafac41`，只取实际行为及自动聚合属性，不导出或复制词值。额外聚合确认 French 600k 的 34 个标点候选共使用 34 个 ASCII 撇号 `'`，没有其他标点／符号；旧原生合成器却只追加连字符，其数量统计不能证明这项键盘练习已经交付。

独立来源为 [Kaikki French edition 原始提取](https://kaikki.org/dictionary/rawdata.html)，文件 `https://kaikki.org/dictionary/downloads/fr/fr-extract.jsonl.gz`，2026-10-29 下载，736,596,796 字节，SHA-256 `823fa6f488e23850075747762d946c730c798d971e93b37fe645863b8f25e377`。流式解压，只接收 `lang_code=fr` 的适用词类及实际 forms，保留小写 NFC 字面拼写；有明确 inflection source 时保留其 Conjugaison 页，不拼接冠词、词根或词尾。解释、例句、图片、音频和原始 JSONL 不进入应用。

排名使用固定 wordfreq 3.1.1 wheel（SHA-256 `4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473`），French 成员 `wordfreq/data/large_fr.msgpack.gz` 的 SHA-256 为 `6f16cd80b9b66c5698ed002becea83ae30d0584c3205f1cf01714ad562c00c8b`。字母池有 1,558,967 个合格形式，按 case-folded 观察排名选 633,907 项，未知排名排后，并保留真实 33 字符长词 `cyclopentanoperhydrophénanthrènes`。`cœur` 保留 `œ`，不为排序改成 `coeur`；没有补重复字母。

Wiktionnaire 主要使用弯撇号 `’`，符合条件的 ASCII 撇号 headword 只有四个。准备器找到 88 个实际 wordfreq ASCII token 与已有词典 headword 对应（只在匹配键比较 `'`／`’`），选择其中排名靠前的 34 项，每项恰好一个 ASCII 撇号，无空格或其他标点。练习值直接来自观察 token，未通过替换词典标点制造；manifest 单列观察拼写、词典原拼写、源页标题及频率桶，例如 `aujourd'hui` 对应 `aujourd’hui`。这与字母形式的字面词典证据分开记录。

最终 633,941 项唯一候选，长度 1–33、大写／空格为 0、ASCII 撇号候选及字符各 34，非 ASCII 候选 323,380。与参考的非 ASCII 数量 282,793 不同，不能据部分形状一致宣称词值、词频、难度或分布等价。提取可能含错误、历史词形、专名、借词、口语或冒犯词，语言质量仍需审校。

| 产物 | SHA-256 |
| --- | --- |
| 换行分隔词数据 | `79b3b724dff36403f2a73b7f8434df803757cadebba39f835e29e659eb11996f` |
| 原生 Swift | `0a77f8961171289a61097d83255effd342e55e0b6f8f8617df9dd2daf277ba74` |
| 完整署名 | `e2d4a87a95d12baa8d237ef255238a6d182ebb599291fe6f69b4e6a72e4dd34d` |
| 逐词来源映射 | `5368a9228f493cdb70bd0f9ce60d88828a6e0b5f66ca268296ab5cd3b2cf4a31` |

## 原生交付与复现

版本 `kaikki-fr-20261029-wordfreq-3.1.1-large-v1`，准备器 SHA-256 `2970cd2a254bfa29af664f764ea60e577de5c35808db4990c53493438266299b`。源准备要求 Unicode 15.0.0（本次 Python 3.12）和 msgpack 1.1.2，不联网、不安装依赖；原生运行时无 Python／Node／msgpack／词典下载依赖。

提供精确哈希的两个输入，在本仓库执行 `python Scripts/prepare-french-large-corpus.py --dictionary /absolute/path/to/fr-extract.jsonl.gz --wordfreq-wheel /absolute/path/to/wordfreq-3.1.1-py3-none-any.whl --check`，逐字节重建比较四个产物。标准库 `--check-bundled` 仅作内部校验。Kaikki URL 会轮换，不是不可变版本；不匹配时拒绝最新文件，复现需要保存的该快照，不声称长期在线保留已经验证。

基本 French 174 项及三个小档的全部字节哈希保持，默认多语仍用基本 French；小档不解析单独的大档静态数组。ID／预设／分享、fr-FR 语音、French 百科、Lazy Latin、未知 Zipf 及旧捕获提示／事件／冻结成绩保持，无数据库迁移或历史回算。

About 新增来源署名，原生许可阅读器新增 Français · 600k。保留 [Wiktionnaire CC BY-SA 4.0 许可说明](https://fr.wiktionary.org/wiki/Wiktionnaire:Licence)、来源和 wordfreq 完整 release notices。633,941 个实际练习拼写均有来源页标题，附页面／贡献者历史 URL 模板；34 个观察拼写有额外对应证据。许可和映射随包逐字节检查，阅读器只加载小许可文档，不把 16MB 映射挂入 SwiftUI 文本布局。

## 验证

旧生产红测 `/tmp/typebar-french-large-red-20261029.log`：一项测试三处失败，缺 `le`／`être`／`cœur`，XCTest 3.570 秒、驱动 27.131 秒，输入哈希不变。下载首次 TLS 失败后同一公开输入重试成功，没有关闭证书校验或接受不完整文件；完整流式解析及精确源 SHA 随后通过。

接入 `/tmp/typebar-french-large-green-20261029.log`：29 项零失败／零跳过，XCTest 15.802 秒、驱动 129.100 秒（含编译），输入哈希不变。覆盖大档哈希／字符形状、小档全部字节、重音／`œ` 与 Lazy Latin／No Space、34 个 ASCII 撇号的实际输入／重复、真实长词的 Backwards／No Space、153 词续批／重复和旧合成提示的 JSON／模型／回放。

生产页面 `/tmp/typebar-french-large-host-20261029.log`：一项通过，XCTest 1.929 秒、驱动 26.636 秒，输入哈希不变。153 词触发真实全预览，观察器仍调用生产准备器，验证配置、候选成员、NSTextInputClient 首词输入、接收器身份和仅生成一次。窗口隐藏、defaults 隔离、SwiftData 仅内存，无真实账号或邮件，不是物理键盘／IME 终验。

独立 Debug 数据探针 `/tmp/typebar-french-large-lazy-probe-20261029.log`：起始 RSS 5,760 KiB；1k getter 0.004089 秒／7,072 KiB，10k getter 0.000061 秒／7,360 KiB，大档首次 0.295058 秒／64,624 KiB，再次约 0.000000833 秒。小档沿用原共享段；此结果只证明其不初始化 600k 和本机 getter 成本，不代表整应用冷启动、主线程首次切换、Release 或最低设备性能。

准备器八项自测在正常／`-O` 模式通过；固定源重建 `/tmp/typebar-french-large-source-check-20261029.log` 通过（73.759 秒）。有效产物对照通过；截断署名、删除源映射、修改原生词值后重算文件校验值，以及错误来源 pin 四类反例在两种模式均拒绝，记录 `/tmp/typebar-french-large-negative-checks-20261029.json`。发布署名／源映射哈希独立于可变 manifest，不把自洽校验值当来源证明。

最终扩大 `/tmp/typebar-french-large-regression-20261029.log`：1,002 项零失败／零运行时跳过，XCTest 503.355 秒、驱动 517.025 秒；145 项必需固定源码证据全部通过。冻结全部 1,311 个非 Markdown 输入，运行后哈希一致。范围包括新大档／实际宿主、现有 French 元数据身份及键盘、其他实际语言池、生成／续批、多语、输入／修饰器、回放／历史、配置和固定源码轨迹，不是完整客户端／服务端全量验收。

`/tmp/typebar-french-large-package-20261029.log` 的 Debug 包检查通过，驱动 41.987 秒、输入哈希不变；包括严格签名、11 个署名／来源资源逐字节比较、包内资源及固定参考原创边界。源码原创性自测／参考扫描、配置／语言元数据无漂移、47 个直接规格／119 个原生符号／17 个支持规格来源审计通过；人工清单 1,437 项仅结构检查，新增两项保持待验收。实际 About 截图已查看，原有显著版权及新增 French 署名／入口完整。

推送前没有打开 PR，main 为 `8c52fb13028f82fd8e8718d55cb7ed65463b034e`、开发分支基线为 `37349708`。Actions API 的系统 TLS 读取失败后，通过准备环境 Python 3.12 的只读请求确认总数仍 826，最新 main 运行 `39118939684` 成功。工作流仅增加三条大档准备／完整性检查，触发条件／通知偏好保持；只集中推开发分支，不创建 PR或重跑远端任务。所有 Swift 编译／测试／探针／打包串行完成，未启动 Typebar 主程序。

历史识别范围现余 113 个直接合成入口，声明数量之和 2,856,716，复核 `/tmp/typebar-french-large-remaining-synthetic-20261029.json`；这不是全量语言缺口数量。语言质量／分布、全部配置交错、实体输入／VoiceOver、旧二进制和完整性能仍开放，goal 保持进行。
