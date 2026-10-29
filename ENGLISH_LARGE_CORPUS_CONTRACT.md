# English 450k 的独立实际语料与原生许可

`LANG-ENGLISH-LARGE-43`，起点 `c6da502bed3a4c766ef44953fe8002bda5ed5137`。本项移除 English 大档的合成词根／字母编号构造器；完整重写目标保持进行。继续使用 SwiftUI／AppKit 原生界面及既有 SwiftData 历史存储，不嵌入网页或原版源码／词表。

## 来源、选集与复现

SCOWL `rel-2026.02.25` 固定提交 `7e99edab8e32f9f9ea2b15f249ca8d4d67237410`，大小 95，A/B/Z/C 拼写、变体等级 1、默认类别，启用内部连字符及原样句点。独立固定 wordfreq 3.1.1 wheel 的 SHA-256 为 `4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473`；English 成员哈希及全部参数存于 `Compatibility/english-large-corpus.json`。只使用参考项目的元数据／聚合和实际生成行为，不读取参考词值或据其选择替代词。

词典来源为 [en-wl/wordlist 固定提交](https://github.com/en-wl/wordlist/tree/7e99edab8e32f9f9ea2b15f249ca8d4d67237410)。准备环境需单独提供干净的该提交、固定 wheel 和 msgpack 1.1.2；在本仓库执行 `python Scripts/prepare-english-large-corpus.py --scowl-root /absolute/path/to/wordlist --wordfreq-wheel /absolute/path/to/wordfreq-3.1.1-py3-none-any.whl --check`。仅需安装包一致性检查时使用 `python3 Scripts/prepare-english-large-corpus.py --check-bundled`，无需来源文件或准备依赖。

准备器在干净固定 SCOWL 工作树之外新建临时数据库。每个词典拼写必须在固定库中逐字面存在，不能把默认去掉句点后的输出当成真实原拼写。282,593 个词典形式加上不在其折叠键中的 167,436 个实际观察 token，合为 450,029 个区分大小写的唯一候选；折叠键 443,056 个。观察 token 仅保留 ASCII 字母、长度 1–31，排除未获词典支持的四次以上同字母或整个短模式反复，共拒绝 629 项；不更改已被词典收录的拼写，也不补合成词凑数。

大小写 33,021 项，标点 176 项，含 44 个撇号、44 个连字符、88 个末尾句点形式；最小／最大长度 1／31。词典形式保留原有大小写，选择及排序规则固定。数量和字符形状一致不证明词值、词频、难度或分布等价；观察部分不是词典认证，低频碎片、姓名、品牌、借词和粗俗词仍可能存在，语言质量须另行审校。

| 产物 | SHA-256 |
| --- | --- |
| 换行分隔词数据 | `5ed42403f79db93db4db581fe3388d3992e7f648b630c8a14408a451176bbd59` |
| 生成 Swift | `cf4cdc05997b14696b5b55942eac6de89d4c64bab930d8f7e092ce9f9d9092c8` |
| 完整署名文档 | `7bbca2ef448dcad490837886e2f6748afe7e1315a887676299b2189d34abf048` |

`Scripts/prepare-english-large-corpus.py --self-test` 和 Python `-O` 各八项通过；校验使用显式错误而非可被优化删除的 assert。`--check-bundled` 只证明包内一致性，固定 SCOWL／wheel 的 `--check` 才逐字节重建比较 Swift、manifest 和署名。安装后的固定源检查 `/tmp/typebar-english-large-installed-source-check.log` 通过。准备器不联网、不安装依赖；msgpack 1.1.2 仅用于准备，原生运行时不依赖 Python／msgpack／下载。已有文件在任何写入前统一拒绝覆盖。

准备器 SHA-256 为 `94b7036c27bbff858fee1731a7925192aa39d3e6f96772ee16259cf66990523b`。仓库外篡改词值、来源 pin、虚假形状和截断署名四种反例在正常／优化模式均被拒绝，有效产物对照通过；错误 wheel 也在生成前拒绝且无输出。记录 `/tmp/typebar-english-large-integrity-negative-checks-v2.json` 与 `/tmp/typebar-english-large-prepared-wheel-failure.json`，不把包内一致性校验当作对来源真实性的独立认证。

## 原生交付与兼容

大词库为单独惰性静态 Swift 数组，小档数据及 200／1k／5k／10k／25k 的全部词字节哈希保持。`english450k` ID、分享／预设编码、en-US 语音、English 百科和未支持 Zipf 的合同保持。旧捕获提示、事件、目标字段及成绩保留，不因当前词库变化回算，也不增加存储迁移。

真实尾词、大小写／撇号／连字符／句点、Backwards／No Space 组合、153 词续批、重复和旧合成提示的存储／回放均有原生检查。Backwards 先倒转候选池再倒转所选词，尾词测试据已有语义选择反向 rank，未修改该生产行为。实际生产练习宿主用 153 词触发全预览异步路径，观察器仍调用真实准备器；检查发布配置、真实词库成员、原生 NSTextInputClient 首词输入及仅生成一次，不替换为固定测试提示。窗口保持隐藏，测试数据存于隔离 defaults 和内存 SwiftData，无真实账号或邮件。

独立新进程 Debug 数据探针 `/tmp/typebar-english-large-lazy-probe-20261029.log`：起始 RSS 5,792 KiB，基础 200 词初始化 0.000257 秒／6,176 KiB；首次大档 0.178227 秒／49,552 KiB；再次 getter 约 0.000001 秒。该结果仅证明本机数据 getter 的惰性边界和成本，不是整个应用冷启动、主线程首选延迟、Release 或最低设备性能验收。

## 显著署名与完整许可

SCOWL 的大档包含 UK Advanced Cryptics Dictionary；其来源许可要求应用内显著展示版权。实际 About 首屏在产品标识后显示来源全名及 `Copyright (c) J Ross Beresford 1993-1999. All Rights Reserved.`，并提供原生完整许可入口。阅读器默认打开 English 大档完整文档，可选择七个本地署名文件、选中文本、滚动及关闭；读取失败明确报错，不展示伪造成功状态。打开 About 只读署名元数据，不初始化大词库。

文档包含 SCOWL 完整 Copyright，原段 SHA-256 `090575a131b4260926c7a6b30a90aca0f5db5fbb5c46778e0c5855227bf6ebc3`，并保留完整 wordfreq 来源说明及 Typebar 改编选集的 CC BY-SA 4.0 署名。打包和包检查逐字节复制／比较该文件，不能只在仓库放许可却漏装应用。

后续 `LANG-GERMAN-SCALES-44` 在同一原生阅读器新增第八个 Deutsch 许可选项，并随包加入 German 的逐词来源映射；本节原始七个文档及首次包检查保留为本项落地时的历史范围，新增部分另见 GERMAN_SCALES_CORPUS_CONTRACT.md。

`LANG-FRENCH-LARGE-45` 随后新增第九个 Français · 600k 许可选项及其随包来源映射，见 FRENCH_LARGE_CORPUS_CONTRACT.md；各阶段包检查数量按当时范围保留。

`LANG-SPANISH-LARGE-46` 随后新增第十个 Español · 650k 许可选项及其来源映射，见 SPANISH_LARGE_CORPUS_CONTRACT.md；English 显著版权保持。

`LANG-ROMANIAN-SCALES-47` 随后新增第十一个 Română 规模词库许可及来源映射，见 ROMANIAN_SCALES_CORPUS_CONTRACT.md；阶段包检查数量保留当时范围。

`LANG-POLISH-SCALES-48` 随后新增第十二个 Polski 规模词库许可及来源映射，见 POLISH_SCALES_CORPUS_CONTRACT.md；English 显著版权位置保持。

隐藏 NSHostingView 不导出有效 AX 树，首次测试的空标签失败不说明界面缺字。改为识别实际缓存像素，不给 Vision 预设词表或自定义词；About 中来源全名与完整版权行均须原样识别且位于首屏上半部。阅读器先检查实际文档开头，再通过真实 NSScrollView 滚至末尾检查最终 DOI；完整文档字节另由读取／打包／源复现保护。截图 `/tmp/typebar-large-english-about.png`、`/tmp/typebar-large-english-license-reader.png` 和末尾截图已保留；人工查看首两张确认实际内容。此证据不等于实体窗口、VoiceOver、按钮打开 sheet 的完整人工验收。

## 验证与开放范围

旧生产语料的真实红测 `/tmp/typebar-english-large-native-red-20261029.log`：一项测试四处失败，缺真实词及错误哈希；接入后同一数据测试通过。随后九项大词库行为检查通过。新增测试编译问题、Backwards 夹具错误、隐藏 AX 空树及错误地用 25 词期待全预览准备的测试失败均单列，不冒充新的产品红例；生产准备阈值仍为超过 100 词。

最终定向 `/tmp/typebar-english-large-focused-green-v2-20261029.log`：26 项零失败／零跳过，XCTest 4.765 秒、驱动 26.293 秒。实际练习宿主 `/tmp/typebar-english-large-host-v3-20261029.log`：一项通过，1.658 秒、驱动 23.616 秒。各轮非 Markdown 输入哈希不变。

最终扩大 `/tmp/typebar-english-large-regression-20261029.log`：975 项零失败／零运行时跳过，XCTest 459.368 秒、驱动 472.769 秒；145 项必需固定源码证据全部通过。冻结全部 1,296 个非 Markdown 输入，运行后哈希一致。范围含新大档／许可／实际宿主、其他实际语言池、生成／续批、多语、修饰器／输入、回放／历史、配置与既有固定源码轨迹，不等于完整客户端或服务端全量验收。

`/tmp/typebar-english-large-package-20261029.log` 的 Debug 包检查通过，驱动 37.132 秒，全部非 Markdown 输入哈希不变；包含严格签名、七个署名文件逐字节比较、包内资源边界及固定参考原创边界。源码原创性自测／参考扫描、配置与语言元数据重建、47 个直接规格／119 个原生符号／17 个支持规格的来源审计通过。人工清单 1,433 项只验证结构，新增两个人工场景保持待验收。

推送前核对没有打开 PR，main 仍为 `8c52fb13028f82fd8e8718d55cb7ed65463b034e`、开发分支基线为 `c6da502b`；Actions 仍为 826 次，最新 main 运行 `39118939684` 成功。只安排一次经过本地验证的开发分支推送，不修改触发条件／通知设置，不主动重跑远端任务。工作流仅增加三条大词库准备／完整性检查。所有 Swift 构建／测试／数据探针及包检查按顺序完成，未启动 Typebar 主程序。

同历史清单范围仍余 117 个直接合成语言入口，声明数量之和 3,740,882，不是完整缺口数量。其他语言、全部设置／修饰器交互、语言质量／难度／分布、物理键盘／IME、VoiceOver、完整 Release 性能及旧二进制仍未完成。此前完整客户端 6,751 项仍保留其一处 OCR 红基线，不能用本次定向或扩大检查改写为全量通过。
