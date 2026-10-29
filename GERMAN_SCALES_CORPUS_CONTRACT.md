# German 三档的字面词形、输入和来源署名

`LANG-GERMAN-SCALES-44`，起点 `3ae7796d14553f7df485b51a7f1a804b9f1a6ce0`。移除 German 1k／10k／250k 的合成词根、字母编号及伪装统计，接入独立实际来源。完整重写仍在进行，其他语言和人工验收不因本项通过而关闭。

## 固定来源与选集

仅从 Monkeytype 固定提交 `91bd24bb8513785c7364cbea29296ff7adafac41` 读取元数据和实际生成器行为，不读取或复制其词值。`frontend/src/ts/test/words-generator.ts` 924–938 行确认 German 关闭随机标点时不统一转小写；既有原生实现保持该行为。Swiss German 的基本 200 词派生不改，其另外两档占位内容也不在本项中宣称完成。

字面来源是 [Kaikki 的 German edition 原始提取](https://kaikki.org/dictionary/rawdata.html)，下载文件 `https://kaikki.org/dictionary/downloads/de/de-extract.jsonl.gz`，2026-10-29 取得，310,139,416 字节，SHA-256 `04f07bd9d54277d79e0c6e1478fe86a13ac9db7c292cdec13b961b59a505f79b`。只接收 `lang_code=de` 的适用词类，保留原始 NFC Latin 字母词形、已有大小写、变音符号与 ß；不把冠词栏拼到词前，不从后缀制造词。多词表达／标点候选仅来自现有 headword，字母候选也可来自其实际 inflection forms。正文、解释、例句、图片及音频不进入应用。

该 URL 会轮换，不能将 URL 本身当作不可变版本。复现必须提供上述精确哈希的保存快照，不能遇到不匹配就接受最新文件。此处不声称长期在线保留或固定 dump／提取日期已经独立验证。当前来源保存于 `/tmp/typebar-german-de-extract-20261029.jsonl.gz`，准备时流式解压，不向仓库或安装包塞入完整原始 JSONL。

排序参考既有 wordfreq 3.1.1 wheel（SHA-256 `4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473`），German 成员 `wordfreq/data/large_de.msgpack.gz` 的 SHA-256 为 `8ef04d3f4a28fb48d800d25fa80a96d90a5f80c8496c9a453f99f887c6ad3c12`。固定 wheel 的 `preprocess.py`／`tokens.py` 明确使用 Unicode case-fold；因此只在排名键把 `Straße` 对应到观察键 `strasse`，练习目标仍是字面的 `Straße`。不同大小写／ß 与 ss 形式可能共享观察依据，不冒充各自独立实测频率。

最终可用池包括 903,490 个字母形式、14,051 个多词 headword 和 10,523 个标点 headword。每档按长度上限和排名选取，并保留一个实际存在的上限长度词，维持长词练习能力，不补重复字母。多词表达缺少整体观察时，以最稀少组成词估算排序，不宣称实测表达频率。标点部分为明确的独立编辑选集，均须逐字面存在于来源；1k 包括 `E-Mail`／`usw.`／`wenn’s`，10k 的 25 项见 manifest。没有修改词的拼写以凑统计。

| 档位 | 唯一数量／长度 | 大写／非 ASCII | 标点／多词 | 词数据 SHA-256 |
| --- | --- | --- | --- | --- |
| 1k | 988／2–17 | 415／78 | 3／8 | `d2cea3f886167e249b438177ee00bcc478e89220e1650b6c608e4028a526ca16` |
| 10k | 9,994／2–27 | 5,045／1,432 | 25／40 | `8f7574893ed17df50c58801441f159a0e04d3622bb3c76effe3f21fcc82e94c6` |
| 250k | 239,243／2–35 | 142,421／47,774 | 0／0 | `ca74b2b71791f169de73afc0c29d948ae394117e3bff05a212ae712c34bdcaac` |

上限词分别为 `unterschiedlichen`、`Weltgesundheitsorganisation`、`Elektrizitätsversorgungsunternehmen`，均有来源页映射。与参考的大小写／非 ASCII 统计不同，不能将数量和部分字符形状当成内容、难度或分布等价。词典提取仍可能包含错误、旧拼写、专名、外来词、冒犯词及不适合该档难度的词形；独立语料替换不等于语言质量终验。

## 准备、署名与原生边界

版本 `kaikki-de-20261029-wordfreq-3.1.1-v1`。准备器 `Scripts/prepare-german-frequency-corpus.py` SHA-256 `9d503051cb8b59af41bbce365e45212eee27cbfb90ec3b53bca3d66a0fb9316d`；源准备要求 Unicode 15.0.0（本次 Python 3.12）及 msgpack 1.1.2。工具不联网、不安装依赖；原生运行时不依赖 Python、msgpack、Node、原始词典或网络。可执行：`python Scripts/prepare-german-frequency-corpus.py --dictionary /absolute/path/to/de-extract.jsonl.gz --wordfreq-wheel /absolute/path/to/wordfreq-3.1.1-py3-none-any.whl --check`，逐字节比较五个生成物。标准库 `--check-bundled` 只作内部完整性检查，不能替代源复现。

小档各有独立静态段，大档另置惰性 Swift 文件，不因选择 1k 而解析 250k。基本 German 的 200 词字节哈希保持 `5096ce3837e415e877b0ac35f88dd10d63b969eee6708c063b9d6c61266f4d91`；原有 German／Swiss German 基本池、默认多语集合、ID／预设／分享、de-DE 语音、German 百科、Lazy Latin 与未知 Zipf 合同保持。旧捕获提示、事件和冻结成绩不按新词库回算，无存储迁移。

About 显示 German Wiktionary contributors／Kaikki／Wiktextract 的署名，原生许可阅读器新增 Deutsch 文档。改编选集采用 CC BY-SA 4.0，并保留 [German Wiktionary 许可说明](https://de.wiktionary.org/wiki/Wiktionary:Lizenzbestimmungen)、历史 CC BY-SA 3.0 与当前 4.0 链接及 wordfreq 完整 release notices。来源方法论文链接为 [Wiktextract, LREC 2022, 1317–1325](https://aclanthology.org/2022.lrec-1.140/)。

`Resources/GermanCorpusSources.txt` 为 239,308 个选入的唯一字面形式保留实际 German Wiktionary 页标题，附页面及贡献者历史 URL 模板；多词类出现相同形式时，确定性选择一个确实提供该形式的源页，不因输入顺序漂移。该映射和完整许可均随应用打包并逐字节检查。阅读器只载入小的许可文档，不把 5MB 来源映射整体塞进 SwiftUI 文本布局。

## 证据与修正记录

生产旧路由红测 `/tmp/typebar-german-corpus-red-20261029.log`：三档缺 `und`／`Haus`，一项测试六处失败，测试 1.736 秒、驱动 23.842 秒，全部非 Markdown 输入哈希不变。候选 v1 的最大长度未覆盖原上限，v2 的小写排名键漏选常见 ß 词，早期标点按未排名字母序偏向同一家族；这些是仓库外准备过程中的问题。最终保留真实长词边界、采用正确 case-fold 查排名并明确编辑标点选集后，才安装 v4 产物。没有把候选调查或缺类型编译错误算成产品红测。

接入 `/tmp/typebar-german-corpus-green-20261029.log`：20 项零失败／零跳过，XCTest 7.350 秒、驱动 123.334 秒（含编译），输入哈希不变。覆盖三档数据哈希、基本池不变、大小写／ß、Lazy Latin／No Space、三个真实长词及 Backwards、全部 28 个标点条目和 48 个多词候选、有限截断、153 词续批／重复及旧合成提示的 JSON／模型／回放。

`/tmp/typebar-german-practice-host-20261029.log`：一项测试逐一挂载三档的实际生产练习页，XCTest 3.267 秒、驱动 25.206 秒，输入哈希不变。153 词触发真实全预览准备，观察器调用实际准备器，不替换词提示；核对配置语言、实际词字段成员、原生 NSTextInputClient 首词输入、接收器身份及不重新生成。全部使用隐藏窗口、隔离 defaults／内存 SwiftData，不涉及真实账号或邮件，不是物理键盘／系统 IME 终验。

独立 Debug 数据进程 `/tmp/typebar-german-lazy-probe-20261029.log`：起始 RSS 5,776 KiB；1k 初始化 0.000384 秒／6,208 KiB，10k 0.003569 秒／7,264 KiB，250k 0.105817 秒／30,704 KiB，再次大档 getter 约 0.000000875 秒。这只证明本机隔离 getter 的成本及惰性边界，不代表整应用冷启动、主线程首次切换、Release 或最低设备性能。

初版完整性工具在截断署名且重算 manifest 校验值时仍返回成功，真实反例保存在 `/tmp/typebar-german-notice-negative-red-20261029.json`。现将发布署名和逐词映射的哈希独立固定，准备及包内验证均检查；两个反例在普通／`-O` 模式下均拒绝，有效产物对照通过。记录 `/tmp/typebar-german-attribution-negative-green-20261029.json`，九项标准库自测在两种模式均通过。固定源复现 `/tmp/typebar-german-final-source-check-20261029.log` 通过，不把自洽的可修改 manifest 当成来源真实性证明。

最终扩大 `/tmp/typebar-german-corpus-regression-20261029.log`：987 项零失败／零运行时跳过，XCTest 478.883 秒、驱动 492.514 秒；145 项必需固定源码证据全部通过。冻结全部 1,304 个非 Markdown 输入，运行后哈希一致。范围含新 German 核心／实际宿主／现有元数据身份和键盘、其他实际语言池、生成／续批、多语、输入／修饰器、回放／历史、配置与固定源码轨迹；不是完整客户端或服务端全量验收。

`/tmp/typebar-german-corpus-package-20261029.log` 的 Debug 包检查通过，驱动 37.729 秒，全部非 Markdown 输入哈希不变；包括严格签名、九个署名／来源资源逐字节比较、包内资源边界及固定参考原创边界。源码原创性自测／参考扫描、配置／语言元数据无漂移、47 个直接规格／119 个原生符号／17 个支持规格的来源审计通过。人工清单 1,435 项只验证结构，新增两个场景保持待验收。实际 About 截图已查看，English 显著版权保留，German 来源署名在完整许可入口前清晰显示。

推送前没有打开 PR，main 为 `8c52fb13028f82fd8e8718d55cb7ed65463b034e`、开发分支基线为 `3ae7796d`，Actions 总数仍 826，最新 main 运行 `39118939684` 成功。工作流仅增加三条 German 准备／完整性检查，触发条件及通知偏好保持；本批只集中推送开发分支，不创建 PR、不主动重跑远端任务。所有 Swift 编译／测试／探针／打包均串行完成，未启动 Typebar 主程序。

与完整固定起点清单同范围仍余 114 个直接合成入口，声明数量之和 3,490,657，不是全部语言缺口数量；复核记录 `/tmp/typebar-german-remaining-synthetic-20261029.json`。语言质量／难度／分布、全部配置交错、物理键盘／IME、VoiceOver、旧二进制和完整 Release 性能仍开放，目标保持进行。
