# 阿塞拜疆语与蒙古语四档独立词库

起点 b554accbe03eba99cdb3077b5fb9ab5c0e1badfb，固定参考 91bd24bb8513785c7364cbea29296ff7adafac41。旧基础每种语言只有 30 个自有词，Azerbaijani 1k 和 Mongolian 10k 分别用 qx／əx 与 ꙮ／ӿ 加编号合成。新四档以独立词典词形、原样句子词项及三处明示的大小写改编替换，不读取或交付原版词值、代码或资产。

## 约束、改编和保留例外

原版只导出数量、字符集合、联合类别及 UTF-16 长度，记录在工作区外 `next-batch-az-mn-reference-aggregate.json` 和 `az-character-joint-aggregate.json`。

| 入口 | 数量 | 原版长度 | 新选集边界 |
| --- | --- | --- | --- |
| Azerbaijani 基础 | 199 | 3–6 | ASCII 73、非 ASCII 126；完整原版键集；旧 iş 为 2，gələcək／pəncərə 为 7、sakitlik 为 8，明确保留这四个例外 |
| Azerbaijani 1k | 989 | 2–7 | ASCII 321、无组合点的非 ASCII 666、带 U+0307 的两项；保留旧 sakitlik 的 8 字符例外 |
| Mongolian 基础 | 1085 | 2–15 | 全部小写字母、非 ASCII，完整原版键集，无长度例外 |
| Mongolian 10k | 9219 | 1–18 | 小写项 8322、大写项 897，完整大小写键集、全部非 ASCII，无长度例外 |

基础均保留在对应大档中，旧 30 词全部保留；没有其他新增长度例外。Azerbaijani 两个组合点词为 `i̇lham`／`i̇slam`，分别来自独立词条 `İlham`／`İslam`，明确采用 Unicode 默认小写，不冒充规范阿塞拜疆语大小写或原样词形。源原词、词条和转换规则逐项交付；两个改编来自不同词条。U+0307 是组合标记，不是标点，Swift 字素、Unicode scalar 和 UTF-16 单元必须区分，简化输入沿原有替换表保留该组合点。

蒙古语词典加句子候选仍没有原样大写 Ё；以真实词形 `ёстой`（独立词条 `ёс`）仅改首字母为 `Ёстой`，逐项标为 `dictionary-initial-uppercase`。这是唯一蒙古语大小写改编，不能宣称原始来源已含这个大写形式。另有 293 个原样大写句子词项，标为 `tatoeba-literal`，同时提供来源句子／作者及其小写词典见证词条；不从连字符、撇号或其他长词内部截片。其余蒙古语词项保留独立词典原样拼写或明确的旧自有词。

## 固定独立来源

[Kaikki Azerbaijani](https://kaikki.org/dictionary/Azerbaijani/index.html)：193947936 字节，SHA-256 8b17fec6310f7285fcbd8a08aa09f1c65fe3b98778bc1fa129b3de20bb50321e；索引报告 2026-10-03 提取、2026-09-02 dump，1a05e46／e3d6d4e。

[Kaikki Mongolian](https://kaikki.org/dictionary/Mongolian/index.html)：12994727 字节，SHA-256 6ccd2cafc023ea5d1bf0310bef9e8abf059174212dbd66cc91dbed6fca38dac7；索引报告 2026-10-25 提取、2026-10-01 dump，f9fe161／6f96ddf。

两份词典来自 English Wiktionary contributors，经 Kaikki／Wiktextract 提取，选择及改编按 CC BY-SA 4.0 署名；只取 az／mn 允许词汇类与字面词形，排除错误／非标准义项及转写、模板、错误标签形式。六个蒙古语旧词 асуулт、найдвар、оролдлого、санаа、тэмдэглэл、хариулт 在筛选后的词汇类中没有出处，明确标为 `typebar-legacy`，不声称原始词典没有其他类别的同字符串；阿塞拜疆语旧词均有选定词汇出处。

[Tatoeba 下载说明](https://tatoeba.org/en/downloads)：aze detailed 237935 字节，SHA-256 315a666a6103209c6c435b5352e247db105f0e9a4a84149d88b0cb93a746bc33；mon detailed 47670 字节，SHA-256 5056ffc65661b7633d8a1a38bde442c9a59640366eccb384617c44e600a0bfb6。句子及摘录按 CC BY 2.0 France 分开署名，只交付选中短词项／出处而非完整归档、译文或音频。

观察按每句每项一次计数；词典词形与改编采用 NFC 小写查询，原样句子词项采用精确大小写查询。词边界保留字母数字、组合标记、下划线、连字符及撇号，避免部分词匹配；无观察为 NA，不是零。基础／大档的观察项分别为 Azerbaijani 194／984、Mongolian 1069／1407。这不代表原版词汇或频率分布等价，尤其蒙古语大档的大量词形只有词典证据。无观察项优先词条标题而非变形；Zipf 未知支持保持不变。

来源表十列分别给出词项、来源类别、来源标题、原词形、改编规则、词典见证词条、观察模式、句子计数、首条 ID 和作者。空作者或 `\\N` 明确映射为 `(unowned)`，不虚构贡献者。两份说明包含全部处理过的贡献者与页面。生成器固定四个输入与八个产物哈希，支持只读重建和固定产物检查；原生许可选项、摘要及包资源复制／逐字节核对已接入。

## 验证

`az-mn-corpus-red` 四项测试十七处预期失败，原生 1.473 秒、driver 27.456317 秒，输入哈希不变；旧目标回放通过。接入后补齐最长词、组合点输入／成绩 JSON、原样西里尔大写两种标点状态、来源读取。旧 Azerbaijani 规模测试的最大长度按保留旧 sakitlik 明示为 8，字母断言按原版真实组合点允许 U+0307；新增测试同时限定只有两项、位置正确、无其他新增例外。

三项普通／优化生成器自检、固定产物和四输入全来源重建对照通过；293 个蒙古语原样词项的首条句子、完整词边界及作者独立核对零差异。`az-mn-corpus-focused` 63 项零失败、零跳过，原生 11.854 秒、driver 121.669514 秒，非 Markdown 输入哈希不变。

`az-mn-corpus-regression` 扩大回归 714 项零失败、零跳过，原生 445.434 秒、driver 461.353894 秒；152 项必需固定源码对照证据检查通过。非 Markdown 输入哈希不变，与 63 项定向使用相同代码和数据。

固定参考配置／语言元数据无漂移、原创性边界及 1490 个唯一人工场景的结构审计通过；结构审计不代表这些人工场景已执行。当前引擎 SHA-256 为 2cb861433b656b0f46b85b420bfa048bc9144b1509e9b5b2eae65c97c9c847cb。213 个索引属性的逐体统计移除两个内联合成入口、10208 个位置；命名助手仍为 100／774604，合成实现范围合计更新为 118／916892，见 [索引词库盘点](INDEXED_LEXICON_IMPLEMENTATION_AUDIT.md)。

`az-mn-corpus-release-package` 显式设置 `TYPEBAR_BUILD_CONFIGURATION=release`，优化编译 554.75 秒、完整 driver 597.769569 秒；签名包、来源表／说明逐字节资源对照与原创性边界检查通过，非 Markdown 输入哈希不变。用户中断后于 2026-11-03 恢复工作，先核对该进程已终态成功、无残留父子进程，再验证当前代码与已测／已打包输入一致，没有重新构建。

Release 二进制 SHA-256 为 7222a2c0868f9bb12334d89485443824307bdac29ae5aeee26f7eece5a3abe6d，不含 `app.typebar.qa.native-input` 和 `TYPEBAR_QA_NATIVE_INPUT_DIAGNOSTICS`；既有隔离 Debug 正对照均包含两项。仅两个诊断源文件与旧正对照核对相同，不声称该旧 Debug 的全部代码／词库等同当前。

可见窗口尚未验收，本批没有启动可见应用。语言质量、代表性词频分布、实体输入、IME、VoiceOver 和完整原版功能等价仍开放，goal active。
