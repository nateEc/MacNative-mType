# Spanish 650k 的独立词形与标点练习

`LANG-SPANISH-LARGE-46`，起点 `47577fc7d84504f030f3fe3ffde327f3cff11c20`。移除 Spanish 大档的词根／编号合成器，保留基本／1k／10k 全部数据。完整重写目标继续进行。

## 来源和边界

固定 Monkeytype 参考为 `91bd24bb8513785c7364cbea29296ff7adafac41`，只读取行为与自动聚合属性，不导出词值。参考有 646,579 个候选、162 个多词候选、77 个标点候选，与 239 个非字母候选不是同一指标。标点标量数量为 ASCII 连字符 62、U+2012 figure dash 11、冒号 1、斜线 2、左括号 2、右括号 1；纯字母词最长 23，带标点字段最长 26。旧合成器只追加 ASCII 连字符、假短语和重复字母，不能证明这些输入能力已交付。

独立字典来源为 [Kaikki 原始提取](https://kaikki.org/dictionary/rawdata.html)，2026-10-29 下载的两个快照：

| 版次／文件 | 字节 | SHA-256 |
| --- | ---: | --- |
| `https://kaikki.org/dictionary/downloads/es/es-extract.jsonl.gz` | 103,226,090 | `9bca1b9e3d4573825f196aff7aaa1a640503430df248f5a82f6602177abf6853` |
| `https://kaikki.org/dictionary/downloads/fr/fr-extract.jsonl.gz` | 736,596,796 | `823fa6f488e23850075747762d946c730c798d971e93b37fe645863b8f25e377` |

两个版本都仅接受 `lang_code=es`，并非混入法语词。保留合格词类和实际 forms 的 NFC 字面拼写、适用 form.source 标题；同词优先西语版，再以标题长度和字面序确定归属，不依赖遍历顺序。释义、例句、音频、图像和原始提取文件不进入应用。

固定 wordfreq 3.1.1 wheel SHA-256 为 `4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473`，Spanish 成员 `wordfreq/data/large_es.msgpack.gz` SHA-256 为 `14f326b4f68d517f9b8b99c1e26ef56a508d2dc8d0ee7a9e6e8732ddab1aa65e`。Case-folded 观察桶用于排序；无整体排名时取最罕见空格／连字符组成部分作为估计，未知排后。这不是纯频率截断，不声称词值、难度、分布等价。

可选池有 893,414 个小写字母形式、33,961 个含大小写形式、9,126 个多词 headword、885 个适用标点 headword。选取 646,337 个小写字母形式、España／México／Madrid 三个字面专名、162 个真实多词 headword、62 个 ASCII 连字符 headword、两个斜线缩写 y/o／s/n，共 646,566 个字面词形。

另有 **13 个明确编辑的书写／排版练习**：11 个真实后缀的 U+2012 变体，`neurorretroalimentaciones:` 主题标签和 `(amigo)` 括号示例。它们有真实基础词的来源映射，**不冒充字典原拼写或独立观察频率**。选集纯字母最长 24，主题标签提供单字段 26 字符边界；没有使用观察数据中的重复 jaja 串凑长度。括号示例采用平衡括号，因此左括号数为 1，与参考的 2 不同，保留字符类别不代表标点分布相同。

最终 646,579 个唯一候选，长度 1–26、大写项 3、多词项 162、标点项 77、非 ASCII 项 238,831；无数字。参考非 ASCII 项为 247,122，不伪装成相同统计。来源可能含提取错误、历史词形、借词、专名、口语及冒犯词；完整语言审校仍开放。

| 产物 | SHA-256 |
| --- | --- |
| 换行词数据 | `7e514588116a662b6260954c1287a68b16a2c50cad1e0b2eb62657edb98989b1` |
| 原生 Swift | `3decad6ed3e0d3b1bcd6bbb6985b898c2c05bb281dec0446a437a6f8be17866a` |
| 完整署名 | `9ec3b4cbb7c5f0487f6e9e40e272233df9954f0032baf24d9e19bb0d12d107f2` |
| 逐词来源映射 | `11aa61f95f2d6696a2755213a54ad507fb6f5e2cabe939bb80df253048737feb` |

## 复现与原生交付

版本 `kaikki-es-fr-20261029-wordfreq-3.1.1-large-v1`，准备器 SHA-256 `634237680c1d56c71206c4575887debda62ac11b938cdeaf85a572eb2b75f6b8`。准备需 Unicode 15.0.0（本次 Python 3.12）、msgpack 1.1.2，不联网或安装依赖。提供上述精确快照，执行：

```sh
python Scripts/prepare-spanish-large-corpus.py --spanish-dictionary /absolute/es-extract.jsonl.gz --french-dictionary /absolute/fr-extract.jsonl.gz --wordfreq-wheel /absolute/wordfreq-3.1.1-py3-none-any.whl --check
```

逐字节重建比较四个产物；标准库 `--check-bundled` 仅验证内部完整性。Kaikki 地址轮换，不能保证长期提供此精确快照；新哈希不匹配时拒绝，不静默接受新数据。应用运行无 Python／网络词典／msgpack 依赖，大档单独静态数组按需初始化。

基本 Spanish 197 项、1k 的 998 项及 10k 的 9,990 项哈希保持，默认多语使用基本池。保留语言 ID／预设／分享、es-ES 语音／百科、未知 Zipf；旧捕获提示、事件和冻结指标不回算，无数据库迁移。Lazy Latin 按固定有限替换表保留 ñ，将 á 等重音简化；关闭标点时按既有规则小写化专名。

About 新增来源署名，许可阅读器新增 Español · 650k；CC BY-SA 4.0 改编说明、wordfreq 完整来源及 646,579 项的四列来源映射随包交付。映射含版次、标题及证据种类，提供页面／贡献者历史 URL 模板；大型映射不整段挂入 SwiftUI 许可文本布局。发布署名与映射哈希独立固定，不能仅通过篡改 manifest 掩盖缺失归属。

## 验证记录

旧实现红测 `/tmp/typebar-spanish-large-red-20261029.log`：一项、三处预期失败，缺 el／niño／corazón；XCTest 3.888 秒，驱动 30.693 秒，输入哈希保持。首次接入定向 31 项因新测试错误假设 ñ 会简化而失败七处；固定参考 lazy-mode.ts 及 Spanish 无 additionalAccents 的元数据证明 ñ 应保留，产品转换规则保持，修正独立测试期望后复验。

准备器八项正常／优化自测通过，固定双字典和 wheel 的逐字节重建通过，记录 `/tmp/typebar-spanish-large-source-check-20261029.log`。有效对照、截断署名、删除来源项、改原生词值并重算文件哈希、错误字典 pin 的正常／优化反例均符合预期，见 `/tmp/typebar-spanish-large-negative-checks-20261029.json`。

修正预期后 `/tmp/typebar-spanish-large-green-v2-20261029.log` 的 31 项零失败／零跳过，XCTest 19.622 秒、驱动 42.307 秒，全部输入哈希保持。覆盖选集全量哈希及字符形状、小档全部字节、重音／ñ／专名规则、所有 162 个多词候选的有限结束与 No Space、所有 77 个标点候选的输入／删除／重复、26 字符单字段 Backwards、153 词续批及旧历史 JSON／模型／回放。

`/tmp/typebar-spanish-large-host-20261029.log` 一项通过，XCTest 2.766 秒、驱动 8.392 秒，输入哈希保持。真实 153 词全预览调用生产准备器，验证选择配置、实际拆词后成员、NSTextInputClient 首词输入、接收器身份和仅准备一次。NSHostingView 窗口隐藏、defaults 隔离、SwiftData 仅内存，无真实账号或用户数据写入。

独立 Debug getter 探针 `/tmp/typebar-spanish-large-lazy-probe-20261029.log` 通过：初始 RSS 5,792 KiB；1k 首次 0.000589 秒／6,288 KiB，10k 首次 0.004977 秒／7,280 KiB，大档首次 0.299120 秒／60,000 KiB，暖访问约 0.000000833 秒。仅证明小档不初始化大数组以及本机数据 getter 成本，不代表整应用冷启动、主线程切换、Release 或最低设备性能。

源码原创性自测／固定参考扫描、配置与语言元数据无漂移检查、47 个直接规格／119 个原生符号／17 个支持规格的行为链接审计通过。人工清单 1,439 项仅结构通过。已查看隐藏 About 的实际渲染图片，既有显著版权及新增 Spanish 署名／许可入口完整；不作为物理窗口／VoiceOver 终验。

人工验收新增两项均保持待验收；原生核心／隐藏宿主证据不代替物理键盘／IME、VoiceOver、语言质量、全部组合及完整性能验收。历史识别范围还余 112 个直接合成入口，声明数量之和 2,210,137，不是全量语言缺口数，goal 保持进行。

扩大回归 `/tmp/typebar-spanish-large-regression-20261029.log`：1,016 项零失败／零运行时跳过，XCTest 518.407 秒、驱动 532.484 秒；145 项必需固定源码证据通过，全部 1,318 个非 Markdown 输入哈希保持。范围包括 Spanish 大档及隐藏生产宿主、Spanish 元数据和既有语言池、生成／续批、多语、输入／修饰器、旧记录／回放、配置与固定源码轨迹，不代表完整客户端／服务端全量通过；历史完整客户端的 OCR 红例不因本轮选择性回归而改写。

Debug 包 `/tmp/typebar-spanish-large-package-20261029.log` 通过，驱动 43.481 秒，输入哈希保持；严格签名、13 个署名／来源资源逐字节比较及固定参考源码／包资源原创性边界通过。所有 Swift 编译、测试、数据探针和打包严格串行；没有启动可见 Typebar 主程序。工作流仅增加三个 Spanish 大档准备／完整性检查，未改触发条件或通知偏好。

推送前 GitHub 插件传输及 Python TLS 请求失败，随后 curl 对同一公开 API 的只读请求成功，没有关闭证书验证。确认零个打开的 PR、main 仍为 `8c52fb13028f82fd8e8718d55cb7ed65463b034e`、开发分支起点 `47577fc7`；Actions 总数 826，最新 main 运行 `39118939684` 成功。只集中推开发分支，不创建 PR、不手动重跑远端任务；Typebar／xctest／swift-test 进程均为零。
