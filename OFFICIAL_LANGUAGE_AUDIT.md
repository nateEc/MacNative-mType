# 官方语言覆盖审计

## 范围与判定

- 参考版本：Monkeytype `91bd24bb8513785c7364cbea29296ff7adafac41`。
- 盘点入口：`packages/schemas/src/languages.ts` 的 `LanguageSchema`，以及对应的 `frontend/static/languages/` 配置文件。该版本 schema 有 446 个语言 ID，目录也有 446 个 JSON 模块。
- 446 不是 446 种独立自然语言：其中包含同语言的词表规模（如 `_1k` / `_10k`）、书写或罗马化变体，以及代码练习标识。本审计以用户可见的语言、书写方式和输入排版语义为单位。
- Typebar 不复制参考项目的代码、JSON、词表、引语、字体、布局或主题资产。此处的“已覆盖”仅表示已用原创内容和原生功能重建可见意图，绝不表示数据一对一迁移或全面同质化。

## 机器可读总账

`Compatibility/official-languages.json` 由 `Scripts/generate-official-language-audit.rb` 从固定提交的 schema ID 与 Typebar 本地枚举重新生成。生成器只读取 `packages/schemas/src/languages.ts` 和 `Sources/Typebar/TypingEngine.swift`，不读取 `frontend/static/languages/*.json`，因此清单只含标识和映射元数据，不含官方词表、引语、字体或标点内容。

446 个官方 ID 当前严格分区为：222 个 Typebar 独立原生选择、213 个数字词表规模变体（由同语言的已有原生选择表达，但没有对应的独立规模选项），以及 11 个尚无原生选择的配置。11 个缺口是 `english_old`、`french_bitoduc`、`russian_contractions`、`russian_contractions_1k`、`tamil_old`、`toki_pona_ku_suli`、`toki_pona_ku_lili`、`twitch_emotes`、`league_of_legends`、`typing_of_the_dead` 和 `pokemon_1k`。因此当前语言面很广，但尚不能宣称官方配置选择完全等价。

## 已覆盖的原生语言面

当前语言目录：152 个可单独练习的语言或书写方式、70 个代码选择和 2 个混合入口。152 个单语入口均支持 Typebar 自有引语；代码目录最新增加 Dockerfile。较早逐项补充中的数量只记录当时状态，当前数字以本段及文末最新更正为准。

| 语义类别 | 已重写的原生行为 | 边界 |
| --- | --- | --- |
| 从右到左 | Arabic、Egyptian Arabic、Moroccan Arabic、Pashto、Sindhi、Hebrew、Persian、Urdu、Central Kurdish 使用 macOS 输入源与原生双向排版；三种 Arabic、Pashto、Sindhi 与 Central Kurdish 同时使用系统原生连写字形；均不进入默认多语混排。 | 混合双向段落须有专门交互验收后才会启用。 |
| 连写、简化输入 | Tamil、Hindi、Gujarati、Bangla、Nepali、Kannada、Telugu、Malayalam、Sanskrit、Khmer、Burmese 与上述 RTL 语言均保留组合输入且按参考禁用简化输入；Sinhala、Lao 与 Amharic 也保留原生脚本输入，但参考未设 `noLazyMode`，因此不强制禁用。上述 LTR 语言均可参与多语混排。 | 不导入参考词表或简化规则。 |
| Thai 词界 | Thai 配置是 LTR、`noLazyMode: true`、`th-TH`，未标记 RTL 或 `joiningScript`；官方生成器除 `nospace` 修饰器外一律追加空格提交符。Typebar 因此使用原创 Thai 词元的空格提交路径与正常 macOS 输入。 | 不按自然书写习惯猜测无空格交互；该决定以参考实际生成器和客户端测试为准。 |
| 缺少 BCP-47 | Armenian、Georgian、Mongolian 与 Marathi 仅设置 `noLazyMode: true`；Lithuanian 没有 BCP-47、RTL、连写或 `noLazyMode` 标记，Albanian 仅定义名称，Bosnian 只额外定义 `orderedByFrequency: true`。七者官方百科实现均回退至 `en`，朗读回退至 `en-US`。Typebar 使用相同默认分支并固定测试。 | 不臆造语言、地区、朗读或百科代码。 |
| Esperanto 书写体系 | 标准、X-sistemo 与 H-sistemo 是三个独立参考语言 ID；标准只标记 `orderedByFrequency: true`，X 只标记 `noLazyMode: true`，H 同时标记二者。三者均没有 BCP-47、RTL 或连写，因此知识短文／朗读均使用 `en`／`en-US`；标准保留 Unicode 和简化输入，X/H 保持 ASCII 转写并禁用简化输入。 | 不导入参考词表或从一种书写自动替换另一种。 |
| Latin 缺省配置 | `latin` 仅定义名称，不含 BCP-47、RTL、连写、`noLazyMode` 或词频排序。Typebar 因此使用 LTR 空格分词、保留简化输入，并使知识短文／朗读分别回退 `en`／`en-US`；Zipf 显示七秒可能不支持提示而不移除修饰器。 | 不补造 `la` 或地区代码，也不导入参考词表。 |
| Friulian BCP-47 | `friulian` 定义 `bcp47: fur`，未设 RTL、连写、`noLazyMode` 或词频排序。Typebar 使用 LTR 空格分词、保留简化输入，并使知识短文／朗读均精确使用 `fur`；Zipf 显示七秒可能不支持提示而不移除修饰器。 | 不导入参考词表或补造地区代码。 |
| Malagasy 缺省配置 | `malagasy` 仅定义 `noLazyMode: true`，不含 BCP-47、RTL、连写或词频排序。Typebar 因此使用 LTR 空格分词、禁用简化输入，并使知识短文／朗读分别回退 `en`／`en-US`；Zipf 显示七秒可能不支持提示而不移除修饰器。 | 不补造 `mg` 或地区代码，也不导入参考词表。 |
| Welsh 缺省配置 | `welsh` 仅定义名称，不含 BCP-47、RTL、连写、`noLazyMode` 或词频排序。Typebar 因此使用 LTR 空格分词、保留简化输入，并使知识短文／朗读分别回退 `en`／`en-US`；Zipf 显示七秒可能不支持提示而不移除修饰器。 | 不补造 `cy` 或地区代码，也不导入参考词表。 |
| Hausa BCP-47 | `hausa` 定义 `bcp47: ha`，未设 RTL、连写、`noLazyMode` 或词频排序。Typebar 使用 LTR 空格分词、保留简化输入，并使知识短文／朗读均精确使用 `ha`；Zipf 显示七秒可能不支持提示而不移除修饰器。 | 不导入参考词表或补造地区代码。 |
| Tatar BCP-47 与词频 | `tatar` 定义 `bcp47: tt` 与 `orderedByFrequency: true`，未设 RTL、连写或 `noLazyMode`。Typebar 使用 LTR 空格分词、保留简化输入，并使知识短文／朗读均精确使用 `tt`；Zipf 保持可用且不显示警告。 | 不导入参考词表或补造地区代码。 |
| Uzbek BCP-47 | `uzbek` 定义 `rightToLeft: false` 与 `bcp47: uz-UZ`，未设连写、`noLazyMode` 或词频排序。Typebar 使用 LTR 空格分词、保留简化输入，知识短文按首段使用 `uz`，朗读精确使用 `uz-UZ`；Zipf 显示七秒可能不支持提示而不移除修饰器。 | 不导入参考词表或补造地区代码。 |
| Swiss German 专用分支 | `swiss_german` 定义 `bcp47: de-CH`，没有 RTL、连写、`noLazyMode` 或词频排序。源码将词流／引语读取转向 German，并在可见词中把 `ß` 替换为 `ss`；社区投稿选择排除该组。Typebar 以自有 German 内容做同样派生和转换，知识短文／朗读使用 `de`／`de-CH`；Zipf 显示未知提示且不移除修饰器。 | 不导入参考词表、引语、German 引语或布局资产；Swiss German 仍可作为成绩与排行榜筛选。 |
| Zipf 词频状态 | `orderedByFrequency: true` 时无提示，`false` 时显示七秒“未按频率排序”提示，缺失时显示七秒“可能不支持”提示；提示不移除 Zipf。Bemba 与 Kabyle 使用明确 `false` 路径，Bosnian、Esperanto、Esperanto H、Tatar、Oromo、Bashkir 与 Hawaiian 使用明确 `true` 路径，Esperanto X、Latin、Friulian、Malagasy、Welsh、Hausa、Uzbek、Macedonian、Kazakh、Vietnamese、Jyutping、Pinyin、Euskera、Frisian、Zulu、Western Armenian、Maltese、toki pona、Xhosa、Tibetan、Kyrgyz、Udmurt、Yoruba、Yiddish 与 Swiss German 使用未知路径。 | 使用自有词表排序，不导入参考词表。 |
| 无空格词界 | 简体／繁体中文、日语平假名与片假名走无空格的原生词界与计分路径。 | 仅在已验证脚本上启用，不能由语言名称推断。 |
| 罗马化／替代书写 | Greeklish、Ukrainian Latin、Japanese Romaji 使用原创 ASCII 离线内容，且不会被在线原文替换为另一书写方式。 | 不把参考项目的变体词表纳入应用。 |
| 代码 | 70 个代码选择以原创短片段覆盖缩进、输入、回放与结果路径；Dockerfile 使用虚构镜像和本地练习路径，保持 `noLazyMode` 的字面输入语义。 | 标识可参考公开语言目录；所有片段、标签组合与 UI 均由 Typebar 自写。 |

每个单语均有：Typebar 自有练习词流、四档引语、会话构造测试；能够安全获取在线百科短文的语言还使用对应语言入口和原生朗读 locale。服务端同时验证投稿白名单、撤回、成绩提交和按语言排行榜，不将客户端新语言视为孤立功能；Swiss German 的例外路径明确拒绝投稿但接受成绩与排行榜筛选。

## 有意不按 ID 一一复刻的部分

| 官方目录形式 | Typebar 策略 | 原因 |
| --- | --- | --- |
| `_1k`、`_5k`、`_10k` 等词表规模 | 不作为独立语言选择；以原创小型词流和可重复生成策略练习。 | 导入同规模词表会复制参考数据，且规模不是新的输入语义。 |
| `*_romanized`、音译或脚本变体 | 仅在能提供清晰、稳定、原创的独立练习承诺时实现。 | 显示名称相近不代表同一内容、输入法或在线来源可安全共用。 |
| 官方语言 JSON 的 `words`、字体和标点数据 | 不导入。 | 保持纯重写与许可边界清晰。 |
| 11 个尚无原生选择的配置 | 不先占位；准确清单由机器总账固定。 | 每项要先确认可见语义、输入法、内容来源和服务端数据面；不能仅凭 ID 猜测实现。 |

## 自动化守卫

- `testPinnedOfficialLanguageCoverageIsPartitionedAndResolvable` 固定 446／222／213／11 守恒关系、分区互斥、11 个明确缺口、每个映射可解析以及 222 个非混合原生选择的一一覆盖；生成器还会拒绝错误参考提交和意外数量变化。
- `testEverySingleLanguageHasAnOriginalExtendedQuoteThatBuildsACompleteSession` 直接枚举 `TypingLanguage.allCases`，保证任何新增的单语都有自有词流、超过 120 字的原创 extended 引语，并能构造完整 quote session。
- 多语测试检查默认候选集、各语言轮转与候选数量；Arabic、Hebrew、Persian、Urdu、Yiddish 与 Central Kurdish 等 RTL 语言明确被排除，所有经审核的 LTR 单语均被包含；当前守卫固定 141 个候选，并明确覆盖各专项语言与书写变体。
- 每次新增语言同时覆盖客户端内容路径、显示／排版、朗读或在线来源边界，以及服务端语言白名单、投稿、撤回、成绩和排行榜；Swiss German 以固定源码要求的“投稿拒绝、成绩接受”边界替代一般投稿路径。
- Egyptian Arabic 审计读取 `arabic_egypt.json` 与 `arabic_egypt_1k.json` 的元数据，不读取其中词表或引语文本。两者定义 RTL、连写和 `bcp47: ar-EG`，不定义 `noLazyMode` 或词频排序；实现因此使用自有内容、原生 RTL/连写排版、`ar` 百科入口、`ar-EG` 朗读、手动可选简化输入和 Zipf 未知提示，并进入社区投稿、成绩及排行榜。
- Moroccan Arabic 审计读取 `arabic_morocco.json` 的元数据，不读取其中词表或引语文本。它定义 RTL、连写、`orderedByFrequency: false` 和 `bcp47: ar-MA`，不定义 `noLazyMode`；实现因此使用自有内容、原生 RTL/连写排版、`ar` 百科入口、`ar-MA` 朗读、手动可选简化输入和明确的 Zipf 不支持提示，并进入社区投稿、成绩及排行榜。
- Pashto 审计只读取 `pashto.json` 的元数据，不读取其中词表或引语文本。它定义 RTL、连写、`noLazyMode: true` 和 `bcp47: ps`，没有词频排序标记；实现因此使用自有内容、原生 RTL/连写排版、`ps` 百科入口和朗读，在非自定义练习禁用简化输入、在自定义文本保留该例外，并以未知状态提示 Zipf，同时进入社区投稿、成绩及排行榜。
- Sindhi 审计只读取 `sindhi.json` 的元数据，不读取其中词表或引语文本。它定义 RTL、连写、`orderedByFrequency: false` 和 `bcp47: sd`，不定义 `noLazyMode`；实现因此使用自有内容、原生 RTL/连写排版、`sd` 百科入口和朗读、手动可选简化输入和明确的 Zipf 不支持提示，并进入社区投稿、成绩及排行榜。
- Occitan 审计只读取 `occitan.json` 的元数据，不读取其中词表或引语文本。它定义 `bcp47: oc-FR`，不定义 RTL、连写、`noLazyMode` 或词频排序；实现因此使用自有内容、LTR 空格分词、`oc` 百科入口、`oc-FR` 朗读、手动可选简化输入和 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Oromo 审计只读取 `oromo.json` 的元数据，不读取其中词表或引语文本。它定义 `bcp47: om` 和 `orderedByFrequency: true`，不定义 RTL、连写或 `noLazyMode`；实现因此使用自有内容、LTR 空格分词、`om` 百科入口和朗读、手动可选简化输入及 Zipf 高频词，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Macedonian 审计只读取 `macedonian.json` 的元数据，不读取其中词表或引语文本。它只定义 `noLazyMode: true`，不定义 BCP-47、RTL、连写或词频排序；实现因此使用自有内容、LTR 空格分词、`en` 百科入口和 `en-US` 朗读、普通练习禁用简化输入且在自定义文本保留例外，以及 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Kazakh 审计只读取 `kazakh.json` 的元数据，不读取其中词表或引语文本。它只定义 `noLazyMode: true`，不定义 BCP-47、RTL、连写或词频排序；实现因此使用自有内容、LTR 空格分词、`en` 百科入口和 `en-US` 朗读、普通练习禁用简化输入且在自定义文本保留例外，以及 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Vietnamese 审计只读取 `vietnamese.json` 的元数据，不读取其中词表或引语文本。它不定义 BCP-47、RTL、连写、`noLazyMode` 或词频排序；实现因此使用自有内容、LTR 空格分词、`en` 百科入口和 `en-US` 朗读、手动可选简化输入及 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Jyutping 审计只读取 `jyutping.json` 的元数据，不读取其中词表或引语文本。它定义 `bcp47: zh-Hant`，不定义 RTL、连写、`noLazyMode` 或词频排序；实现因此使用自有 ASCII 加声调数字内容和 LTR 空格分词，本地词流不混入参考文本。知识短文按 BCP 首段使用 `zh` 且在返回汉字时按中文词界分词，系统朗读精确使用 `zh-Hant`；保留手动简化输入和 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Pinyin 审计只读取 `pinyin.json`、`pinyin_1k.json` 与 `pinyin_10k.json` 的元数据，不读取其中词表或引语文本。三者不定义 BCP-47、RTL、连写、`noLazyMode` 或词频排序；实现因此使用独立自写 ASCII 拼音内容与 LTR 空格分词，严格回退 `en` 百科入口和 `en-US` 朗读。保留手动简化输入和 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Western Armenian 审计只读取 `armenian_western.json` 与 `armenian_western_1k.json` 的元数据，不读取其中词表或引语文本。两者定义 `bcp47: hyw`，不定义 RTL、连写、`noLazyMode` 或词频排序；实现因此使用独立自写的西部亚美尼亚语正字法内容与 LTR 空格分词，知识短文和朗读均精确使用 `hyw`。保留手动简化输入和 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Bashkir 审计只读取 `bashkir.json` 的元数据，不读取其中词表或引语文本。它定义 `bcp47: ba` 和 `orderedByFrequency: true`，不定义 RTL、连写或 `noLazyMode`；实现因此使用独立自写的 Bashkir 西里尔内容与 LTR 空格分词，知识短文和朗读均精确使用 `ba`。保留手动简化输入与 Zipf 高频词，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Euskera 审计只读取 `euskera.json` 的元数据，不读取其中词表或引语文本。它定义 `rightToLeft: false` 与 `bcp47: eu`，不定义连写、`noLazyMode` 或词频排序；实现因此使用独立自写的 Basque 内容与 LTR 空格分词，知识短文和朗读均精确使用 `eu`。保留手动简化输入与 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Frisian 审计只读取 `frisian.json` 与 `frisian_1k.json` 的元数据，不读取其中词表或引语文本。两者定义 `bcp47: fy-FY`，不定义 RTL、连写、`noLazyMode` 或词频排序；实现因此使用独立自写的 Frisian 内容与 LTR 空格分词，知识短文按 BCP 首段使用 `fy`，朗读精确使用 `fy-FY`。保留手动简化输入和 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Zulu 审计只读取 `zulu.json` 的元数据，不读取其中词表或引语文本。它不定义 BCP-47、RTL、连写、`noLazyMode` 或词频排序；实现因此使用独立自写的 isiZulu 内容与 LTR 空格分词，知识短文和朗读严格使用 `en` 与 `en-US` 缺省分支。保留手动简化输入和 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Hawaiian 审计只读取 `hawaiian.json` 与 `hawaiian_1k.json` 的元数据，不读取其中词表或引语文本。两者定义 `rightToLeft: false`、`bcp47: haw` 与 `orderedByFrequency: true`，不定义连写或 `noLazyMode`；实现因此使用独立自写的 Hawaiian 内容与 LTR 空格分词，知识短文和朗读均精确使用 `haw`。保留手动简化输入和 Zipf 高频词，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Kabyle 审计只读取 `kabyle.json`、`kabyle_1k.json`、`kabyle_2k.json`、`kabyle_5k.json` 与 `kabyle_10k.json` 的元数据，不读取其中词表或引语文本。它们定义 `bcp47: kab` 与 `orderedByFrequency: false`，不定义 RTL、连写或 `noLazyMode`；实现因此使用独立自写的 Taqbaylit 内容与 LTR 空格分词，知识短文和朗读均精确使用 `kab`。保留手动简化输入与明确的 Zipf 不支持提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Maltese 审计只读取 `maltese.json` 与 `maltese_1k.json` 的元数据，不读取其中词表或引语文本。两者定义 `bcp47: mt`，不定义 RTL、连写、`noLazyMode` 或词频排序；实现因此使用独立自写的 Maltese 内容与 LTR 空格分词，知识短文和朗读均精确使用 `mt`。保留手动简化输入与明确的 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- toki pona 审计只读取 `toki_pona.json`、`toki_pona_ku_suli.json` 与 `toki_pona_ku_lili.json` 的元数据，不读取其中词表或引语文本。三者定义 `noLazyMode: true`，不定义 BCP-47、RTL、连写或词频排序；实现因此使用独立自写的 toki pona 内容与 LTR 空格分词，知识短文和朗读严格使用 `en`／`en-US` 缺省路径。普通练习移除简化输入，而自定义文本保留该例外；Zipf 走未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Xhosa 审计只读取 `xhosa.json` 与 `xhosa_3k.json` 的元数据，不读取其中词表或引语文本。主组定义 `rightToLeft: false` 与 `bcp47: xh`，3k 组不定义这些可选字段；参考代码按当前词组读取，故主组使用 `xh`、3k 组回退 `en`／`en-US`。Typebar 以独立自写的 isiXhosa 内容与 LTR 空格分词呈现用户可见主选择，并精确使用 `xh`；不导入任一参考词表或引语。保留手动简化输入与 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Tibetan 审计只读取 `tibetan.json` 与 `tibetan_1k.json` 的元数据，不读取其中词表或引语文本。两者定义 `rightToLeft: false`、`joiningScript: true`、`noLazyMode: true` 与 `bcp47: bo-TI`，不定义词频排序；实现以独立自写的 Tibetan 内容和 LTR 空格分词处理，并在单语或混有 Tibetan 的提示中保留 macOS 原生塑形、较紧行距和圆点逐字替换保护。知识短文与朗读分别精确使用 `bo` 与 `bo-TI`；普通练习移除简化输入而自定义文本保留例外。它进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Kyrgyz 审计只读取 `kyrgyz.json` 与 `kyrgyz_1k.json` 的元数据，不读取其中词表或引语文本。两者定义 `bcp47: ky-KY`，不定义 RTL、连写、`noLazyMode` 或词频排序；实现因此使用独立自写的 Kyrgyz 内容与 LTR 空格分词，知识短文按 BCP 首段使用 `ky`，朗读精确使用 `ky-KY`。保留手动简化输入和 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Yiddish 审计只读取 `yiddish.json` 的元数据，不读取其中词表或引语文本。它定义 `rightToLeft: true`、`joiningScript: true` 与 `bcp47: yi`，不定义 `noLazyMode` 或词频排序；实现因此使用独立自写的 Yiddish 内容、RTL 空格分词及原生塑形／圆点逐字替换保护，知识短文和朗读均精确使用 `yi`。保留手动简化输入和 Zipf 未知提示，并进入社区投稿、成绩及排行榜；尚未完成专门交互验收的双向多语混排明确排除。
- Udmurt 审计只读取 `udmurt.json` 的元数据，不读取其中词表或引语文本。它只定义名称，不定义 BCP-47、RTL、连写、`noLazyMode` 或词频排序；实现因此使用独立自写的 Udmurt 内容与 LTR 空格分词，知识短文和朗读严格使用 `en`／`en-US` 缺省路径。保留手动简化输入和 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- Yoruba 审计只读取 `yoruba_1k.json` 的元数据，不读取其中词表或引语文本。它只定义名称，不定义 BCP-47、RTL、连写、`noLazyMode` 或词频排序；实现因此使用独立自写的含声调 Yoruba 内容与 LTR 空格分词，知识短文和朗读严格使用 `en`／`en-US` 缺省路径。保留手动简化输入和 Zipf 未知提示，并进入默认／自选多语混排、社区投稿、成绩及排行榜。
- 2026-09-05 更正：当前单语总数为一百一十二种、默认／自选 LTR 多语候选为一百零二种。Swahili 审计只读取 `swahili_1k.json` 的元数据，不读取其中词表或引语文本；它定义 `noLazyMode: true`，不定义 BCP-47、RTL、连写或词频排序。因此 Typebar 以独立自写的 Swahili 内容走 LTR 空格分词和 `en`／`en-US` 缺省在线/朗读路径；普通练习移除简化输入而自定义文本保留例外，Zipf 使用未知提示，并已覆盖多语轮转、社区投稿、成绩和排行榜。
- 2026-09-05 更正：当前单语总数为一百一十三种、默认／自选 LTR 多语候选为一百零三种。Kinyarwanda 审计只读取 `kinyarwanda.json` 的元数据，不读取其中词表或引语文本；它定义 `noLazyMode: true`、`orderedByFrequency: true` 与 `bcp47: rw-RW`，不定义 RTL 或连写。因此 Typebar 以独立自写的 Kinyarwanda 内容走 LTR 空格分词，知识短文按 BCP 首段使用 `rw`，朗读精确使用 `rw-RW`；普通练习移除简化输入而自定义文本保留例外，Zipf 使用自有高频词，并已覆盖多语轮转、社区投稿、成绩和排行榜。
- 2026-09-05 更正：当前单语总数为一百一十四种、默认／自选 LTR 多语候选为一百零四种。Shona 审计只读取 `shona.json` 和 `shona_1k.json` 的元数据，不读取其中词表或引语文本；它们只定义名称，不定义 BCP-47、RTL、连写、`noLazyMode` 或词频排序。因此 Typebar 以独立自写的 Shona 内容走 LTR 空格分词和 `en`／`en-US` 缺省在线/朗读路径；保留简化输入与 Zipf 未知提示，并已覆盖多语轮转、社区投稿、成绩和排行榜。
- 2026-09-05 更正：当前单语总数为一百一十五种、默认／自选 LTR 多语候选为一百零五种。Belarusian Łacinka 审计只读取 `belarusian_lacinka.json` 和 `belarusian_lacinka_1k.json` 的元数据，不读取其中词表或引语文本；它们定义 `noLazyMode: false`，不定义 BCP-47、RTL、连写或词频排序。因此 Typebar 以独立自写的拉丁转写内容走 LTR 空格分词和 `en`／`en-US` 缺省在线/朗读路径；保留简化输入与 Zipf 未知提示，并已覆盖多语轮转、社区投稿、成绩和排行榜。
- 2026-09-05 更正：当前单语总数为一百一十七种、默认／自选 LTR 多语候选为一百零七种。Crimean Tatar 拉丁与西里尔书写审计分别只读取五个 `tatar_crimean*` 和五个 `tatar_crimean_cyrillic*` 配置的元数据，不读取词表或引语文本；十个配置均定义 `noLazyMode: true` 与 `bcp47: crh-CRH`，不定义 RTL、连写或词频排序。Typebar 以两套独立自写词流及各自四档引语保留书写选择，均使用 LTR 空格分词、`crh` 在线知识短文与 `crh-CRH` 朗读；普通练习移除简化输入而自定义文本保留例外，Zipf 走未知提示，并已覆盖多语轮转、社区投稿、成绩和排行榜。
- 2026-09-05 更正：当前单语总数为一百一十八种、默认／自选 LTR 多语候选为一百零八种。Klingon 审计只读取 `klingon.json` 与 `klingon_1k.json` 的元数据，不读取词表或引语文本；两者均定义 `bcp47: tlh`，不定义 RTL、连写、`noLazyMode` 或词频排序。Typebar 以独立自写的大小写敏感、词内撇号词流和四档引语处理 LTR 空格分词，在线知识短文和朗读均精确使用 `tlh`；保留简化输入，词内 `'` 不会按装饰标点剥离，Zipf 走未知提示，并已覆盖多语轮转、社区投稿、成绩和排行榜。
- 2026-09-05 更正：当前单语总数为一百一十九种、默认／自选 LTR 多语候选为一百零九种。Quenya 审计只读取 `quenya.json` 的元数据，不读取词表或引语文本；它未定义 BCP-47、RTL、连写、`noLazyMode` 或词频排序。Typebar 以独立自写词流和四档引语处理 LTR 空格分词，在线知识短文和朗读严格使用 `en`／`en-US` 缺省路径；保留简化输入，Zipf 走未知提示，并已覆盖多语轮转、社区投稿、成绩和排行榜。
- 2026-09-05 更正：当前单语总数为一百二十一种、默认／自选 LTR 多语候选为一百一十一种。Viossa 与 Viossa · Njutro 审计分别只读取 `viossa.json` 与 `viossa_njutro.json` 的元数据，不读取词表或引语文本；两者均未定义 BCP-47、RTL 或连写，均定义 `orderedByFrequency: false`。Typebar 以彼此独立、明示为原创练习 idiolect 的词流和各自四档引语处理 LTR 空格分词，在线知识短文和朗读严格使用 `en`／`en-US` 缺省路径；两者 Zipf 走不支持提示。Viossa 保留简化输入；Njutro 定义 `noLazyMode: true`，普通练习禁用简化输入而自定义文本保留例外，并已覆盖多语轮转、社区投稿、成绩和排行榜。
- 2026-09-05 更正：当前单语总数为一百二十二种、默认／自选 LTR 多语候选为一百一十二种。Māori 审计只读取 `maori_1k.json` 的元数据，不读取词表或引语文本；它未定义 BCP-47、RTL、连写、`noLazyMode` 或词频排序。Typebar 以保留长元音 macron 的原创词流和四档引语处理 LTR 空格分词，在线知识短文和朗读严格使用 `en`／`en-US` 缺省路径；保留简化输入，Zipf 走未知提示，并已覆盖多语轮转、社区投稿、成绩和排行榜。
- 2026-09-05 更正：当前单语总数为一百二十四种、默认／自选 LTR 多语候选为一百一十四种。Lojban 审计只读取 `lojban_gismu.json` 与 `lojban_cmavo.json` 的元数据，不读取词表或引语文本；两个配置均定义 `noLazyMode: true`，不定义 BCP-47、RTL、连写或词频排序。Typebar 以彼此独立的原创根词和结构词词流、各自四档引语处理 LTR 空格分词，cmavo 保留 `.` 与 `'` 的输入语义；在线知识短文和朗读严格使用 `en`／`en-US` 缺省路径，普通练习禁用简化输入而自定义文本保留例外，Zipf 走未知提示，并已覆盖多语轮转、社区投稿、成绩和排行榜。
- 2026-09-07 更正：当前单语总数为一百二十五种、默认／自选 LTR 多语候选为一百一十五种。Santali 审计只读取 `santali.json` 的名称与可选元数据字段，不读取词表或引语文本；固定配置仅定义 `bcp47: sat-IN`，未定义 RTL、连写、`noLazyMode` 或词频排序。Typebar 使用 Unicode Ol Chiki 的独立练习词流与四档自有文本，走 LTR 空格分词、`sat` 百科入口、`sat-IN` 系统朗读、显式简化输入和 Zipf 未知提示，并已覆盖多语轮转、社区投稿、撤回、成绩及排行榜。
- 2026-09-07 更正：当前单语总数为一百三十种、默认／自选 LTR 多语候选为一百二十种。新增 Bulgarian Latin、Nepali Romanized、Persian Romanized、Sanskrit Roman 与 Urdu Roman；审计只读取对应五个固定 JSON 的名称和元数据，不读取词表或引语。五者均为 LTR 空格词界并使用彼此独立的 Typebar 自写词流与四档文本，不宣称运行时可逆转写。Bulgarian Latin（`bg`）与 Persian Romanized（`fa`）按 `noLazyMode: true` 禁用简化输入；Nepali Romanized 未定义 BCP-47，严格回退 `en`／`en-US`；Sanskrit Roman 使用 `sa`；Urdu Roman 使用 `ur-Latn`，百科按基础语言请求 `ur`。Bulgarian Latin 与 Urdu Roman 的 `orderedByFrequency: false` 显示 Zipf 不支持，其余三项显示未知；五者均已覆盖多语轮转、社区投稿、撤回、成绩和排行榜。
- 2026-09-07 更正：当前单语总数为一百三十三种、默认／自选 LTR 多语候选为一百二十三种。Hinglish、Tanglish 与 Urdish 的固定配置均未定义 BCP-47、连写、`noLazyMode` 或词频排序，Tanglish 额外显式定义 `rightToLeft: false`；其余两项未定义方向，因此三者均按 LTR 空格词界实现。Typebar 为每项提供独立自写的拉丁字母代码混合词流和四档文本，不导入参考或网络语料，也不宣称拼写规范化；知识短文与系统朗读严格回退 `en`／`en-US`，保留简化输入并显示 Zipf 未知提示，且已覆盖多语轮转、社区投稿、撤回、成绩和排行榜。
- 2026-09-08 更正：当前单语总数为一百三十六种、默认／自选 LTR 多语候选为一百二十六种。Ἑλληνιστικὴ Κοινή按固定 `bcp47: el-GR` 使用 LTR 空格词界、`el` 百科入口、`el-GR` 朗读、可选简化输入与 Zipf 未知提示；Typebar 为其提供独立自写的多调希腊语词流和四档文本。Pig Latin 与 Lorem Ipsum 的固定配置均定义 `noLazyMode: true`；前者只对 Typebar 自有英语词流和引语做确定性首辅音簇转换，后者只使用 Typebar 自写的伪拉丁词流与文本，二者均禁用普通练习简化输入、使用 `en`／`en-US` 路径且显示 Zipf 未知提示。三者均进入多语轮转、社区投稿、撤回、成绩和排行榜；未读取或导入参考词表、引语、转换实现或资产。
- 2026-09-08 更正：当前单语总数为一百三十七种、默认／自选 LTR 多语候选为一百二十七种。新增 English · Five Letter，对应固定 `wordle` 目录的可见“五字符英语词”约束。审计只读取名称、可选元数据、词数和各词长度，不读取任何词值；固定配置没有 BCP-47、RTL、连写、`noLazyMode` 或词频排序。Typebar 使用独立自写的五字母英语词流与四档全五字母文本，按缺省 `en`／`en-US` 路径处理知识短文与朗读，保留简化输入并显示 Zipf 未知提示；它已进入多语轮转、社区投稿、撤回、成绩和排行榜。
- 2026-09-08 更正：当前单语总数为一百三十八种、默认／自选 LTR 多语候选为一百二十八种。新增 Kokanu；固定配置定义 `rightToLeft: false`、`bcp47: xxs-Lat` 与 `orderedByFrequency: false`，未定义连写或 `noLazyMode`。审计不读取参考词值或引语；拉丁转写词汇和 `le/o` 动词标记等语法边界来自 [Kokanu 官方语法](https://en.kokanu.com/reference/basic-grammar.html) 与 [官方词典](https://dictionary.kokanu.com/)，四档练习句由 Typebar 独立编写。实现使用 LTR 空格词界、`xxs` 知识短文路径、`xxs-Lat` 朗读标识、可选简化输入和 Zipf 不支持提示，并贯通多语轮转、社区投稿、撤回、成绩与排行榜。
- 2026-09-08 更正：当前单语总数为一百三十九种、默认／自选 LTR 多语候选为一百二十九种。新增 Likanu；固定配置定义 `rightToLeft: false`、`joiningScript: true`、`bcp47: xxs-Uixs` 与 `orderedByFrequency: false`，未定义 `noLazyMode`。字符、元音修饰、尾音 `n` 组合上划线及标点规则来自 [Kokanu 官方发音与书写说明](https://en.kokanu.com/reference/pronunciation.html)；Typebar 以独立音节解析器确定性转换自有 Kokanu 词流和四档文本，不读取参考词值、引语或转换代码。实现保留整段 Unicode 连写、LTR 空格词界、`xxs`／`xxs-Uixs` 在线与朗读路径、可选简化输入和 Zipf 不支持提示，并贯通多语轮转、社区投稿、撤回、成绩与排行榜。
- 2026-09-08 更正：当前单语总数为一百四十二种、默认／自选 LTR 多语候选为一百三十二种。新增 English · Commonly Misspelled、English · Contractions 与 English · Double Letter。固定配置均定义 `noLazyMode: true`、`orderedByFrequency: false`，未定义 RTL 或连写；Double Letter 额外定义 `bcp47: en-US`，其余两项走缺省 `en`／`en-US`。审计只读取名称、元数据、词数和长度范围，不读取任何参考词值；Typebar 分别以自写正确拼写词、全撇号缩写词和含相邻重复字符的词流及各自四档原创文本实现，并贯通混排、配置、预设、分享、归档、社区投稿、撤回、成绩与排行榜。
- 2026-09-08 更正：当前单语总数为一百四十四种、默认／自选 LTR 多语候选为一百三十四种。新增 English · Legal 与 English · Medical。Legal 固定配置未定义 RTL、连写、BCP-47、`noLazyMode` 或词频排序，因此使用 LTR、`en`／`en-US`、可选简化输入和 Zipf 未知提示；Medical 定义 `rightToLeft: false`、`bcp47: en-US`、`noLazyMode: true` 与 `orderedByFrequency: false`，因此禁用简化输入并显示 Zipf 不支持。审计不读取参考词值；两项均使用 Typebar 自写领域词流和四档文本，并贯通混排与全部客户端／服务端数据面。
- 2026-09-08 更正：当前单语总数为一百四十五种、默认／自选 LTR 多语候选为一百三十五种。新增 English · Shakespearean；固定配置仅定义 `noLazyMode: true`，未定义 RTL、连写、BCP-47 或词频排序，因此使用 LTR、`en`／`en-US`、禁用简化输入和 Zipf 未知提示。Typebar 使用自写古体代词、动词和副词词流以及四档仿古文本，不复制莎士比亚作品或参考词值，并贯通混排与全部客户端／服务端数据面。
- 2026-09-08 更正：当前单语总数为一百四十六种、默认／自选 LTR 多语候选为一百三十六种。新增 Svenska · Å Ä Ö；固定 `swedish_diacritics` 配置只定义 `bcp47: sv-SE`。结构审计只确认参考词数、4–6 字符长度范围及每词均含 `å/ä/ö`，不读取词值；Typebar 使用 58 个独立自写且满足同一约束的词和四档原创瑞典语文本，走 LTR 空格词界、`sv` 百科入口、`sv-SE` 朗读、可选简化输入和 Zipf 未知提示，并贯通混排与全部客户端／服务端数据面。
- 2026-09-08 更正：当前单语总数为一百四十七种、默认／自选 LTR 多语候选为一百三十七种。新增 Português · Acentos e cedilha；固定 `portuguese_acentos_e_cedilha` 配置只定义 `bcp47: pt-PT`。结构审计只确认参考词数、长度范围及每词均含葡萄牙语重音字母或 `ç`，不读取词值；Typebar 使用独立自写的专项词流与四档原创葡萄牙语文本，走 LTR 空格词界、`pt` 百科入口、`pt-PT` 朗读、可选简化输入和 Zipf 未知提示，并贯通混排与全部客户端／服务端数据面。
- 2026-09-08 更正：当前单语总数为一百四十八种、默认／自选 LTR 多语候选为一百三十八种。新增 Русский · Аббревиатуры；固定 `russian_abbreviations` 配置定义 `bcp47: ru-RU`、`noLazyMode: true` 与 `orderedByFrequency: false`。结构审计只确认 245 个参考 token 均无空格和数字、223 个全大写、240 个不超过 6 字符，不读取词值；Typebar 使用 64 个独立自写短缩略词和四档原创俄语文本，走 LTR 空格词界、`ru` 百科入口、`ru-RU` 朗读、禁用简化输入和 Zipf 不支持提示，并贯通混排与全部客户端／服务端数据面。

## 后续候选与准入条件

每个新候选都必须先确认 RTL、连写、词界、BCP-47、输入法和服务端数据面；不得仅因名称或书写习惯相似而复用既有路径。

`english_old` 当前仅能确认是 200 词、无附加元数据且与现行 `english` 仅少量重合的独立目录；固定源码没有说明它表示旧版默认词表还是历史英语。取得项目一手定义前保持候选状态，不以猜测赋予用户可见名称或内容。

`russian_contractions` 定义 `bcp47: ru-RU`、`noLazyMode: true` 与 `orderedByFrequency: false`；结构审计只确认 200 个短 token 中多数是小写西里尔形式，少量包含标点。固定源码没有解释这里的 “contractions” 是口语缩约、带标点结构还是其他专项语义，因此暂不创建会误导用户的练习模式，也不读取或复制参考词值。

任何候选只有在完成上述语义核对、原创内容、跨客户端与服务端测试及文档记录后，才会从“候选”变为“已覆盖”。

- 2026-09-08 更正：当前单语总数为一百五十种、默认／自选 LTR 多语候选为一百四十种。新增 Українська · Закінчення 与 Українська (Latynka) · Закінчення；两个固定配置均定义 `noLazyMode: true`，不定义 BCP-47 或词频排序。结构审计仅确认原生组为 118 个、1–4 字符的乌克兰西里尔 token，Latynka 组为 117 个、1–5 字符且字符集限于 `a-zïğš` 的 token，不读取词值。Typebar 以两套独立自写词流和各四档原创文本重建这些边界，禁用简化输入、使用 `en`／`en-US` 缺省路径、显示 Zipf 未知提示，并贯通混排与全部客户端／服务端数据面。
- 2026-09-08 更正：当前单语总数为一百五十一种、默认／自选 LTR 多语候选为一百四十一种。新增 বাংলা · অক্ষর；固定 `bangla_letters` 定义 `joiningScript: true`、`noLazyMode: true` 与 `bcp47: bn-BD`，结构审计仅确认其 62 个 token 的 56/3/2/1 标量长度分布和 Bengali Unicode 区块边界，不读取词值。Typebar 根据 [Unicode 17.0 Bengali 区块](https://www.unicode.org/charts/PDF/U0980.pdf) 独立编排字母、符号和组合序列及四档原创文本，使用 LTR 空格词界、`bn`／`bn-BD`、禁用简化输入和 Zipf 未知提示，并贯通混排与全部数据面。同时将原生连写保护从 3 项纠正为固定元数据要求的 26 项，覆盖已支持的 Arabic、Indic、RTL、Korean、Likanu、Tibetan 与 Yiddish 语言；不读取参考词值或复用实现。
- 2026-09-08 更正：当前单语总数为一百五十二种、默认／自选 LTR 多语候选为一百四十二种。新增 Git 专项；固定 `git` 配置仅定义 `noLazyMode: true`，结构审计只确认 52 个唯一 token、1–19 字符长度分布、全小写 ASCII、4 个含符号 token 及仅 `-`／`@` 的符号集合，不读取词值。Typebar 依据本机 Git 2.50.1 `git help -a` 的公开命令面和通用版本控制概念独立编排词流及四档原创文本，使用 LTR 空格词界、缺省 `en`／`en-US`、禁用简化输入和 Zipf 未知提示，并贯通混排与全部数据面。
