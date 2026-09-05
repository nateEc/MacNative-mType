# 官方语言覆盖审计

## 范围与判定

- 参考版本：Monkeytype `91bd24bb8513785c7364cbea29296ff7adafac41`。
- 盘点入口：`packages/schemas/src/languages.ts` 的 `LanguageSchema`，以及对应的 `frontend/static/languages/` 配置文件。该版本 schema 有 446 个语言 ID，目录也有 446 个 JSON 模块。
- 446 不是 446 种独立自然语言：其中包含同语言的词表规模（如 `_1k` / `_10k`）、书写或罗马化变体，以及代码练习标识。本审计以用户可见的语言、书写方式和输入排版语义为单位。
- Typebar 不复制参考项目的代码、JSON、词表、引语、字体、布局或主题资产。此处的“已覆盖”仅表示已用原创内容和原生功能重建可见意图，绝不表示数据一对一迁移或全面同质化。

## 已覆盖的原生语言面

Typebar 现有 68 个可单独练习并支持原创引语的语言／书写方式：English、Español、Deutsch、Afrikaans、Azərbaycanca、Беларуская、Lietuvių、Latviešu、Монгол、کوردی ناوەندی、العربية、עברית、فارسی、اردو、தமிழ்、हिन्दी、ગુજરાતી、বাংলা、ไทย、नेपाली、ಕನ್ನಡ、తెలుగు、മലയാളം、संस्कृतम्、සිංහල、ខ្មែរ、မြန်မာ、ລາວ、አማርኛ、Հայերեն、ქართული、Ελληνικά、Greeklish、Nederlands、Filipino、Català、Bahasa Indonesia、Bahasa Melayu、Dansk、Norsk Bokmål、Norsk Nynorsk、Svenska、Magyar、Čeština、Slovenčina、Slovenščina、Hrvatski、Српски、Srpski Latin、Български、Română、Suomi、Eesti、Íslenska、Français、Italiano、Português、简体中文、繁體中文、Русский、Українська、Ukrainian Latin、日本語・ひらがな、日本語・カタカナ、日本語・ローマ字、한국어、Türkçe、Polski。另有中英混合与可配置的多语混合练习。

| 语义类别 | 已重写的原生行为 | 边界 |
| --- | --- | --- |
| 从右到左 | Arabic、Hebrew、Persian、Urdu、Central Kurdish 使用 macOS 输入源与原生双向排版；Central Kurdish 同时使用系统原生连写字形；均不进入默认多语混排。 | 混合双向段落须有专门交互验收后才会启用。 |
| 连写、简化输入 | Tamil、Hindi、Gujarati、Bangla、Nepali、Kannada、Telugu、Malayalam、Sanskrit、Khmer、Burmese 与上述 RTL 语言均保留组合输入且按参考禁用简化输入；Sinhala、Lao 与 Amharic 也保留原生脚本输入，但参考未设 `noLazyMode`，因此不强制禁用。上述 LTR 语言均可参与多语混排。 | 不导入参考词表或简化规则。 |
| Thai 词界 | Thai 配置是 LTR、`noLazyMode: true`、`th-TH`，未标记 RTL 或 `joiningScript`；官方生成器除 `nospace` 修饰器外一律追加空格提交符。Typebar 因此使用原创 Thai 词元的空格提交路径与正常 macOS 输入。 | 不按自然书写习惯猜测无空格交互；该决定以参考实际生成器和客户端测试为准。 |
| 缺少 BCP-47 | Armenian、Georgian 与 Mongolian 仅设置 `noLazyMode: true`；Lithuanian 没有 BCP-47、RTL、连写或 `noLazyMode` 标记。四者官方百科实现均回退至 `en`，朗读回退至 `en-US`。Typebar 使用相同默认分支并固定测试。 | 不臆造语言、地区、朗读或百科代码。 |
| 无空格词界 | 简体／繁体中文、日语平假名与片假名走无空格的原生词界与计分路径。 | 仅在已验证脚本上启用，不能由语言名称推断。 |
| 罗马化／替代书写 | Greeklish、Ukrainian Latin、Japanese Romaji 使用原创 ASCII 离线内容，且不会被在线原文替换为另一书写方式。 | 不把参考项目的变体词表纳入应用。 |
| 代码 | 69 个代码选择以原创短片段覆盖缩进、输入、回放与结果路径。 | 标识可参考公开语言目录；所有片段、标签组合与 UI 均由 Typebar 自写。 |

每个单语均有：自创练习词流、四档原创引语、会话构造测试；能够安全获取在线百科短文的语言还使用对应语言入口和原生朗读 locale。服务端同时验证投稿白名单、撤回、成绩提交和按语言排行榜，不将客户端新语言视为孤立功能。

## 有意不按 ID 一一复刻的部分

| 官方目录形式 | Typebar 策略 | 原因 |
| --- | --- | --- |
| `_1k`、`_5k`、`_10k` 等词表规模 | 不作为独立语言选择；以原创小型词流和可重复生成策略练习。 | 导入同规模词表会复制参考数据，且规模不是新的输入语义。 |
| `*_romanized`、音译或脚本变体 | 仅在能提供清晰、稳定、原创的独立练习承诺时实现。 | 显示名称相近不代表同一内容、输入法或在线来源可安全共用。 |
| 官方语言 JSON 的 `words`、字体和标点数据 | 不导入。 | 保持纯重写与许可边界清晰。 |
| 尚未研究的语言 ID | 不先占位。 | 每个语言要先确认 RTL、连写、无空格、BCP-47、输入法和服务端数据面。 |

## 自动化守卫

- `testEverySingleLanguageHasAnOriginalExtendedQuoteThatBuildsACompleteSession` 直接枚举 `TypingLanguage.allCases`，保证任何新增的单语都有自有词流、超过 120 字的原创 extended 引语，并能构造完整 quote session。
- 多语测试检查默认候选集、各语言轮转与候选数量；Arabic、Hebrew、Persian、Urdu 与 Central Kurdish 等 RTL 语言明确被排除，Tamil、Hindi、Gujarati、Bangla、Thai、Nepali、Kannada、Telugu、Malayalam、Sanskrit、Sinhala、Khmer、Burmese、Lao、Amharic、Armenian、Georgian、Azerbaijani、Belarusian、Lithuanian、Latvian 与 Mongolian 明确被包含。
- 每次新增语言同时覆盖客户端内容路径、显示／排版、朗读或在线来源边界，以及服务端语言白名单、投稿、撤回、成绩和排行榜。

## 后续候选与准入条件

当前没有未经语义审核就进入实现队列的语言。每个新候选都必须先确认 RTL、连写、词界、BCP-47、输入法和服务端数据面；不得仅因名称或书写习惯相似而复用既有路径。

任何候选只有在完成上述语义核对、原创内容、跨客户端与服务端测试及文档记录后，才会从“候选”变为“已覆盖”。
