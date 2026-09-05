# 官方语言覆盖审计

## 范围与判定

- 参考版本：Monkeytype `91bd24bb8513785c7364cbea29296ff7adafac41`。
- 盘点入口：`packages/schemas/src/languages.ts` 的 `LanguageSchema`，以及对应的 `frontend/static/languages/` 配置文件。该版本 schema 有 446 个语言 ID，目录也有 446 个 JSON 模块。
- 446 不是 446 种独立自然语言：其中包含同语言的词表规模（如 `_1k` / `_10k`）、书写或罗马化变体，以及代码练习标识。本审计以用户可见的语言、书写方式和输入排版语义为单位。
- Typebar 不复制参考项目的代码、JSON、词表、引语、字体、布局或主题资产。此处的“已覆盖”仅表示已用原创内容和原生功能重建可见意图，绝不表示数据一对一迁移或全面同质化。

## 已覆盖的原生语言面

Typebar 现有 111 个可单独练习并支持 Typebar 自有引语的语言／书写方式：English、Español、Deutsch、Swiss German、Afrikaans、Shqip、Ichibemba、Bosanski、Esperanto、Esperanto · X-sistemo、Esperanto · H-sistemo、Latina、Friulian、Malagasy、Cymraeg、Hausa、Татарча、Oʻzbekcha、Occitan、Oromo、Македонски、Қазақша、Tiếng Việt、Jyutping、Pinyin、Башҡортса、Euskara、Frysk、isiZulu、ʻŌlelo Hawaiʻi、Taqbaylit、Malti、toki pona、isiXhosa、བོད་སྐད་、Кыргызча、Удмурт кыл、Yorùbá、ייִדיש、Azərbaycanca、Беларуская、Lietuvių、Latviešu、Монгол、Gaeilge、Galego、मराठी、کوردی ناوەندی、العربية、العربية المصرية、العربية المغربية、پښتو、سنڌي、עברית、فارسی、اردو、தமிழ்、हिन्दी、ગુજરાતી、বাংলা、ไทย、नेपाली、ಕನ್ನಡ、తెలుగు、മലയാളം、संस्कृतम्、සිංහල、ខ្មែរ、မြန်မာ、ລາວ、አማርኛ、Հայերեն、Հայերէն (Արեւմտեան)、ქართული、Ελληνικά、Greeklish、Nederlands、Filipino、Català、Bahasa Indonesia、Bahasa Melayu、Dansk、Norsk Bokmål、Norsk Nynorsk、Svenska、Magyar、Čeština、Slovenčina、Slovenščina、Hrvatski、Српски、Srpski Latin、Български、Română、Suomi、Eesti、Íslenska、Français、Italiano、Português、简体中文、繁體中文、Русский、Українська、Ukrainian Latin、日本語・ひらがな、日本語・カタカナ、日本語・ローマ字、한국어、Türkçe、Polski。另有中英混合与可配置的多语混合练习。

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
| 代码 | 69 个代码选择以原创短片段覆盖缩进、输入、回放与结果路径。 | 标识可参考公开语言目录；所有片段、标签组合与 UI 均由 Typebar 自写。 |

每个单语均有：Typebar 自有练习词流、四档引语、会话构造测试；能够安全获取在线百科短文的语言还使用对应语言入口和原生朗读 locale。服务端同时验证投稿白名单、撤回、成绩提交和按语言排行榜，不将客户端新语言视为孤立功能；Swiss German 的例外路径明确拒绝投稿但接受成绩与排行榜筛选。

## 有意不按 ID 一一复刻的部分

| 官方目录形式 | Typebar 策略 | 原因 |
| --- | --- | --- |
| `_1k`、`_5k`、`_10k` 等词表规模 | 不作为独立语言选择；以原创小型词流和可重复生成策略练习。 | 导入同规模词表会复制参考数据，且规模不是新的输入语义。 |
| `*_romanized`、音译或脚本变体 | 仅在能提供清晰、稳定、原创的独立练习承诺时实现。 | 显示名称相近不代表同一内容、输入法或在线来源可安全共用。 |
| 官方语言 JSON 的 `words`、字体和标点数据 | 不导入。 | 保持纯重写与许可边界清晰。 |
| 尚未研究的语言 ID | 不先占位。 | 每个语言要先确认 RTL、连写、无空格、BCP-47、输入法和服务端数据面。 |

## 自动化守卫

- `testEverySingleLanguageHasAnOriginalExtendedQuoteThatBuildsACompleteSession` 直接枚举 `TypingLanguage.allCases`，保证任何新增的单语都有自有词流、超过 120 字的原创 extended 引语，并能构造完整 quote session。
- 多语测试检查默认候选集、各语言轮转与候选数量；Arabic、Hebrew、Persian、Urdu、Yiddish 与 Central Kurdish 等 RTL 语言明确被排除，Swiss German、Albanian、Bemba、Bosnian、Esperanto、Esperanto X、Esperanto H、Latin、Friulian、Malagasy、Welsh、Hausa、Tatar、Uzbek、Occitan、Oromo、Macedonian、Kazakh、Vietnamese、Jyutping、Pinyin、Bashkir、Euskera、Frisian、Zulu、Hawaiian、Kabyle、Maltese、toki pona、Xhosa、Tibetan、Kyrgyz、Udmurt、Yoruba、Tamil、Hindi、Gujarati、Bangla、Thai、Nepali、Kannada、Telugu、Malayalam、Sanskrit、Sinhala、Khmer、Burmese、Lao、Amharic、Armenian、Western Armenian、Georgian、Azerbaijani、Belarusian、Lithuanian、Latvian、Mongolian、Irish、Galician 与 Marathi 明确被包含。
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

## 后续候选与准入条件

当前没有未经语义审核就进入实现队列的语言。每个新候选都必须先确认 RTL、连写、词界、BCP-47、输入法和服务端数据面；不得仅因名称或书写习惯相似而复用既有路径。

任何候选只有在完成上述语义核对、原创内容、跨客户端与服务端测试及文档记录后，才会从“候选”变为“已覆盖”。
