# 官方配置兼容性审计

## 范围与方法

- 参考源码：Monkeytype `91bd24bb8513785c7364cbea29296ff7adafac41`。
- 权威入口：`packages/schemas/src/configs.ts` 中的 `ConfigSchema`；它列出当前网页端所有可保存配置键。
- 本审计只记录用户可见设置的代码级映射。`已映射` 不代替真实设备验收；`部分` 和`未实现`不能在其他文档中表述为已完成。
- Typebar 的实现、文案、数据模型和测试均为原创；该表不复制参考实现的代码、资产、词表、布局定义或主题数据。

- Catalan、Indonesian 与 Malay 的自动化测试覆盖各自的自创词流、四档原创引语、完整多语混排轮转、`ca-ES` / `id-ID` / `ms-MY` 朗读 locale 与仅在明示启用时使用的 `ca` / `id` / `ms` 百科入口；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。

状态含义：**已映射** = 有本机可见设置及对应持久化模型；**部分** = 可见意图已实现但选项、数据规模或交互不同；**未实现** = 尚无对应能力；**不适用** = 与“无广告的本机应用”产品约束冲突而有意不实现。

## 逐项映射

| 官方键 | Typebar 对应项 | 状态与证据 |
| --- | --- | --- |
| `punctuation` | `ContentOptions.includePunctuation` | 已映射；进入 `TestConfiguration` 与历史筛选。 |
| `numbers` | `ContentOptions.includeNumbers` | 已映射；进入 `TestConfiguration` 与历史筛选。 |
| `words` | `TestConfiguration.wordLimit` | 已映射；字数模式和自定义循环字数共用限制。 |
| `time` | `TestConfiguration.duration` | 已映射；计时模式和自定义循环计时共用限制。 |
| `mode` | `TestMode` | 已映射；官方当前五种模式 time/words/quote/zen/custom 均存在，原生代码练习为额外能力。 |
| `quoteLength` | `QuoteLength`、收藏和本机搜索 | 部分；已覆盖短/中/长/超长与收藏/搜索，内容规模保持原创。 |
| `language` | `TypingLanguage`、`mixedLanguageComponents` | 部分；九十四种 Typebar 自有单语（包括 Swiss German、Egyptian Arabic、Moroccan Arabic、Pashto、Sindhi、Occitan、Oromo、Macedonian、Kazakh、Vietnamese、Bemba、Bosnian、Latin、Friulian、Malagasy、Welsh、Hausa、Tatar、Uzbek 与三种 Esperanto 书写方式）、中英混合和自选多语组合，不复制官方语言目录。Arabic、Egyptian Arabic、Moroccan Arabic、Pashto、Sindhi、Hebrew、Persian、Urdu 与 Central Kurdish 使用 macOS 输入源、RTL 提示和原生双向文本排版；三种 Arabic、Pashto、Sindhi 与 Central Kurdish 均使用系统原生连写字形，九者均暂不进入双向多语混排；经配置验证的 LTR 语言可进入混排，Occitan、Oromo、Macedonian、Kazakh 与 Vietnamese 现经测试进入该白名单，Thai 的空格提交来自参考实际生成器而非自然书写习惯推断。知识短文和朗读严格按每项配置或其缺省分支处理：Swiss German 使用 `de`／`de-CH`，Egyptian Arabic 使用 `ar`／`ar-EG`，Moroccan Arabic 使用 `ar`／`ar-MA`，Pashto 使用 `ps`／`ps`，Sindhi 使用 `sd`／`sd`，Occitan 使用 `oc`／`oc-FR`，Oromo 使用 `om`／`om`，Sanskrit 使用 `sa`，Sinhala 使用 `si`，Khmer 使用 `km`／`km-KH`，Azerbaijani、Belarusian 与 Uzbek 使用完整 BCP-47 的首段／完整标识，Central Kurdish 使用 `ckb`，Bemba 使用 `bem`，Friulian 使用 `fur`，Hausa 使用 `ha`，Tatar 使用 `tt`；Bosnian、Latin、Malagasy、Welsh、Macedonian、Kazakh、Vietnamese 和三个无 BCP-47 的 Esperanto 书写方式严格回退 `en`／`en-US`。Swiss German 复用 Typebar 自有 German 内容、把可见 `ß` 变为 `ss`，可进入成绩和排行榜但不能投稿或选择社区引语；两种地区 Arabic、Pashto、Sindhi、Occitan、Oromo、Macedonian、Kazakh 与 Vietnamese 使用独立自有内容并允许社区投稿，Moroccan Arabic 与 Sindhi 按 `orderedByFrequency: false` 显示 Zipf 不支持提示，Pashto、Occitan、Macedonian、Kazakh 与 Vietnamese 按缺失排序标记显示未知提示，Oromo 按 `orderedByFrequency: true` 保留 Zipf 高频词。Zipf 的其余分支、输入简化规则、原创内容边界及各语言的完整映射均记录在后续审计条目与自动化测试中。乌克兰语 Latin、日语罗马字、Greeklish 以及 Esperanto X/H 均保持所选 ASCII 书写，不让在线原文改写它们。 |

2026-09-04 更新：单语数量增至五十八种，新增 Burmese（`myanmarBurmese`）：参考配置为 `joiningScript: true`、`noLazyMode: true`、LTR、`my-MM`。Typebar 使用原创词流、四档引语、macOS 组合输入和空格提交，并以 `my` 访问知识短文、`my-MM` 调用系统朗读；该语言进入混排、预设、归档、社区投稿及服务端排行榜全路径。

2026-09-04 更新：单语数量增至五十九种，新增 Lao（`lao`）：参考配置为 LTR、`joiningScript: false`、未设置 `noLazyMode`、`bcp47: lo`。Typebar 使用原创词流、四档引语和空格提交，以 `lo` 访问知识短文及调用系统朗读；保留用户选择的简化输入，并将该语言接入混排、预设、归档、社区投稿及服务端排行榜全路径。参考的 `Noto Sans Lao` 字体资产未被导入，原生显示交由 macOS。

2026-09-05 更新：单语数量增至六十种，新增 Amharic（`amharic`）：参考配置仅定义 `bcp47: am-ET`，没有 `rightToLeft`、`joiningScript` 或 `noLazyMode`。Typebar 使用原创词流、四档引语、LTR 空格提交，以 `am` 访问知识短文并以 `am-ET` 调用系统朗读；保留用户选择的简化输入，并将该语言接入混排、预设、归档、社区投稿及服务端排行榜全路径。

2026-09-05 更新：单语数量增至六十一种，新增 Armenian（`armenian`）：参考配置仅定义 `noLazyMode: true`，没有 BCP-47、RTL 或连写标记。Typebar 使用原创词流、四档引语和 LTR 空格提交；知识短文与系统朗读严格复用参考的缺省分支，分别为 `en` 和 `en-US`，不补造 Armenian 代码。该语言进入混排、预设、归档、社区投稿及服务端排行榜全路径，且不应用简化输入。

2026-09-05 更新：单语数量增至六十二种，新增 Georgian（`georgian`）：参考配置仅定义 `noLazyMode: true`，没有 BCP-47、RTL 或连写标记。Typebar 使用原创词流、四档引语和 LTR 空格提交；知识短文与系统朗读严格复用参考的缺省分支，分别为 `en` 和 `en-US`，不补造 Georgian 代码。该语言进入混排、预设、归档、社区投稿及服务端排行榜全路径，且不应用简化输入。

2026-09-05 更新：单语数量增至六十三种，新增 Azerbaijani（`azerbaijani`）：参考配置仅定义 `bcp47: az-AZ`，没有 RTL、连写或 `noLazyMode` 标记。Typebar 使用原创词流、四档引语与 LTR 空格提交；知识短文按 BCP-47 首段使用 `az`，系统朗读精确使用 `az-AZ`，保留用户选择的简化输入。该语言进入混排、预设、归档、社区投稿及服务端排行榜全路径。

2026-09-05 更新：单语数量增至六十四种，新增 Belarusian（`belarusian`）：参考配置定义 `noLazyMode: true` 与 `bcp47: be-BY`，没有 RTL 或连写标记。Typebar 使用原创词流、四档引语与 LTR 空格提交；知识短文按 BCP-47 首段使用 `be`，系统朗读精确使用 `be-BY`，并禁用简化输入。该语言进入混排、预设、归档、社区投稿及服务端排行榜全路径；独立的拉丁变体尚未以本项代替。

2026-09-05 更新：单语数量增至六十五种，新增 Central Kurdish（`kurdishCentral`）：参考配置定义 `rightToLeft: true`、`joiningScript: true` 与 `bcp47: ckb`，未定义 `noLazyMode`。Typebar 使用原创词流与四档引语，交由 macOS 原生 RTL 文本系统呈现连写字形；知识短文与系统朗读均精确使用 `ckb`，保留用户选择的简化输入。该语言进入单语配置、预设、归档、社区投稿及服务端排行榜全路径，但不进入未验收的双向多语混排。
2026-09-05 更新：单语数量增至六十六种，新增 Lithuanian（`lithuanian`）：参考配置仅定义名称，没有 BCP-47、RTL、连写或 `noLazyMode`。Typebar 使用原创词流、四档引语与 LTR 空格提交，并严格保留参考的缺省分支：知识短文使用 `en`，系统朗读使用 `en-US`，不补造 Lithuanian 代码；该语言保留简化输入并进入混排、预设、归档、社区投稿及服务端排行榜全路径。本行取代语言映射概览中较早的六十五种数量。
2026-09-05 更新：单语数量增至六十七种，新增 Latvian（`latvian`）：参考配置仅定义 `bcp47: lv`，没有 RTL、连写或 `noLazyMode`。Typebar 使用原创词流、四档引语与 LTR 空格提交；知识短文与系统朗读均精确使用 `lv`，保留用户选择的简化输入，并接入混排、预设、归档、社区投稿及服务端排行榜全路径。本行取代语言映射概览中较早的六十六种数量。
2026-09-05 更新：单语数量增至六十八种，新增 Mongolian（`mongolian`）：参考配置仅定义 `noLazyMode: true`，没有 BCP-47、RTL 或连写。Typebar 使用原创词流、四档引语与 LTR 空格提交；知识短文与系统朗读严格复用参考的缺省分支，分别为 `en` 和 `en-US`，不补造 Mongolian 代码，并禁用简化输入。该语言进入混排、预设、归档、社区投稿及服务端排行榜全路径。本行取代语言映射概览中较早的六十七种数量。
2026-09-05 更新：单语数量增至六十九种，新增 Irish（`irish`）：参考配置仅定义 `bcp47: ga-IE`，没有 RTL、连写或 `noLazyMode`。Typebar 使用原创词流、四档引语与 LTR 空格提交；知识短文按 BCP-47 首段使用 `ga`，系统朗读精确使用 `ga-IE`，并保留用户选择的简化输入。该语言进入混排、预设、归档、社区投稿及服务端排行榜全路径。本行取代语言映射概览中较早的六十八种数量。
2026-09-05 更新：单语数量增至七十种，新增 Galician（`galician`）：参考配置定义 `bcp47: gl-ES` 与 `orderedByFrequency: true`，没有 RTL、连写或 `noLazyMode`。Typebar 使用原创、按自有排名排列的词流与四档引语，保持 LTR 空格提交；知识短文按 BCP-47 首段使用 `gl`，系统朗读精确使用 `gl-ES`，并保留 Zipf 高频词与用户选择的简化输入。该语言进入混排、预设、归档、社区投稿及服务端排行榜全路径。本行取代语言映射概览中较早的六十九种数量。
2026-09-05 更新：单语数量增至七十一种，新增 Marathi（`marathi`）：参考配置定义 `noLazyMode: true` 与 `orderedByFrequency: true`，没有 BCP-47、RTL 或连写。Typebar 使用原创、按自有排名排列的词流与四档引语，保持 LTR 空格提交；知识短文与系统朗读严格复用参考的缺省分支，分别为 `en` 和 `en-US`，不补造 Marathi 代码，并保留 Zipf 高频词、禁用简化输入。该语言进入混排、预设、归档、社区投稿及服务端排行榜全路径。本行取代语言映射概览中较早的七十种数量。
2026-09-05 更新：单语数量增至七十二种，新增 Albanian（`albanian`）：参考配置仅定义 `name: albanian`，没有 BCP-47、RTL、连写、`noLazyMode` 或词频排序标记。Typebar 使用原创词流与四档引语，保持 LTR 空格提交；知识短文与系统朗读严格复用参考的缺省分支，分别为 `en` 和 `en-US`，不补造 Albanian 代码，并保留用户选择的简化输入。该语言进入混排、预设、归档、社区投稿及服务端排行榜全路径。本行取代语言映射概览中较早的七十一种数量。
2026-09-05 更新：补齐 Zipf 词频元数据语义：Typebar 保留现有秩次加权生成器，并以固定参考的 `orderedByFrequency` 字段区分已确认、明确不支持与未知三种状态。启用 Zipf 后，明确不支持与未知会显示七秒原生提示，但不会移除修饰器或改变生成路径，和参考 `debouncedZipfCheck` 的可观测行为一致。该策略已覆盖现有 Armenian、Bulgarian、Hungarian、Lao 等明确不支持词表及未标注排序的语言。
2026-09-05 更新：单语数量增至七十三种，新增 Bemba（`bemba`）：参考配置定义 `bcp47: bem`、`rightToLeft: false` 与 `orderedByFrequency: false`，没有连写或 `noLazyMode`。Typebar 使用原创词流与四档引语，保持 LTR 空格提交；知识短文与系统朗读精确使用 `bem`，并保留用户选择的简化输入。该语言进入混排、预设、归档、社区投稿及服务端排行榜全路径；启用 Zipf 时会显示词表未按频率排序的七秒提示，但不移除修饰器。本行取代语言映射概览中较早的七十二种数量。
2026-09-05 更新：单语数量增至七十四种，新增 Bosnian（`bosnian`）：参考配置仅定义 `name: bosnian` 与 `orderedByFrequency: true`，没有 BCP-47、RTL、连写或 `noLazyMode`。Typebar 使用原创、按自有排名排列的词流与四档引语，保持 LTR 空格提交；知识短文与系统朗读严格复用参考的缺省分支，分别为 `en` 和 `en-US`，不补造 Bosnian 代码，并保留 Zipf 高频词和用户选择的简化输入。该语言进入混排、预设、归档、社区投稿及服务端排行榜全路径。本行取代语言映射概览中较早的七十三种数量。
2026-09-05 更新：单语数量增至七十七种，新增标准 Esperanto（`esperanto`）、Esperanto X-sistemo（`esperantoXSystem`）与 Esperanto H-sistemo（`esperantoHSystem`）三种独立书写方式。固定参考中，标准模式仅定义 `orderedByFrequency: true`；X-sistemo 仅定义 `noLazyMode: true`；H-sistemo 同时定义二者；三者均没有 BCP-47、RTL 或连写。Typebar 使用独立的原创词流和四档引语，以 LTR 空格提交并接入混排、预设、归档、社区投稿及服务端排行榜；标准模式保留 Unicode 与简化输入，X/H 保持 ASCII 转写并禁用简化输入。三者的知识短文与朗读严格复用缺省 `en` 与 `en-US`，不补造 Esperanto 代码；标准和 H 保留 Zipf，X 在启用时显示七秒“可能不支持”提示但不移除修饰器。本行取代语言映射概览中较早的七十四种数量。
2026-09-05 更新：单语数量增至七十八种，新增 Latin（`latin`）：参考配置仅定义 `name: latin`，没有 BCP-47、RTL、连写、`noLazyMode` 或词频排序标记。Typebar 使用原创词流与四档引语，保持 LTR 空格提交；知识短文与系统朗读严格复用参考的缺省分支，分别为 `en` 和 `en-US`，不补造 Latin 代码，并保留用户选择的简化输入。该语言进入混排、预设、归档、社区投稿及服务端排行榜全路径；启用 Zipf 时显示可能不支持的七秒提示，但不移除修饰器。本行取代语言映射概览中较早的七十七种数量。
2026-09-05 更新：单语数量增至七十九种，新增 Friulian（`friulian`）：参考配置定义 `bcp47: fur`，没有 RTL、连写、`noLazyMode` 或词频排序标记。Typebar 使用原创词流与四档引语，保持 LTR 空格提交；知识短文与系统朗读均精确使用 `fur`，并保留用户选择的简化输入。该语言进入混排、预设、归档、社区投稿及服务端排行榜全路径；启用 Zipf 时显示可能不支持的七秒提示，但不移除修饰器。本行取代语言映射概览中较早的七十八种数量。
2026-09-05 更新：单语数量增至八十种，新增 Malagasy（`malagasy`）：参考配置仅定义 `noLazyMode: true`，没有 BCP-47、RTL、连写或词频排序标记。Typebar 使用原创词流与四档引语，保持 LTR 空格提交；知识短文与系统朗读严格复用参考的缺省分支，分别为 `en` 和 `en-US`，不补造 Malagasy 代码，并禁用简化输入。该语言进入混排、预设、归档、社区投稿及服务端排行榜全路径；启用 Zipf 时显示可能不支持的七秒提示，但不移除修饰器。本行取代语言映射概览中较早的七十九种数量。
2026-09-05 更新：单语数量增至八十一种，新增 Welsh（`welsh`）：参考配置仅定义 `name: welsh`，没有 BCP-47、RTL、连写、`noLazyMode` 或词频排序标记。Typebar 使用原创词流与四档引语，保持 LTR 空格提交；知识短文与系统朗读严格复用参考的缺省分支，分别为 `en` 和 `en-US`，不补造 Welsh 代码，并保留用户选择的简化输入。该语言进入混排、预设、归档、社区投稿及服务端排行榜全路径；启用 Zipf 时显示可能不支持的七秒提示，但不移除修饰器。本行取代语言映射概览中较早的八十种数量。
2026-09-05 更新：单语数量增至八十二种，新增 Hausa（`hausa`）：参考配置定义 `bcp47: ha`，没有 RTL、连写、`noLazyMode` 或词频排序标记。Typebar 使用原创词流与四档引语，保持 LTR 空格提交；知识短文与系统朗读均精确使用 `ha`，并保留用户选择的简化输入。该语言进入混排、预设、归档、社区投稿及服务端排行榜全路径；启用 Zipf 时显示可能不支持的七秒提示，但不移除修饰器。本行取代语言映射概览中较早的八十一种数量。
2026-09-05 更新：单语数量增至八十三种，新增 Tatar（`tatar`）：参考配置定义 `bcp47: tt` 与 `orderedByFrequency: true`，没有 RTL、连写或 `noLazyMode` 标记。Typebar 使用原创 Unicode 西里尔词流与四档引语，保持 LTR 空格提交；知识短文与系统朗读均精确使用 `tt`，保留用户选择的简化输入和 Zipf 高频词。该语言进入混排、预设、归档、社区投稿及服务端排行榜全路径。本行取代语言映射概览中较早的八十二种数量。
2026-09-05 更新：单语数量增至八十四种，新增 Uzbek（`uzbek`）：参考配置显式定义 `rightToLeft: false` 与 `bcp47: uz-UZ`，没有连写、`noLazyMode` 或词频排序标记。Typebar 使用原创 Unicode 词流与四档引语，保持 LTR 空格提交；知识短文按 BCP-47 首段使用 `uz`，系统朗读精确使用 `uz-UZ`，并保留用户选择的简化输入。该语言进入混排、预设、归档、社区投稿及服务端排行榜全路径；启用 Zipf 时显示可能不支持的七秒提示，但不移除修饰器。本行取代语言映射概览中较早的八十三种数量。
2026-09-05 更新：单语数量增至八十五种，新增 Swiss German（`swissGerman`）：参考配置定义 `bcp47: de-CH`，没有 RTL、连写、`noLazyMode` 或词频排序。参考源码将其词流和引语路径回退 German，并将可见 `ß` 替换为 `ss`。Typebar 仅派生自有 German 内容而不导入参考字典、引语或布局资产；它使用 LTR 空格提交、`de` 知识短文入口、`de-CH` 系统朗读，保留简化输入与 Zipf 的七秒未知提示。该语言进入混排、预设、归档、结果和排行榜；按源码不进入社区投稿或社区引语来源。
2026-09-05 更新：单语数量增至八十八种，新增 Pashto（`pashto`）：参考配置定义 `rightToLeft: true`、`joiningScript: true`、`noLazyMode: true` 与 `bcp47: ps`，没有词频排序标记。Typebar 使用原创词流与四档引语，交由 macOS 原生 RTL 文本系统呈现连写字形；知识短文与系统朗读均精确使用 `ps`。该语言不进入未验收的双向多语混排，非自定义练习禁用简化输入、自定义文本保留例外；Zipf 启用时显示可能不支持的七秒提示但不移除修饰器。Pashto 已进入预设、归档、社区投稿、成绩及服务端排行榜全路径。
2026-09-05 更新：单语数量增至八十九种，新增 Sindhi（`sindhi`）：参考配置定义 `rightToLeft: true`、`joiningScript: true`、`orderedByFrequency: false` 与 `bcp47: sd`，没有 `noLazyMode`。Typebar 使用原创词流与四档引语，交由 macOS 原生 RTL 文本系统呈现连写字形；知识短文与系统朗读均精确使用 `sd`。该语言不进入未验收的双向多语混排，保留用户显式选择的简化输入却不继承标准 Arabic 的自动快捷偏好；Zipf 启用时显示词表未按频率排序的七秒提示但不移除修饰器。Sindhi 已进入预设、归档、社区投稿、成绩及服务端排行榜全路径。
2026-09-05 更新：单语数量增至九十种，新增 Occitan（`occitan`）：参考配置定义 `bcp47: oc-FR`，没有 RTL、连写、`noLazyMode` 或词频排序标记。Typebar 使用原创词流与四档引语、LTR 空格提交；知识短文按 BCP-47 首段使用 `oc`，系统朗读精确使用 `oc-FR`。该语言进入已测试的默认/自选多语混排、预设、归档、社区投稿、成绩及服务端排行榜全路径；保留用户选择的简化输入，Zipf 启用时显示可能不支持的七秒提示但不移除修饰器。

2026-09-05 更新：单语数量增至九十一种，新增 Oromo（`oromo`）：参考配置定义 `bcp47: om` 与 `orderedByFrequency: true`，没有 RTL、连写或 `noLazyMode`。Typebar 使用原创词流与四档引语、LTR 空格提交；知识短文与系统朗读均精确使用 `om`。该语言进入已测试的默认/自选多语混排、预设、归档、社区投稿、成绩及服务端排行榜全路径；保留用户选择的简化输入与 Zipf 高频词。

2026-09-05 更新：单语数量增至九十二种，新增 Macedonian（`macedonian`）：参考配置仅定义 `noLazyMode: true`，没有 BCP-47、RTL、连写或词频排序标记。Typebar 使用原创西里尔词流与四档引语、LTR 空格提交；知识短文与系统朗读严格复用缺省 `en` 与 `en-US`，不补造 Macedonian 代码。该语言进入已测试的默认/自选多语混排、预设、归档、社区投稿、成绩及服务端排行榜全路径；普通练习禁用简化输入，自定义文本保留例外，Zipf 启用时显示可能不支持的七秒提示但不移除修饰器。

2026-09-05 更新：单语数量增至九十三种，新增 Kazakh（`kazakh`）：参考配置仅定义 `noLazyMode: true`，没有 BCP-47、RTL、连写或词频排序标记。Typebar 使用原创西里尔词流与四档引语、LTR 空格提交；知识短文与系统朗读严格复用缺省 `en` 与 `en-US`，不补造 Kazakh 代码。该语言进入已测试的默认/自选多语混排、预设、归档、社区投稿、成绩及服务端排行榜全路径；普通练习禁用简化输入，自定义文本保留例外，Zipf 启用时显示可能不支持的七秒提示但不移除修饰器。

2026-09-05 更新：单语数量增至九十四种，新增 Vietnamese（`vietnamese`）：参考配置没有 BCP-47、RTL、连写、`noLazyMode` 或词频排序标记。Typebar 使用原创词流与四档引语、LTR 空格提交；知识短文与系统朗读严格复用缺省 `en` 与 `en-US`，不补造 Vietnamese 代码。该语言进入已测试的默认/自选多语混排、预设、归档、社区投稿、成绩及服务端排行榜全路径；保留用户显式选择的简化输入，Zipf 启用时显示可能不支持的七秒提示但不移除修饰器。

2026-09-05 更新：单语数量增至九十五种，新增 Jyutping（`jyutping`）：参考配置定义 `bcp47: zh-Hant`，没有 RTL、连写、`noLazyMode` 或词频排序标记。Typebar 使用原创 ASCII 加声调数字词流与四档引语、LTR 空格提交；知识短文按 BCP 首段使用 `zh`，返回的汉字内容按中文词界分词，系统朗读精确使用 `zh-Hant`。该语言进入已测试的默认/自选多语混排、预设、归档、社区投稿、成绩及服务端排行榜全路径；保留用户显式选择的简化输入，Zipf 启用时显示可能不支持的七秒提示但不移除修饰器。
2026-09-05 更新：单语数量增至九十六种，新增 Pinyin（`pinyin`）：基础、1k 与 10k 参考配置均只定义名称，没有 BCP-47、RTL、连写、`noLazyMode` 或词频排序标记。Typebar 使用原创 ASCII 拼音词流与四档引语、LTR 空格提交；知识短文与系统朗读严格复用缺省 `en` 与 `en-US`，不补造 Pinyin 代码。该语言进入已测试的默认/自选多语混排、预设、归档、社区投稿、成绩及服务端排行榜全路径；保留用户显式选择的简化输入，Zipf 启用时显示可能不支持的七秒提示但不移除修饰器。
2026-09-05 更新：单语数量增至九十七种，新增 Western Armenian（`armenianWestern`）：基础与 1k 参考配置均定义 `bcp47: hyw`，没有 RTL、连写、`noLazyMode` 或词频排序标记。Typebar 使用原创西部亚美尼亚语正字法词流与四档引语、LTR 空格提交；知识短文与系统朗读均精确使用 `hyw`。该语言进入已测试的默认/自选多语混排、预设、归档、社区投稿、成绩及服务端排行榜全路径；保留用户显式选择的简化输入，Zipf 启用时显示可能不支持的七秒提示但不移除修饰器。
2026-09-05 更新：单语数量增至九十八种，新增 Bashkir（`bashkir`）：参考配置定义 `bcp47: ba` 与 `orderedByFrequency: true`，没有 RTL、连写或 `noLazyMode` 标记。Typebar 使用原创 Bashkir 西里尔词流与四档引语、LTR 空格提交；知识短文与系统朗读均精确使用 `ba`。该语言进入已测试的默认/自选多语混排、预设、归档、社区投稿、成绩及服务端排行榜全路径；保留用户显式选择的简化输入与 Zipf 高频词。
2026-09-05 更新：单语数量增至九十九种，新增 Euskera（`basque`）：参考配置定义 `rightToLeft: false` 与 `bcp47: eu`，没有连写、`noLazyMode` 或词频排序标记。Typebar 使用原创 Basque 词流与四档引语、LTR 空格提交；知识短文与系统朗读均精确使用 `eu`。该语言进入已测试的默认/自选多语混排、预设、归档、社区投稿、成绩及服务端排行榜全路径；保留用户显式选择的简化输入，Zipf 启用时显示可能不支持的七秒提示但不移除修饰器。
2026-09-05 更新：单语数量增至一百种，新增 Frisian（`frisian`）：基础与 1k 参考配置均定义 `bcp47: fy-FY`，没有 RTL、连写、`noLazyMode` 或词频排序标记。Typebar 使用原创 Frisian 词流与四档引语、LTR 空格提交；知识短文按 BCP 首段使用 `fy`，系统朗读精确使用 `fy-FY`。该语言进入已测试的默认/自选多语混排、预设、归档、社区投稿、成绩及服务端排行榜全路径；保留用户显式选择的简化输入，Zipf 启用时显示可能不支持的七秒提示但不移除修饰器。
2026-09-05 更新：单语数量增至一百零一种，新增 Zulu（`zulu`）：固定参考配置没有 BCP-47、RTL、连写、`noLazyMode` 或词频排序标记。Typebar 使用原创 isiZulu 词流与四档引语、LTR 空格提交；知识短文与系统朗读严格复用缺省 `en` 与 `en-US`，不补造 Zulu 代码。该语言进入已测试的默认/自选多语混排、预设、归档、社区投稿、成绩及服务端排行榜全路径；保留用户显式选择的简化输入，Zipf 启用时显示可能不支持的七秒提示但不移除修饰器。
2026-09-05 更新：单语数量增至一百零二种，新增 Hawaiian（`hawaiian`）：基础与 1k 参考配置均定义 `rightToLeft: false`、`bcp47: haw` 与 `orderedByFrequency: true`，没有连写或 `noLazyMode`。Typebar 使用原创 Hawaiian 词流与四档引语、LTR 空格提交；知识短文与系统朗读均精确使用 `haw`。该语言进入已测试的默认/自选多语混排、预设、归档、社区投稿、成绩及服务端排行榜全路径；保留用户显式选择的简化输入与 Zipf 高频词。
2026-09-05 更新：单语数量增至一百零三种，新增 Kabyle（`kabyle`）：基础、1k、2k、5k 与 10k 参考配置均定义 `bcp47: kab` 与 `orderedByFrequency: false`，没有 RTL、连写或 `noLazyMode`。Typebar 使用原创 Taqbaylit 词流与四档引语、LTR 空格提交；知识短文与系统朗读均精确使用 `kab`。该语言进入已测试的默认/自选多语混排、预设、归档、社区投稿、成绩及服务端排行榜全路径；保留用户显式选择的简化输入，Zipf 启用时显示不支持的七秒提示但不移除修饰器。
| `burstHeatmap` | `showWordBurstHeatmap` | 已映射。 |
| `difficulty` | `Difficulty` | 已映射。 |
| `quickRestart` | `QuickRestartKey` | 已映射；保留 macOS 快捷键与长测试保护。 |
| `repeatQuotes` | `repeatQuotes` | 已映射。 |
| `resultSaving` | `saveCompletedResults` | 已映射。 |
| `blindMode` | `blindMode` | 已映射。 |
| `alwaysShowWordsHistory` | `alwaysShowWordsHistory` | 已映射。 |
| `singleListCommandLine` | `commandPaletteListMode` | 部分；原生命令面板使用单列表/分组导航而非网页命令行。 |
| `minWpm` | `minimumWpm` | 已映射。 |
| `minWpmCustomSpeed` | `minimumWpm` | 已映射；零值关闭。 |
| `minAcc` | `minimumAccuracy` | 已映射。 |
| `minAccCustom` | `minimumAccuracy` | 已映射；零值关闭。 |
| `minBurst` | `minimumWordBurstMode` | 已映射；支持关闭/固定/弹性。 |
| `minBurstCustomSpeed` | `minimumWordBurstWpm` | 已映射。 |
| `britishEnglish` | `englishVariant` | 已映射；使用 Typebar 自有英式词库。 |
| `funbox` | `TestModifier` | 已映射；48 项逐项证据见 `OFFICIAL_FUNBOX_AUDIT.md`。 |
| `customLayoutfluid` | `layoutFluidLayouts` | 已映射；官方上限 15，当前 22 个原创内置布局可任选至多 15 个进入原生序列。 |
| `customPolyglot` | `mixedLanguageComponents` | 部分；自选组合已实现，候选语言仅限 Typebar 原创语言集。 |
| `freedomMode` | `freedomMode` | 已映射。 |
| `strictSpace` | `strictSpace` | 已映射。 |
| `oppositeShiftMode` | `oppositeShiftMode` | 已映射。 |
| `stopOnError` | `stopOnErrorMode` | 已映射；使用明确的 off/word/letter 模式。 |
| `deleteOnError` | `deleteOnErrorMode` | 已映射；使用明确的 off/letter/letter hard/word/word hard 模式。 |
| `confidenceMode` | `confidenceMode` | 已映射。 |
| `quickEnd` | `quickEnd` | 已映射。 |
| `indicateTypos` | `typoIndicatorStyle` | 已映射。 |
| `compositionDisplay` | `compositionDisplayStyle` | 已映射。 |
| `hideExtraLetters` | `hideExtraLetters` | 已映射。 |
| `lazyMode` | `TestModifier.lazyLatin`、Arabic 快速输入偏好 | 部分；语义为提示文本简化重音/连字，当前以显式练习修饰器而非全局开关呈现。Arabic 另有默认开启、可持久化关闭的快速输入偏好，进入 Arabic 时自动加入该修饰器，并以独立 Unicode 归一化省略短元音、tanwin、shadda、sukun 与常见 alef 变体；该自动行为不影响其他语言。依据固定参考版本的 `noLazyMode`，非自定义模式会禁用 English、Hebrew、Persian、Urdu、Tamil、Hindi、Gujarati、Bangla、Thai、Nepali、Kannada、Telugu、Malayalam、Sanskrit、Greeklish、Dutch、Filipino、Indonesian、Serbian Cyrillic、Bulgarian、Macedonian、Kazakh、中日韩／日语罗马字、Ukrainian 与 Ukrainian Latin，以及所有代码练习的该修饰器；自定义文本仍可使用。可配置多语练习只有至少一个选择的组成语言允许时才保留它。 |
| `lazyMode`（Pashto 补充） | `TestModifier.lazyLatin` | 固定参考的 Pashto 定义 `noLazyMode: true`；因此非自定义 Pashto 练习禁用简化输入，自定义文本仍允许用户显式启用，且不继承标准 Arabic 的自动快捷偏好。 |
| `lazyMode`（Sindhi 补充） | `TestModifier.lazyLatin` | 固定参考的 Sindhi 未定义 `noLazyMode`；因此可保留用户显式选择的简化输入，但不会继承仅针对标准 Arabic 的自动快捷偏好。 |
| `layout` | `KeyboardInputLayout` | 部分；系统输入源为默认，22 种原创物理布局和用户自写四行布局（可选等长 Shift 图例）的基础映射可显式模拟；官方全部命名布局尚未覆盖。 |
| `codeUnindentOnBackspace` | `codeUnindentOnBackspace` | 已映射。 |
| `soundVolume` | `soundVolume` | 已映射。 |
| `playSoundOnClick` | `playKeyclickSound`、`clickSoundStyle` | 部分；提供四种 macOS 系统音型，而非网页端全部音效选择。 |
| `playSoundOnError` | `playErrorBeep`、`errorSoundStyle` | 部分；提供四种 macOS 系统音型。 |
| `playTimeWarning` | `timeWarningOffset`、`timeWarningSoundStyle` | 部分；保留时间点与四种原生音型。 |
| `smoothCaret` | `smoothCaretMotion` | 已映射。 |
| `caretStyle` | `caretStyle` | 部分；以原创原生矢量样式实现相同可见角色。 |
| `paceCaret` | `paceGuideMode` | 已映射；含 custom/PB/tag PB/average/daily/last。 |
| `paceCaretCustomSpeed` | `paceGuideCustomWpm` | 已映射。 |
| `paceCaretStyle` | `paceCaretStyle` | 部分；以原创原生矢量样式实现。 |
| `repeatedPace` | `repeatedPace` | 已映射。 |
| `timerStyle` | `liveProgressStyle` | 已映射；含 off/bar/text/mini/flash 文本与迷你。 |
| `liveSpeedStyle` | `liveSpeedStyle` | 已映射。 |
| `liveAccStyle` | `liveAccuracyStyle` | 已映射。 |
| `liveBurstStyle` | `liveBurstStyle` | 已映射。 |
| `timerColor` | `liveStatsColor` | 部分；按原生主题语义提供强调色/次要/正文等选项。 |
| `timerOpacity` | `liveStatsOpacity` | 已映射；四档 25/50/75/100%。 |
| `highlightMode` | `promptHighlightMode` | 已映射。 |
| `typedEffect` | `typedCharacterEffect` | 已映射。 |
| `tapeMode` | `practiceTapeMode` | 已映射。 |
| `tapeMargin` | `practiceTapeMargin` | 已映射；以 0–1 原生比例保存。 |
| `smoothLineScroll` | `smoothPracticeLineScroll` | 已映射。 |
| `showAllLines` | `showAllPracticeLines` | 已映射。 |
| `alwaysShowDecimalPlaces` | `alwaysShowDecimalPlaces` | 已映射。 |
| `typingSpeedUnit` | `typingSpeedUnit` | 已映射。 |
| `startGraphsAtZero` | `startGraphsAtZero` | 已映射。 |
| `maxLineWidth` | `practiceLineWidth`、`customPracticeLineColumns` | 已映射；以原生列宽/自适应表达。 |
| `fontSize` | `fontSize` | 已映射。 |
| `fontFamily` | `practiceFont`、本机字体名称/导入 | 部分；使用 macOS 已安装或用户导入字体，不复用网页字体资产。 |
| `keymapMode` | `keyboardGuideMode` | 已映射。 |
| `keymapLayout` | `keyboardGuideLayoutSource`、`keyboardLayout`、自定义图 | 部分；可选内置、当前 macOS 输入源或用户自写 Unicode 图；239 份官方命名资产不打包。 |
| `keymapStyle` | `keyboardGuideStyle` | 已映射。 |
| `keymapLegendStyle` | `keyboardGuideLegendStyle` | 已映射。 |
| `keymapKeys` | `keyboardGuideKeysMode` | 已映射。 |
| `keymapSize` | `keyboardGuideScale` | 已映射。 |
| `flipTestColors` | `flipTestColors` | 已映射。 |
| `colorfulMode` | `colorfulMode` | 已映射。 |
| `customBackground` | `customBackgroundURL`、本地图片 | 已映射；额外支持私有本机背景。 |
| `customBackgroundSize` | `customBackgroundFit` | 已映射。 |
| `customBackgroundFilter` | `customBackgroundFilter` | 已映射。 |
| `autoSwitchTheme` | `followSystemTheme` | 已映射。 |
| `themeLight` | `systemLightTheme` | 已映射。 |
| `themeDark` | `systemDarkTheme` | 已映射。 |
| `randomTheme` | `randomThemeMode` | 已映射。 |
| `favThemes` | `favoriteThemeIDs` | 已映射。 |
| `theme` | `theme`、`activeCustomThemeID` | 已映射。 |
| `customTheme` | `customThemes` | 已映射。 |
| `customThemeColors` | `CustomThemeDefinition` | 已映射；可创建、编辑、应用和归档原创背景、面板、强调色、提示文字、辅助文字、光标、淡化已输入、错误、额外输入与彩色模式两类反馈色。字段与默认色均为 Typebar 原生定义，不复用网页数组或颜色资产。 |
| `showKeyTips` | `showKeyTips` | 已映射。 |
| `showOutOfFocusWarning` | `showFocusWarning` | 已映射。 |
| `capsLockWarning` | `showCapsLockWarning` | 已映射。 |
| `showAverage` | `showAverage` | 已映射。 |
| `showPb` | `showPersonalBest` | 已映射。 |
| `accountChart` | `historyChartVisibility` | 部分；本机历史的速度、准确率、10/100 次均值独立开关，非网页账户图。 |
| `monkey` | `showTypingCompanion` | 部分；原创手部提示，不复制网页猴子形象或资产。 |
| `monkeyPowerLevel` | `typingPowerMode` | 部分；原创粒子能量效果，档位与形象不同。 |
| `ads` | 无 | 不适用；Typebar 的产品约束是无广告。 |

## 当前优先缺口

1. 官方 239 份命名 `keymapLayout` 资产与输入模拟尚未全部覆盖。当前策略优先使用 macOS 当前输入源（普通、Shift、Option、Shift+Option 四层标签，并通过 TIS 输入源切换通知刷新）、22 个原创内置模拟布局（含独立实现的 Greek Alphabetic · Typebar、Hungarian QWERTZ · Typebar、Russian、Ukrainian JCUKEN、Bulgarian Cyrillic · Typebar 与 Serbian Cyrillic · Typebar），以及可由用户自写四行/Shift 图例定义的基础映射，避免复制资产；仍需继续扩展原创输入映射覆盖。
2. 官方语言、词表、主题、字体和声音的完整目录不应复制。后续以原创或明确授权内容扩大用户可选范围，并逐项标注差异；语言候选、语义边界和准入条件见 `OFFICIAL_LANGUAGE_AUDIT.md`。
3. 网页账户页图表、猴子外观和广告设置不适合作为原生逐像素复刻目标；对用户可见意图的原生替代仍需设备验收。

## 本轮新增验证

- Russian JCUKEN 自动化测试覆盖 `ё`、`й`、`ж`、`э`、`я`、`ь`、逗号与 ISO `< >` 的提示高亮、普通/Shift 物理 keycode、反查 keycode；独立设置快照覆盖键盘图、输入模拟与 Layout Fluid 持久化。映射为 Typebar 原生实现，不导入参考布局 JSON。
- Ukrainian JCUKEN 自动化测试覆盖 `ґ`、`ї`、`і`、`є` 与 ISO `< >` 的提示高亮、普通/Shift 物理 keycode、反查 keycode，以及键盘图、输入模拟和 Layout Fluid 持久化。映射按 Typebar 自有定义编写，不读取或导入参考布局 JSON。
- Bulgarian Cyrillic · Typebar 自动化测试覆盖 Typebar 自写的 `я`、`ъ`、`щ`、`ч`、`ь` 与 ISO `< >` 提示高亮、普通/Shift 物理 keycode、反查 keycode，以及键盘图、输入模拟和 Layout Fluid 持久化；它不是官方或系统 BDS 布局的导入，用户可继续选择 macOS 当前输入源取得系统布局。
- Serbian Cyrillic · Typebar 自动化测试覆盖 Typebar 自写的 `љ`、`ђ`、`ћ`、`ж`、`џ` 与 ISO `< >` 提示高亮、普通/Shift 物理 keycode、反查 keycode，以及键盘图、输入模拟和 Layout Fluid 持久化；它不是官方或系统塞尔维亚语布局资产的导入，用户可继续选择 macOS 当前输入源取得系统布局。
- Hungarian QWERTZ · Typebar 自动化测试覆盖 Typebar 自写的 `á`、`é`、`í`、`ó`、`ö`、`ő`、`ú`、`ü`、`ű`、QWERTZ Y/Z 与练习标点的提示高亮、普通/Shift 物理 keycode、反查 keycode，以及键盘图、输入模拟和 Layout Fluid 持久化；它不导入官方或系统匈牙利语布局资产，未收录的死键和 Option 层继续交给 macOS 当前输入源。
- Greek Alphabetic · Typebar 自动化测试覆盖 Typebar 自写的二十四个基本 Greek 字母、七个重音元音、词末 `ς` 与练习标点的提示高亮、普通/Shift 物理 keycode、反查 keycode、原创词库字符覆盖，以及键盘图、输入模拟和 Layout Fluid 持久化；它不导入官方或系统希腊语布局资产，未收录字符、死键和 Option 层继续交给 macOS 当前输入源。
- 乌克兰语自动化测试覆盖原创词表中的 `ї`、`є`、`ґ`、四档原创引语、多语混排、弱项复练、`uk-UA` 朗读 locale 与 `uk` 百科入口；服务端测试覆盖成绩提交、语言筛选排行榜与引语投稿白名单，未读取或导入参考词表/内容。
- 乌克兰语 Latin 自动化测试覆盖全 ASCII 自创词流、四档原创引语、完整多语混排轮转、弱项复练、`uk-UA` 朗读 locale 与服务端投稿/排行榜白名单；参考流会保守留在离线内容，以免远端西里尔文本违反 Latin 承诺。
- Dutch 自动化测试覆盖自创词流（含 `één`）、四档原创引语、完整多语混排轮转、弱项复练、`nl-NL` 朗读 locale 与 `nl` 百科入口；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- Danish 自动化测试覆盖自创词流（含 `æ`、`ø`、`å`）、四档原创引语、完整多语混排轮转、弱项复练、`da-DK` 朗读 locale 与 `da` 百科入口；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- Norwegian Bokmål 自动化测试覆盖自创词流（含 `æ`、`ø`、`å`）、四档原创引语、完整多语混排轮转、弱项复练、`nb-NO` 朗读 locale 与 `no` 百科入口；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- Swedish 自动化测试覆盖自创词流（含 `å`、`ä`、`ö`）、四档原创引语、完整多语混排轮转、弱项复练、`sv-SE` 朗读 locale 与 `sv` 百科入口；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- Greek 自动化测试覆盖自创词流（含重音字符）、四档原创引语、完整多语混排轮转、弱项复练、`el-GR` 朗读 locale 与 `el` 百科入口；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- Greeklish 自动化测试覆盖自创 ASCII 词流、四档原创引语、完整多语混排轮转、弱项复练、`el-GR` 朗读 locale，以及阻止 `el` 百科文本替换的离线回退；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- Norwegian Nynorsk 自动化测试覆盖自创词流、四档原创引语、完整多语混排轮转、`nn-NO` 朗读 locale 与仅在明示启用时使用的 `nn` 百科入口；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- Afrikaans 自动化测试覆盖自创词流、四档原创引语、完整多语混排轮转、`af-ZA` 朗读 locale 与仅在明示启用时使用的 `af` 百科入口；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- Filipino 自动化测试覆盖自创词流、四档原创引语、完整多语混排轮转、`fil-PH` 朗读 locale 与仅在明示启用时使用的 `tl` 百科入口；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- Japanese Katakana 自动化测试覆盖自创片假名词流、无空格词界、四档原创引语、完整多语混排轮转、`ja-JP` 朗读 locale 与离线知识短文回退；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- Japanese Romaji 自动化测试覆盖自创 ASCII 罗马字词流、空格分词、四档原创引语、完整多语混排轮转、`ja-JP` 朗读 locale 与离线知识短文回退；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- Czech 自动化测试覆盖自创词流（含 `ř`、`ě`、`š`、`č`、`ž` 与 `ů`）、四档原创引语、完整多语混排轮转、弱项复练、`cs-CZ` 朗读 locale 与 `cs` 百科入口；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- Bulgarian 自动化测试覆盖自创西里尔词流（含 `ъ`、`щ`、`ю` 与 `я`）、四档原创引语、完整多语混排轮转、弱项复练、`bg-BG` 朗读 locale 与 `bg` 百科入口；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- Romanian 自动化测试覆盖自创词流（含 `ă`、`â`、`î`、`ș` 与 `ț`）、四档原创引语、完整多语混排轮转、弱项复练、`ro-RO` 朗读 locale 与 `ro` 百科入口；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- Finnish 自动化测试覆盖自创词流（含 `ä` 与 `ö`）、四档原创引语、完整多语混排轮转、弱项复练、`fi-FI` 朗读 locale 与 `fi` 百科入口；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- Estonian 自动化测试覆盖自创词流（含 `õ`、`ä`、`ö` 与 `ü`）、四档原创引语、完整多语混排轮转、弱项复练、`et-EE` 朗读 locale 与 `et` 百科入口；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- Icelandic 自动化测试覆盖自创词流（含 `ð`、`þ`、`æ` 与 `ö`）、四档原创引语、完整多语混排轮转、弱项复练、`is-IS` 朗读 locale 与 `is` 百科入口；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- Slovak 自动化测试覆盖自创词流（含 `á`、`ä`、`č`、`ď`、`ľ`、`ô`、`ŕ`、`š`、`ť`、`ý` 与 `ž`）、四档原创引语、完整多语混排轮转、弱项复练、`sk-SK` 朗读 locale 与 `sk` 百科入口；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- Slovenian 自动化测试覆盖自创词流（含 `č`、`š` 与 `ž`）、四档原创引语、完整多语混排轮转、弱项复练、`sl-SI` 朗读 locale 与 `sl` 百科入口；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- Croatian 自动化测试覆盖自创词流（含 `č`、`ć`、`đ`、`š` 与 `ž`）、四档原创引语、完整多语混排轮转、弱项复练、`hr-HR` 朗读 locale 与 `hr` 百科入口；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- Serbian 自动化测试覆盖自创西里尔词流（含 `љ`、`њ`、`ђ`、`ћ`、`џ`、`ч`、`ш` 与 `ж`）、四档原创引语、完整多语混排轮转、弱项复练、`sr-RS` 朗读 locale 与 `sr` 百科入口；Serbian Latin 同样覆盖四档原创离线拉丁引语、混排、弱项复练与 `sr-RS`，并拒绝百科替换以保持当前书写形式；服务端测试覆盖两者的投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- Hungarian 自动化测试覆盖自创词流（含 `á`、`é`、`í`、`ó`、`ö`、`ő`、`ú`、`ü`、`ű`）、四档原创引语、完整多语混排轮转、弱项复练、`hu-HU` 朗读 locale 与 `hu` 百科入口；服务端测试覆盖投稿、撤回、成绩提交与按语言排行，未读取或导入参考词表/内容。
- 完整客户端 `swift test` 通过 270 项、独立 Vapor 服务 `swift test` 通过 66 项；两次测试前 `pgrep -ax Typebar` 均无输出，未启动图形应用。
- `SystemKeyboardGuide` 的注入式测试验证四行 ANSI 物理键位、Shift 图例、下一键匹配字符及缺失键位的安全回退。
- 设置快照测试覆盖键盘图来源的持久化、恢复与旧归档默认回退。
- 自定义键盘输入映射测试覆盖 Unicode 字母普通/Shift 映射、用户定义的符号 Shift 图例、旧归档默认、Option 的系统回退、归档恢复和删除选中图后的安全回退。
- Discord 头像隐私测试覆盖默认不公开、显式开启、资料卡与 WPM/XP 榜显示、关闭后立即隐藏与非法哈希拒绝；客户端同时拒绝非 ASCII 标识与异常 CDN URL。
- 原创公开徽章测试覆盖服务端成绩派生、未解锁拒绝、显式选择/清除、公开资料与 WPM/XP 榜显示、旧字段省略及删除服务端成绩后的即时隐藏。
- 公开资料连续练习测试覆盖服务端 UTC 日界下的当前/最长连续派生、活动隐私开关联动隐藏，以及客户端对新旧资料响应的解码。
- 公开资料练习统计测试覆盖服务端从已接受成绩起止时间聚合累计时长，以及按随完成提交的重开次数派生开始次数；重复提交同一成绩 ID 不会重复累加，客户端对新旧资料响应安全解码。未完成且未提交练习与本机历史不进入该值。
- 引语长度与队列测试覆盖多选长度通过预设和 Typebar 配置链接保存、旧单长度配置迁移，以及同一候选集每轮不重复且避免立即重复当前引语；队列仅存于当前进程，不引入参考内容或实现。
- 服务公告测试覆盖公开读取、部署审核密钥发布/删除、计划日期往返、空白公告拒绝、原生完整日期/日期/相对时间占位符替换，以及本机普通公告关闭、置顶公告保留和服务端移除后的本机确认清理；不复制参考文案、样式或实现。
- 完整客户端 `swift test` 已通过 261 项测试；测试前 `pgrep -x Typebar` 无输出，未启动图形应用。
- 独立 Vapor 服务的 `swift test` 已通过 66 项测试，其中覆盖 GitHub/Google/Discord OAuth 的 PKCE 授权 URL、一次性 state、原生回调、注册/关联、提供商匹配重新验证、安全移除、Discord 头像公开隐私、原创公开徽章、公开连续练习/开始次数隐私及服务公告；测试前 `pgrep -x Typebar` 无输出，未启动图形应用。
- Maltese 审计只读取 `maltese.json` 与 `maltese_1k.json` 的元数据，不读取其中词表或引语文本。两者定义 `bcp47: mt`，不定义 RTL、连写、`noLazyMode` 或词频排序；实现因此使用独立自写的 Maltese 内容与 LTR 空格分词，知识短文和朗读均精确使用 `mt`。保留手动简化输入和 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- toki pona 审计只读取 `toki_pona.json`、`toki_pona_ku_suli.json` 与 `toki_pona_ku_lili.json` 的元数据，不读取其中词表或引语文本。三者定义 `noLazyMode: true`，不定义 BCP-47、RTL、连写或词频排序；实现因此使用独立自写的 toki pona 内容与 LTR 空格分词，知识短文和朗读严格使用 `en`／`en-US` 缺省路径。普通练习移除简化输入，自定义文本保留例外；Zipf 走未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Xhosa 审计只读取 `xhosa.json` 与 `xhosa_3k.json` 的元数据，不读取其中词表或引语文本。主 `xhosa` 定义 `rightToLeft: false` 与 `bcp47: xh`，而 `xhosa_3k` 不定义这些可选字段；参考的在线与朗读代码按当前词组读取，因此前者使用 `xh`、后者回退 `en`／`en-US`。Typebar 使用独立自写的 isiXhosa 内容和 LTR 空格分词；其用户可见主选择精确使用 `xh`，不导入任一参考词表或引语。保留手动简化输入与 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Tibetan 审计只读取 `tibetan.json` 与 `tibetan_1k.json` 的元数据，不读取其中词表或引语文本。两者均定义 `rightToLeft: false`、`joiningScript: true`、`noLazyMode: true` 与 `bcp47: bo-TI`，不定义词频排序。Typebar 使用独立自写的 Tibetan 内容与 LTR 空格分词，并以配置级 `joiningScript` 标记在单语或任一包含 Tibetan 的多语提示中保留 macOS 原生塑形、收紧行距及禁用逐字圆点替换。知识短文使用 `bo`，朗读精确使用 `bo-TI`；普通练习移除简化输入，自定义文本保留例外。Zipf 走未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Kyrgyz 审计只读取 `kyrgyz.json` 与 `kyrgyz_1k.json` 的元数据，不读取其中词表或引语文本。两者定义 `bcp47: ky-KY`，不定义 RTL、连写、`noLazyMode` 或词频排序；实现因此使用独立自写的 Kyrgyz 内容与 LTR 空格分词，知识短文按 BCP 首段使用 `ky`，朗读精确使用 `ky-KY`。保留手动简化输入和 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Yiddish 审计只读取 `yiddish.json` 的元数据，不读取其中词表或引语文本。它定义 `rightToLeft: true`、`joiningScript: true` 与 `bcp47: yi`，不定义 `noLazyMode` 或词频排序；实现因此使用独立自写的 Yiddish 内容、RTL 空格分词及原生塑形／圆点逐字替换保护，知识短文和朗读均精确使用 `yi`。保留手动简化输入和 Zipf 未知提示，并进入社区投稿、成绩及排行榜；尚未完成专门交互验收的双向多语混排明确排除。
- Udmurt 审计只读取 `udmurt.json` 的元数据，不读取其中词表或引语文本。它只定义名称，不定义 BCP-47、RTL、连写、`noLazyMode` 或词频排序；实现因此使用独立自写的 Udmurt 内容与 LTR 空格分词，知识短文和朗读严格使用 `en`／`en-US` 缺省路径。保留手动简化输入和 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Yoruba 审计只读取 `yoruba_1k.json` 的元数据，不读取其中词表或引语文本。它只定义名称，不定义 BCP-47、RTL、连写、`noLazyMode` 或词频排序；实现因此使用独立自写的含声调 Yoruba 内容与 LTR 空格分词，知识短文和朗读严格使用 `en`／`en-US` 缺省路径。保留手动简化输入和 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Swahili 审计只读取 `swahili_1k.json` 的元数据，不读取其中词表或引语文本。它定义 `noLazyMode: true`，不定义 BCP-47、RTL、连写或词频排序；实现因此使用独立自写的 Swahili 内容与 LTR 空格分词，知识短文和朗读严格使用 `en`／`en-US` 缺省路径。普通练习移除简化输入，自定义文本保留例外；Zipf 走未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Kinyarwanda 审计只读取 `kinyarwanda.json` 的元数据，不读取其中词表或引语文本。它定义 `noLazyMode: true`、`orderedByFrequency: true` 与 `bcp47: rw-RW`，不定义 RTL 或连写；实现因此使用独立自写的 Kinyarwanda 内容与 LTR 空格分词，知识短文按 BCP 首段使用 `rw`，朗读精确使用 `rw-RW`。普通练习移除简化输入，自定义文本保留例外；Zipf 使用自有高频词，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Shona 审计只读取 `shona.json` 和 `shona_1k.json` 的元数据，不读取其中词表或引语文本。它们只定义名称，不定义 BCP-47、RTL、连写、`noLazyMode` 或词频排序；实现因此使用独立自写的 Shona 内容与 LTR 空格分词，知识短文和朗读严格使用 `en`／`en-US` 缺省路径。保留手动简化输入和 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Belarusian Łacinka 审计只读取 `belarusian_lacinka.json` 和 `belarusian_lacinka_1k.json` 的元数据，不读取其中词表或引语文本。它们定义 `noLazyMode: false`，不定义 BCP-47、RTL、连写或词频排序；实现因此使用独立自写的拉丁转写内容与 LTR 空格分词，知识短文和朗读严格使用 `en`／`en-US` 缺省路径。保留手动简化输入和 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Crimean Tatar 审计只读取 `tatar_crimean.json`、`tatar_crimean_1k.json`、`tatar_crimean_5k.json`、`tatar_crimean_10k.json`、`tatar_crimean_15k.json`，以及对应五个 `tatar_crimean_cyrillic*` 配置的元数据，不读取任何词表或引语文本。十个配置均定义 `noLazyMode: true` 与 `bcp47: crh-CRH`，不定义 RTL、连写或词频排序；实现将拉丁与西里尔作为不可互换的独立用户可见选择，以各自原创内容走 LTR 空格分词、`crh` 知识短文和 `crh-CRH` 朗读。普通练习移除简化输入而自定义文本保留例外，Zipf 走未知提示；两者均进入默认／自选多语混排、社区投稿、成绩和排行榜。
- Klingon 审计只读取 `klingon.json` 与 `klingon_1k.json` 的元数据，不读取其中词表或引语文本。两个配置均定义 `bcp47: tlh`，不定义 RTL、连写、`noLazyMode` 或词频排序；实现因此以独立自写的大小写敏感、词内撇号内容走 LTR 空格分词，知识短文和朗读均精确使用 `tlh`。未定义 `noLazyMode`，故保留简化输入；词内 `'` 被保留为目标词组成部分而不按装饰标点规范化；Zipf 走未知提示，并进入默认／自选多语混排、社区投稿、成绩和排行榜。
- Quenya 审计只读取 `quenya.json` 的元数据，不读取其中词表或引语文本。配置未定义 BCP-47、RTL、连写、`noLazyMode` 或词频排序；实现因此以独立自写内容走 LTR 空格分词，知识短文和朗读严格使用 `en`／`en-US` 缺省路径。保留简化输入；Zipf 走未知提示，并进入默认／自选多语混排、社区投稿、成绩和排行榜。
- Viossa 审计只读取 `viossa.json` 与 `viossa_njutro.json` 的元数据，不读取其中词表或引语文本。两者均未定义 BCP-47、RTL 或连写，且均定义 `orderedByFrequency: false`；实现以两套独立、明示为 Typebar 原创练习 idiolect 的内容走 LTR 空格分词，知识短文和朗读严格使用 `en`／`en-US` 缺省路径，Zipf 显示不支持提示。基础 Viossa 未定义 `noLazyMode`，故保留简化输入；Njutro 定义 `noLazyMode: true`，普通练习禁用简化输入而自定义文本保留例外。两者均进入默认／自选多语混排、社区投稿、成绩和排行榜。
- Māori 审计只读取 `maori_1k.json` 的元数据，不读取其中词表或引语文本。配置未定义 BCP-47、RTL、连写、`noLazyMode` 或词频排序；实现以保留 macron 的独立自写内容走 LTR 空格分词，知识短文和朗读严格使用 `en`／`en-US` 缺省路径。保留简化输入；Zipf 走未知提示，并进入默认／自选多语混排、社区投稿、成绩和排行榜。
- Lojban 审计只读取 `lojban_gismu.json` 与 `lojban_cmavo.json` 的元数据，不读取其中词表或引语文本。两者均定义 `noLazyMode: true`，不定义 BCP-47、RTL、连写或词频排序；实现以独立自写的根词与结构词内容走 LTR 空格分词，后者保留 `.` 与 `'` 的目标字符语义。知识短文和朗读严格使用 `en`／`en-US` 缺省路径；普通练习禁用简化输入而自定义文本保留例外，Zipf 走未知提示，并进入默认／自选多语混排、社区投稿、成绩和排行榜。
