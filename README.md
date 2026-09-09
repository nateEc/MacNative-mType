# Typebar

一个从零实现的 macOS 打字应用。目标是对 Monkeytype 做功能兼容的纯重写，但不使用其代码、后端、资产或广告。完整范围、实现边界和进度见 [REWRITE_SPEC.md](REWRITE_SPEC.md)。

远程功能的自建服务范围与 API 草案见 [SERVICE_SCOPE.md](SERVICE_SCOPE.md) 和 [SERVICE_CONTRACTS.md](SERVICE_CONTRACTS.md)。

## 运行

需要 Xcode 16 或更新版本：

```sh
swift run
```

生成可直接双击的本地应用包：

```sh
zsh Scripts/package-macos-app.sh
```

运行自建服务的最小健康检查（服务能力仍在建设中）：

```sh
cd server
swift run TypebarServer serve --hostname 127.0.0.1 --port 8080
```

服务能力可从 `http://127.0.0.1:8080/v1/capabilities` 查询；该入口会如实标示未实现模块。
若要暂时停止一切服务端写入而继续提供状态和只读查询，可在启动前设置 `TYPEBAR_MAINTENANCE_MODE=true`；客户端会提示用户本机离线练习不受影响。

### 发布服务公告

部署者设置 `TYPEBAR_MODERATION_TOKEN` 后，可在原生设置的“审核员工具”发布或删除公告，也可附加计划日期。所有客户端会在启动时公开读取公告：普通公告可仅在当前 Mac 关闭，置顶公告会保留到服务端删除。含计划日期的公告可在正文中使用 `{date}`、`{dateNoTime}` 和 `{dateDifference}`，由 macOS 以当前地区显示完整日期时间、日期或相对时间。公告不需要账户，不包含输入、提示、成绩、邮箱或令牌。

### 配置账户邮件

密码重置与邮箱验证由部署者显式配置的 HTTPS webhook 投递，不绑定特定邮件服务。设置 `TYPEBAR_PASSWORD_RESET_WEBHOOK_URL` 后，密码重置会继续向该地址 `POST` JSON 的 `email`、`token` 和 ISO 8601 `expiresAt`；邮箱验证在相同字段外额外带 `kind: "emailVerification"`，以兼容既有的重置收件端。可选的 `TYPEBAR_PASSWORD_RESET_WEBHOOK_TOKEN` 会以 Bearer 令牌放入请求头。webhook 必须为带 `kind` 的事件生成验证邮件，且切勿记录或转发一次性码。未配置 webhook 时，能力端点会标为计划中，重置或验证请求会返回明确的 `503`，不会伪称邮件已发出。

### 配置第三方登录

自建服务可按标准授权码流程接入 GitHub、Google 或 Discord。每个提供商都必须同时设置客户端 ID、客户端密钥和精确的回调地址：`TYPEBAR_GITHUB_OAUTH_CLIENT_ID`、`TYPEBAR_GITHUB_OAUTH_CLIENT_SECRET`、`TYPEBAR_GITHUB_OAUTH_REDIRECT_URL`，或相应的 `TYPEBAR_GOOGLE_OAUTH_*` / `TYPEBAR_DISCORD_OAUTH_*` 三项。回调地址必须是 HTTPS（本机 `localhost`、`127.0.0.1` 或 `::1` 可使用 HTTP），不能带查询参数、片段或用户信息。服务端会使用 PKCE、一次性且仅保存哈希的短期 state，并只接受已验证的提供商邮箱；Discord 仅请求 `identify email`。提供商访问令牌不会保存或写入日志。尚未配置的提供商会在能力端点显示为“计划中”。原生账户设置会通过 macOS 系统授权窗口调用这套流程，并以 `typebar://oauth/callback` 接收回调。Discord 头像仅在用户已关联 Discord 且主动开启公开资料开关时，以受格式校验的公开 ID 与头像哈希构成 CDN 请求；未开启时不会从公开资料接口返回 Discord 关联。

## 已验证的基础能力

- 原生 macOS 窗口及菜单栏入口；可选择开启 `⌃⇧Space` 全局唤起（需要用户主动授予辅助功能权限）
- 可重复打包为本地 `Typebar.app`
- 可从原生界面配置并开始计时、字数、引语、自定义文本、禅模式；计时支持 5–3600 秒、字数支持 1–1000 词的自定义数值
- 开始后可明确放弃本次测试；放弃与难度失败均不会写入完成成绩
- 原创 English（美式或英式拼写）、Español、Deutsch、Afrikaans、العربية、עברית、فارسی、اردو、தமிழ்、हिन्दी、ગુજરાતી、বাংলা、ไทย、नेपाली、ಕನ್ನಡ、తెలుగు、മലയാളം、संस्कृतम्、සිංහල、ខ្មែរ、Ελληνικά、Greeklish、Nederlands、Filipino、Català、Bahasa Indonesia、Bahasa Melayu、Dansk、Norsk bokmål、Norsk nynorsk、Svenska、Magyar、Čeština、Slovenčina、Slovenščina、Hrvatski、Српски、Srpski (Latin)、Български、Română、Suomi、Eesti、Íslenska、Français、Italiano、Português、简体中文、繁體中文、Русский、Українська、Українська (Latin)、日本語（ひらがな）、日本語（カタカナ）、日本語（ローマ字）、한국어、Türkçe、Polski 与 Git 离线词库及引语；Git 专项以本机公开命令界面和通用概念独立编排，不读取参考词值。Arabic、Hebrew、Persian 和 Urdu 用 macOS 输入源、RTL 提示与原生双向文本排版呈现，暂不进入双向多语混排。Tamil、Hindi、Gujarati、Bangla、Nepali、Kannada、Telugu、Malayalam、Sanskrit、Sinhala 和 Khmer 使用 macOS 组合输入与 LTR 原生文本排版，并可加入默认和自选多语混排；Thai 也可混排，但按参考实际生成器的空格提交语义练习，不将自然书写习惯误作无空格交互。Arabic 有默认开启、可关闭的快速输入，用于将原创词流中的短元音等组合符号归一为更易输入的提示；它不影响其他语言。乌克兰语 Latin、日语罗马字与 Greeklish 仅提供 Typebar 自创的 ASCII 离线内容；Srpski (Latin) 也只使用原创离线拉丁内容。四种书写形式都不会被随机远端原文替换；日语假名模式也不以随机百科文本替换提示；计时、字数和禅模式还可用中英混合词流，语言选择随测试配置、预设和成绩保存
- 新增原创 မြန်မာ 离线词库及引语，使用 macOS Burmese 输入源、组合输入和 LTR 文本排版，能加入默认和自选多语混排；知识短文与系统朗读分别使用参考定义的 `my` 与 `my-MM`，且不应用简化重音输入。
- 新增原创 ລາວ 离线词库及引语，使用 macOS Lao 输入源和 LTR 文本排版，能加入默认和自选多语混排；知识短文与系统朗读均精确使用参考定义的 `lo`，保留用户显式选择的简化输入。
- 新增原创 አማርኛ 离线词库及引语，使用 macOS Amharic 输入源和 LTR 文本排版，能加入默认和自选多语混排；知识短文与系统朗读分别精确使用参考定义的 `am` 与 `am-ET`，保留用户显式选择的简化输入。
- 新增原创 Հայերեն 离线词库及引语，使用 macOS Armenian 输入源和 LTR 文本排版，能加入默认和自选多语混排；参考未定义 BCP-47，故知识短文与系统朗读分别按其缺省规则使用 `en` 与 `en-US`，且不应用简化重音输入。
- 新增原创 ქართული 离线词库及引语，使用 macOS Georgian 输入源和 LTR 文本排版，能加入默认和自选多语混排；参考未定义 BCP-47，故知识短文与系统朗读分别按其缺省规则使用 `en` 与 `en-US`，且不应用简化重音输入。
- 新增原创 Azərbaycanca 离线词库及引语，使用 macOS Azerbaijani 输入源和 LTR 空格词界，可加入默认和自选多语混排；知识短文按官方 `az-AZ` 的首段使用 `az`，系统朗读严格使用 `az-AZ`，且官方未禁用简化输入。
- 新增原创 Беларуская 离线词库及引语，使用 macOS Belarusian 输入源和 LTR 空格词界，可加入默认和自选多语混排；知识短文按官方 `be-BY` 的首段使用 `be`，系统朗读严格使用 `be-BY`，并依照 `noLazyMode` 禁用简化输入。
- 新增原创 Lietuvių 离线词库及引语，使用 macOS Lithuanian 输入源和 LTR 空格词界，可加入默认和自选多语混排；参考未定义 BCP-47，故知识短文与系统朗读分别按其缺省规则使用 `en` 与 `en-US`，并保留简化输入选项。
- 新增原创 Latviešu 离线词库及引语，使用 macOS Latvian 输入源和 LTR 空格词界，可加入默认和自选多语混排；知识短文与系统朗读均严格使用官方 `lv`，且保留简化输入选项。
- 新增原创 Монгол离线词库及引语，使用 macOS Mongolian 输入源和 LTR 空格词界，可加入默认和自选多语混排；参考仅定义 `noLazyMode`、未定义 BCP-47，故知识短文与系统朗读分别按其缺省规则使用 `en` 与 `en-US`，并禁用简化输入选项。
- 新增原创 Gaeilge 离线词库及引语，使用 macOS Irish 输入源和 LTR 空格词界，可加入默认和自选多语混排；知识短文按官方 `ga-IE` 的首段使用 `ga`，系统朗读严格使用 `ga-IE`，且官方未禁用简化输入。
- 新增原创 Galego 离线词库及引语，使用 macOS Galician 输入源和 LTR 空格词界，可加入默认和自选多语混排；知识短文按官方 `gl-ES` 的首段使用 `gl`，系统朗读严格使用 `gl-ES`，并保留官方 `orderedByFrequency` 对应的 Zipf 高频词选项。
- 新增原创 मराठी 离线词库及引语，使用 macOS Marathi 输入源和 LTR 空格词界，可加入默认和自选多语混排；参考仅定义 `noLazyMode` 与 `orderedByFrequency`、未定义 BCP-47，故知识短文与系统朗读分别按其缺省规则使用 `en` 与 `en-US`，保留 Zipf 高频词并禁用简化输入选项。
- 新增原创 Shqip 离线词库及引语，使用 macOS Albanian 输入源和 LTR 空格词界，可加入默认和自选多语混排；参考只定义语言名称，故知识短文与系统朗读严格按缺省规则使用 `en` 与 `en-US`，并保留简化输入选项。
- 新增原创 Ichibemba 离线词库及引语，使用 macOS Bemba 输入源和 LTR 空格词界，可加入默认和自选多语混排；知识短文与系统朗读严格使用官方 `bem`，参考将 `orderedByFrequency` 标为 `false`，因此启用 Zipf 时会提示词表未按频率排序但不会关闭修饰器。
- 新增原创 Bosanski 离线词库及引语，使用 macOS Bosnian 输入源和 LTR 空格词界，可加入默认和自选多语混排；参考只定义语言名称与 `orderedByFrequency: true`、未定义 BCP-47，故知识短文与系统朗读严格按缺省规则使用 `en` 与 `en-US`，并保留 Zipf 高频词和简化输入选项。
- 新增原创 Esperanto、Esperanto · X-sistemo 与 Esperanto · H-sistemo 离线词库及引语，三者都是独立的 LTR 空格词界练习并可混排；参考标准书写与 H-sistemo 确认支持 Zipf，X-sistemo 未声明排序，故启用 Zipf 时仅显示可能不支持的提示。三者均未定义 BCP-47，因此知识短文与朗读分别严格回退至 `en` 与 `en-US`；标准书写保留简化输入，X/H 两种 ASCII 转写按 `noLazyMode` 禁用它。
- 新增原创 Latina 离线词库及引语，使用 LTR 空格词界，可加入默认和自选多语混排；参考只定义语言名称，故知识短文与系统朗读严格按缺省规则使用 `en` 与 `en-US`，保留简化输入；参考未声明词频排序，因此启用 Zipf 时会提示可能不支持但不会关闭修饰器。
- 新增原创 Friulian 离线词库及引语，使用 LTR 空格词界，可加入默认和自选多语混排；知识短文与系统朗读均严格使用参考定义的 `fur`，并保留简化输入；参考未声明词频排序，因此启用 Zipf 时会提示可能不支持但不会关闭修饰器。
- 新增原创 Malagasy 离线词库及引语，使用 LTR 空格词界，可加入默认和自选多语混排；参考只定义 `noLazyMode`、未定义 BCP-47，故知识短文与系统朗读分别按缺省规则使用 `en` 与 `en-US`，并禁用简化输入；参考未声明词频排序，因此启用 Zipf 时会提示可能不支持但不会关闭修饰器。
- 新增原创 Cymraeg（Welsh）离线词库及引语，使用 LTR 空格词界，可加入默认和自选多语混排；参考只定义语言名称，故知识短文与系统朗读严格按缺省规则使用 `en` 与 `en-US`，保留简化输入；参考未声明词频排序，因此启用 Zipf 时会提示可能不支持但不会关闭修饰器。
- 新增原创 Hausa 离线词库及引语，使用 LTR 空格词界，可加入默认和自选多语混排；知识短文与系统朗读均严格使用参考定义的 `ha`，并保留简化输入；参考未声明词频排序，因此启用 Zipf 时会提示可能不支持但不会关闭修饰器。
- 新增原创 Татарча（Tatar）离线词库及引语，使用 LTR 空格词界与西里尔输入，可加入默认和自选多语混排；知识短文与系统朗读均严格使用参考定义的 `tt`，并保留简化输入和确认可用的 Zipf 高频词。
- 新增原创 Oʻzbekcha（Uzbek）离线词库及引语，使用参考明确的 LTR 空格词界，可加入默认和自选多语混排；知识短文按 BCP 首段使用 `uz`，系统朗读精确使用 `uz-UZ`，并保留简化输入；参考未声明词频排序，因此启用 Zipf 时会提示可能不支持但不会关闭修饰器。
- 新增 Swiss German 原生练习：严格复用 Typebar 自有 German 词流及四档引语，并把可见 `ß` 全部替换为 `ss`；这是对固定源码专用分支的等价实现，不导入官方词表或引语。知识短文按 BCP 首段使用 `de`，系统朗读精确使用 `de-CH`，保留简化输入；参考未声明词频排序，因此 Zipf 保留并提示可能不支持。Swiss German 可进入多语混排与成绩排行榜，但按源码不提供社区引语投稿或社区来源。
- 新增原创 کوردی ناوەندی 离线词库及引语，使用 macOS Central Kurdish 输入源、RTL 原生排版及连写字形；知识短文与系统朗读均严格使用 `ckb`。它不进入默认或自选多语混排，且参考未定义 `noLazyMode`，故保留简化输入选项。
- 代码练习提供与官方当前目录对应的 70 个语言/方言选择，每项使用 Typebar 原创离线片段，并支持换行、自动缩进、可选反缩进和回放；最新增加 Dockerfile，不导入官方代码语料
- 当前语言目录：240 个可单独练习的语言或书写方式、70 个代码选择和 2 个混合入口。
- 固定参考版本的 446 个官方语言配置 ID 已有可重新生成的机器总账：310 个对应 Typebar 独立选择，136 个数字词表规模变体由同语言选择表达，当前没有未映射 ID；项目不会把规模变体误报成独立一一等价，也不会为补齐规模而复制官方语料
- Thai 1k／5k／10k／20k／50k／60k 以六个独立 ID 提供原创按需索引词流，保持各档规模、Unicode 长度、组合标记及标点／空格／数字结构，不复制参考词值
- Norsk bokmål 1k／5k／10k／150k／600k 以五个独立 ID 提供原创按需索引词流，保持各档规模、长度、大小写、标点、数字与非 ASCII 结构；600k 普通出题只生成请求项
- Norsk nynorsk 1k／5k／10k／100k／400k 以五个独立 ID 提供原创按需索引词流，保持各档规模、长度、大小写、标点、空格、数字与非 ASCII 结构；400k 普通出题只生成请求项
- 简体中文 1k／5k／10k／50k 以四个独立 ID 提供原创按需 CJK 索引词流，保持固定规模、长度和 Unicode 聚合结构；无空格普通出题只生成请求项
- 繁體中文 1k／5k／10k／50k 以四个独立 ID 提供原创按需繁体 CJK 索引词流，保持实际规模、长度、Unicode 数字、标点交叠与词频语义；无空格普通出题只解析本次提示
- नेपाली 1k 以独立 ID 提供 1,000 项原创按需天城文索引词流，保持组合标记、字符与标量长度结构，并使用 macOS 组合输入、`ne` 百科和 `ne-NP` 朗读
- Azərbaycanca 1k 以独立 ID 提供 989 项原创按需索引词流，保持 2–7 字符与 668 个非 ASCII 条目的聚合结构，并接入 `az` 百科及 `az-AZ` 朗读
- Malagasy 1k 与 Bahasa Melayu 1k 分别以 975／1,000 项原创按需索引词流提供独立入口，保持各自长度、大写、标点、非 ASCII 与内部空格聚合结构
- 韩语 1k／5k 以两个独立 ID 提供原创、按需生成的纯 Hangul 词流，保持固定规模、长度、空格词界、连写、朗读和数据面语义，不复制参考词值
- Creature Index 1k · Typebar 使用规则生成的 1,025 个原创虚构生物条目，保留多词、符号、数字、长度和非频率排序结构，不包含宝可梦名称、设定或资产
- Arena Strategy Terms · Typebar 使用 442 个原创竞技场术语重建题名大小写、多词 section、符号、数字与默认标点行为，不包含英雄、装备、技能名称或游戏资产
- Русский · Краткие формы提供 200 条基础与 880 条扩展原创短形式；两个规模均独立可选，保持包含关系、符号、数字、大小写与长度边界，不导入参考词值
- தமிழ் · பழைய தொகுப்பு以独立入口提供 460 条原创 joining-script 练习项，保持固定标量长度和单条多词结构，不导入旧词表值
- English 1k／5k／10k／25k／450k 作为五个独立入口使用原创确定性索引词流；普通出题只生成实际请求的词，词表筛选与弱项分析才扫描所选规模，同时保持固定实际规模、长度、大小写、符号和词频排序能力，不导入参考词值
- Español 1k／10k／650k 作为三个独立入口使用原创确定性索引词流，保持 998／9,990／646,579 的实际规模及长度、大小写、符号、多词和非 ASCII 结构；普通出题不物化整表，也不导入参考词值
- Français 1k／2k／10k／600k 作为四个独立入口使用原创确定性索引词流，保持 1,394／2,041／10,251／633,941 的实际规模及长度、大小写、标点、多词和非 ASCII 结构；四档不会重复加入默认混排，600k 普通出题只读取请求项
- العربية 10k 与 العربية المصرية 1k 使用两套原创阿拉伯字母索引词流，保持 9,281／1,141 个唯一项及固定的前导、内部和双空格结构；两项独立接入 RTL、连写、`ar-SA`／`ar-EG`、四档引语和服务端数据面
- Deutsch 1k／10k／250k 作为三个独立入口使用原创确定性索引词流，保持 988／9,994／239,243 的实际规模及长度、名词大写、标点、多词和非 ASCII 结构；250k 普通出题不会物化整表
- Română 1k／5k／10k／25k／50k／100k／200k 七档均为独立入口，原创确定性索引词流保持对应实际规模及长度、标点和非 ASCII 结构；200k 普通出题同样只读取请求项
- Polski 2k／5k／10k／20k／40k／200k 六档均为独立入口，原创确定性索引词流保持对应实际规模及长度、大小写、标点和非 ASCII 结构；200k 普通出题只读取请求项
- Беларуская 1k／5k／10k／25k／50k／100k 六档均为独立入口，原创确定性西里尔索引词流保持对应实际规模及长度、大小写、标点和非 ASCII 结构；100k 普通出题只读取请求项
- Русский 1k／5k／10k／25k／50k／375k 六档均为独立入口，原创确定性西里尔索引词流保持对应实际规模及长度、大小写、标点、多词和非 ASCII 结构；375k 普通出题只读取请求项
- Português 1k／3k／5k／320k／550k 五档均为独立入口，原创确定性索引词流保持对应实际规模及长度、大小写、标点、多词、数字、符号和非 ASCII 结构；两档大型词流普通出题只读取请求项
- 引语模式可按短、中、长、超长筛选，收藏原创离线引语；完成页会保留本轮引语身份，提供本机收藏/评分，或对已审核社区引语进行账户评价和私有举报；可选择仅在输入中重开时重复当前引语，随机选择则始终避开当前内容；收藏与策略会随本机归档保存
- 计时、字数和禅模式可按需加入数字与标点，且选项随预设和备份保存
- 自定义文本可保存、选择复用和删除；“筛选词表…”可只从 Typebar 自创离线词表按词长、字符或 ICU 正则生成内容；“生成文本…”可从用户提供的片段随机组合练习词。两者均可替换或追加后立即开始，且不下载第三方词表
- normal / expert / master 难度，以及严格空格、停止错误、删除错误、盲打、自由回退与三档信心模式；信心模式可阻止回退修复上一错误词，最大档禁用退格
- 自有趣味修饰器支持“无空格”与“下划线分隔”两种互斥的词间边界练习；“全大写”“逐词首字母大写”“交替大小写”彼此互斥，并可组合“ROT13”“逐词反写”“字符双写”和“遇错清除当前词”。后者仅对空格分词文本生效，误键会清除当前未提交词，并保持回放可复现。另有“记忆模式”：开始前显示提示，首个有效输入后隐藏提示但继续按原文计分
- “简化重音输入”修饰器可将当前测试提示中的重音、变音、常见连字与 ß 转成普通拉丁输入；不会改写离线内容或用户原文
- 可选择当前词、当前词加 1/2/3 个预读词四档可见范围；它只影响提示显示，不改变输入、成绩或回放
- 原生 AppKit 键盘输入（文字提交、退格、Esc / ⌘R 重开与 IME 组合输入协议）
- 快速重开键可设为关闭、Esc、Tab 或 Enter；⌘R 始终可用
- 可选原创键盘提示：一百五十三种内置布局（含 Whix2、Haruka、Kuntum、Kuntem、Kuntem-JQ、Scythe、Inqwerted、Rain、Night、Night STIC、Nila、Noctum、Cascade、Vylet、Romak、Octa8、Nerps、Gallium、Gallium Angle、Gallium v2、STNDC、UCIEA、Whorf、Whorf 6、Whorfmax、Pine v4、Three、Asset、Dwarf、Flaw、Focal、Zenith、Dhorf、Gust、Recurva、Pine、Real、Sertain、CTGAP、Graphite、Capewell Dvorak、Colman、Heart、Klauser、Oneproduct、Middlemak-NH、Foalmak、Quartz、Arensito、ARTS、Boo/Mangle、APT/Angle、Middlemak、Semimak/JQ/JQC、Canary/Matrix、TypeHack、ISRT/Angle、Engram/Engrammer、MTGAP/Full、Ina、Soul、Niro、Hands Down/Alt/Neu/Neu Inverted、French Bépo AFNOR、ANSI Alpha、Swedish Colemak/Dvorak、French Dvorak、French AZERTY AFNOR、French Bépo、Programmer Dvorak/Prime、German Dvorak/Improved、Spanish Dvorak、MTGAP ASRT、Halmak、QGMLWB、QGMLWY、QWPR、Colemak Angle/Wide/DHv、Norman、Programmer Workman、Turkish E、Japanese Hiragana、相互独立的 Colemak-DH ANSI/ISO/Matrix/Wide ANSI/Wide ISO 与 Colemak-DHk ANSI/ISO、Typebar 自写的希腊字母、匈牙利语 QWERTZ、保加利亚语与塞尔维亚语西里尔图，以及 Tamil99、Brazilian ABNT2、Dvorak Left/Right-Handed、Mongolian Cyrillic、Armenian HM QWERTY、Hindi InScript、Thai Kedmanee/Pattachote、Polish (Programmers)、Urdu Phonetic 和 Arabic macOS 的 Option 字符层、Swedish QWERTY、Macedonian、Pashto、Estonian、Persian Standard/Farsi、Arabic 101/102 与 Hebrew）、跟随 macOS 当前输入源的动态物理键位图，以及最多二十种用户自写的 Unicode 四行键盘图；七种原生几何样式、关闭/静态/按键反馈/下一键模式、精简/数字行/完整按键集、0.5–3.5 倍大小及小写/大写/空白/动态图例均可持久化。视觉键盘图不改变输入，输入默认始终交给 macOS 当前输入法，只有明确开启内置布局模拟时才接管物理键。Layout Fluid 会按阶段同时切换内置键盘图与模拟布局（每轮最多选择十五种）；多字符快捷键会完整输出，但下一键提示优先选择能精确输出目标字符的单字符键；动态图例随 Shift、Caps Lock 以及支持的 Option/Shift+Option 层更新，其余死键与 Option 输入仍由 macOS 处理
- 当前内置键盘图为二十五种：新增 Danish QWERTY，独立模拟 `å`、`æ`、`ø`、`§` 与其普通/Shift 实体键位；该项取代上条的“二十四种”计数。死键和 Option/AltGr 层继续保持 macOS 原生输入路径，不导入 Monkeytype 布局资产
- 当前内置键盘图为二十六种：新增 Norwegian QWERTY，公开现有 Nordic 键位对应的 `å`、`ø`、`æ` 实体映射，保留 Nordic 作为已有设置的兼容选项；该项取代上条的“二十五种”计数。死键和 Option/AltGr 层仍保持 macOS 原生输入路径，不导入 Monkeytype 布局资产
- 当前内置键盘图为二十七种：新增 ANSI Colemak-DH，独立模拟与标准 Colemak 不同的 `B/G`、`D/V`、`H/M` 位置；该项取代上条的“二十六种”计数。ISO、wide 与其他 Colemak-DH 变体仍由系统输入或自定义布局处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为二十八种：新增 Turkish F，独立模拟 `ğ/ı/i/İ/ü/ö/ç/ş`、数字行与 ISO `< >` 的 F 键位；该项取代上条的“二十七种”计数。AltGr 与组合式死键仍由 macOS 处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为二十九种：新增 Bulgarian Phonetic Traditional，独立模拟 `ч/я/ъ/ш/щ/ю/ь/ѝ`、数字行与 ISO 物理键上的 `ю`；该项取代上条的“二十八种”计数。AltGr 仍由 macOS 处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为三十种：新增 Belarusian，独立模拟 `Ў/ў`、`І/і`、`Ё/ё`、数字符号与 ISO `< >`；该项取代上条的“二十九种”计数。Option/AltGr 仍由 macOS 处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为三十一种：新增 Macedonian，独立模拟 `Љ/Њ/Ѕ/Ѓ/Ж/Ќ/Џ`、ISO `ѐ/Ѐ` 和数字引号层；该项取代上条的“三十种”计数。Option/AltGr 仍由 macOS 处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为三十二种：新增 Pashto，独立模拟波斯-阿拉伯字母、东阿拉伯数字、组合音标、ZWJ/ZWNJ 与区域标点的普通/Shift 键位；不输出字符的 ISO 键、AltGr、方向控制与其他系统层继续由 macOS 处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为三十三种：新增 Estonian，独立模拟 `õ/ä/ö/ü/š/ž`、ISO `< >` 与区域标点的普通/Shift 键位；AltGr 与组合式死键继续由 macOS 处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为三十四种：新增 Persian (Standard)，独立模拟波斯字母、东阿拉伯数字、`﷼`、组合音标、ZWJ/ZWNJ、ISO 与区域标点的普通/Shift 键位；AltGr 和方向控制继续由 macOS 处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为三十五种：新增 Arabic (101)，独立模拟阿拉伯字母、组合音标、`لإ/لأ/لا/لآ` 完整文本输出、ISO 与区域标点的普通/Shift 键位；AltGr、ZWJ/ZWNJ 与方向控制继续由 macOS 处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为三十六种：新增 Hebrew，独立模拟希伯来字母、Shift 拉丁/标点层与 ISO 键的普通/Shift 实体键位；AltGr、Caps Lock 元音点和方向控制继续由 macOS 处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为三十七种：新增 Arabic (102)，独立模拟 `ذ`、ISO tatweel、组合音标、连字与区域标点的实际普通/Shift 键位；AltGr、ZWJ/ZWNJ 与方向控制继续由 macOS 处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为三十八种：新增 Arabic (macOS)，依据 macOS TIS/`UCKeyTranslate` 的公开输入行为独立实现阿拉伯数字、组合音标、区域标点及 Option/Shift+Option 层；无输出的 Shift 键会被正确消费，不会落回另一输入源。不读取或导入 Monkeytype 布局 JSON
- 当前内置键盘图为三十九种：新增 Persian (Farsi)，依据 Microsoft Persian KLID `00000429` 的公开键位表独立实现 Farsi Yeh、Keheh、Gaf、ISO `پ` 与 `ریال` 多字符快捷键；Control 层继续由 macOS 处理，不读取或导入 Monkeytype 布局 JSON
- 当前内置键盘图为四十种：新增 Urdu Phonetic (CRULP)，依据 CLE/CRULP v1.1 规范与 SIL Keyman 的开放映射交叉实现 Urdu 字母、数字、组合音标、宗教符号及 Option/Right Alt 层；明确无输出的 Shift+F 会被正确消费，不导入第三方代码、字体或键盘资产
- 当前内置键盘图为四十一种：新增 Thai Kedmanee，依据 Microsoft KLID `0000041E` 键位表与 NECTEC 的 TIS 820 资料独立实现泰文字母、元音、声调、数字与标点的普通/Shift 实体键位，并以 macOS `com.apple.keylayout.Thai` 系统映射交叉核对；Option 与组合输入继续由 macOS 处理，不读取或导入 Monkeytype 布局 JSON
- 当前内置键盘图为四十二种：新增 Thai Pattachote，依据 Microsoft KLID `0001041E` 的公开布局标识及键盘驱动表独立实现普通/Shift 键位，并以 NECTEC 布局资料和 macOS `com.apple.keylayout.Thai-PattaChote` 系统映射交叉核对主体字母层；采用完整标准数字行，Option 与组合输入继续由 macOS 处理，不读取或导入 Monkeytype 布局 JSON
- 当前内置键盘图为四十三种：新增 Hindi – InScript (macOS)，依据 macOS `com.apple.keylayout.Devanagari` 的系统翻译行为独立实现数字、元音、辅音、组合符与 `ज्ञ/त्र/क्ष/श्र` 多码点输出；无输出普通/Shift 键会被明确消费，Option 与复杂组合输入继续由 macOS 处理。BIS 与 Microsoft 资料用于交叉确认 InScript 标准家族，不读取或导入 Monkeytype 布局 JSON
- 当前内置键盘图为四十四种：新增 Armenian – HM QWERTY，依据 macOS `com.apple.keylayout.Armenian-HMQWERTY` 的系统翻译行为独立实现 Base、Shift、Option 与 Shift+Option 四层，包括仅在 Option 层提供的 Armenian 字母和标点；不读取或导入 Monkeytype 布局 JSON
- 当前内置键盘图为四十五种：新增 Mongolian Cyrillic，依据 macOS `com.apple.keylayout.Mongolian-Cyrillic` 的系统翻译行为独立实现 Base、Shift、Option 与 Shift+Option 四层；主体字母层与 Unicode CLDR 的 Mongolian Cyrillic 标准布局交叉核对，不读取或导入 Monkeytype 布局 JSON
- 当前内置键盘图为四十七种：新增 Dvorak – Left-Handed 与 Dvorak – Right-Handed，依据 macOS `com.apple.keylayout.Dvorak-Left` / `Dvorak-Right` 独立实现四个修饰层，并与 Apple 对左右手布局的定义及 Unicode CLDR 标识交叉核对；不读取或导入 Monkeytype 布局 JSON
- 当前内置键盘图为四十八种：新增 Brazilian – ABNT2，依据 macOS `com.apple.keylayout.Brazilian-ABNT2` 独立实现四个修饰层，并显式支持 ISO 键 keyCode 10 与右 Shift 附近的 ABNT2 专用键 keyCode 94；Unicode CLDR 用于交叉核对 103 键 ABNT2 几何和主体层，不读取或导入 Monkeytype 布局 JSON
- 当前内置键盘图为四十九种：新增 Tamil99 (macOS)，依据 macOS `com.apple.keylayout.Tamil99` 独立实现四个修饰层，完整保留 Tamil 组合符、`ஸ்ரீ` 多码点输出和明确空输出的 Shift/Option 层；Microsoft Tamil 99 标识与 Unicode CLDR Tamil 键盘资料用于交叉核对，不读取或导入 Monkeytype 布局 JSON
- 当前内置键盘图为五十种：新增 Colemak-DH ISO，依据 Colemak-DH 官方公开说明与 CC0 macOS 基础层独立实现 ISO Angle Mod 的额外 `Z` 键、左侧 `X C D V`、中央反引号及右侧 `K H , . /`；该时点的 Matrix 与 wide 等其他变体由 macOS 输入源或自定义布局处理，下一条已补齐 Matrix，不读取或导入 Monkeytype 布局 JSON、代码或资产
- 当前内置键盘图为五十一种：新增 Colemak-DH Matrix，依据 Colemak-DH 官方 CC0 macOS 基础层独立实现正交底行 `Z X C D V K H , . /`，与 ANSI 的中央 `Z` 重定位及 ISO 的额外实体键保持独立；wide 等其他变体继续由 macOS 输入源或自定义布局处理，不读取或导入 Monkeytype 布局 JSON、代码或资产
- 当前内置键盘图为五十三种：新增 Colemak-DHk ANSI 与 ISO，依据 ColemakMods 官方 CC0 macOS 键位定义独立实现 `K` 留在主行、`M H` 移至底行的 DHk 语义；ANSI 底行为 `X C D V Z M H , . /`，ISO 额外保留左侧 `Z` 实体键及中央反引号。两者具有独立提示、模拟、反查与持久化标识，不读取或导入 Monkeytype 布局 JSON、代码或资产
- 当前内置键盘图为五十五种：新增 Colemak-DH Wide ANSI 与 ISO，依据 ColemakMods 官方 CC0 定义独立实现向右移动的数字、右手字母和标点列；ANSI 底行为 `X C D V Z / K H , .`，ISO 额外保留左侧 `Z`，底行为 `Z X C D V \\ # K H , .`。两者具有独立提示、模拟、反查与持久化标识，不读取或导入 Monkeytype 布局 JSON、代码或资产
- 当前内置键盘图为五十六种：新增 Japanese Hiragana，使用 Typebar 自有 Swift 数据重新表达固定参考可观察的 47 个 ANSI 键位行为，覆盖普通假名、小假名、日文括号与标点 Shift 输出；不复制、打包或运行参考 JSON、代码、字体或其他资产
- 当前内置键盘图为五十九种：新增 ANSI Colemak Angle、ANSI Colemak Wide 与 ANSI Norman。三项均以 Typebar 自有 Swift 映射完整覆盖 47 个 ANSI Base/Shift 位置，并分别保留 Angle 底行、Wide 数字/标点位移和 Norman 字母排列；不复制、打包或运行参考布局资产
- 当前内置键盘图为六十二种：新增 ANSI Colemak-DHv、Programmer Workman 与 Turkish E。前两项完整覆盖 47 个 ANSI Base/Shift 位置，Turkish E 完整覆盖含额外 ISO 键的 48 个位置；三项均接入提示、模拟、反查、设置归档和 Layout Fluid，不复制、打包或运行参考布局资产
- 当前内置键盘图为六十七种：新增 MTGAP ASRT、Halmak、QGMLWB、QGMLWY 与 QWPR。五项均完整覆盖 47 个 ANSI Base/Shift 位置，其中 Halmak 保留非标准数字及标点 Shift 层；全部接入提示、模拟、反查、设置归档和 Layout Fluid，不复制、打包或运行参考布局资产
- 当前内置键盘图为七十二种：新增 Programmer Dvorak、Programmer Dvorak Prime、German Dvorak、German Dvorak Improved 与 Spanish Dvorak。两项 ANSI 和三项 ISO 布局分别完整覆盖 47/48 个 Base/Shift 位置，并保留各自符号及区域字符层；全部接入提示、模拟、反查、设置归档和 Layout Fluid，不复制、打包或运行参考布局资产
- 上一阶段内置键盘图增至七十七种：新增 Swedish Colemak、Swedish Dvorak、French Dvorak、French AZERTY (AFNOR) 与 French Bépo。五项均完整覆盖 48 个 ISO 位置；AFNOR/Bépo 另覆盖 Option/Shift+Option，AFNOR 包含 NBSP/窄 NBSP 空格层；全部接入提示、模拟、反查、设置归档和 Layout Fluid，不复制、打包或运行参考布局资产
- 上一阶段内置键盘图增至七十九种：新增 French Bépo (AFNOR) 与 ANSI Alpha。Bépo AFNOR 完整覆盖 48 个 ISO 四层位置与普通空格，Alpha 完整覆盖 47 个 ANSI Base/Shift 位置；两项均接入提示、模拟、反查、设置归档和 Layout Fluid，不复制、打包或运行参考布局资产
- 上一阶段内置键盘图增至八十三种：新增 ANSI Hands Down、Alt、Neu 与 Neu Inverted。四项均完整覆盖 47 个 ANSI Base/Shift 位置；Neu 两项保留非标准符号层。`handsdown_promethium` 因独立 `R` 拇指键继续回退，不伪装为标准 ANSI；不复制、打包或运行参考布局资产
- 上一阶段内置键盘图增至八十八种：新增 MTGAP、MTGAP Full、Ina、Soul 与 Niro。五项均完整覆盖 47 个 ANSI Base/Shift 位置，前三项保留非标准符号层，MTGAP Full 在精简提示中仍显示数字行；不复制、打包或运行参考布局资产
- 上一阶段内置键盘图增至九十三种：新增 TypeHack、ISRT、ISRT Angle、Engram 与 Engrammer。五项均完整覆盖 47 个 ANSI Base/Shift 位置，TypeHack 与 Engram 保留非标准符号层，Engram 两项在精简提示中仍显示数字行；不复制、打包或运行参考布局资产
- 上一阶段内置键盘图增至九十八种：新增 Semimak、Semimak JQ、Semimak JQC、Canary 与 Canary Matrix。五项均完整覆盖 47 个 ANSI Base/Shift 位置，并保留三种 Semimak 的 J/Q/C 差异和两种 Canary 的独立排列；不复制、打包或运行参考布局资产
- 上一阶段内置键盘图增至一百零三种：新增 Boo、Boo Mangle、APT、APT Angle 与 Middlemak。五项均完整覆盖 47 个 ANSI Base/Shift 位置；Boo 两项保留非标准符号层，Boo Mangle 在精简提示中仍显示数字行，APT Angle 保留独立底行；不复制、打包或运行参考布局资产
- 上一阶段内置键盘图增至一百五十三种：新增 Whix2、Haruka、Kuntum、Kuntem 与 Kuntem-JQ。Haruka 与三个 Kuntum/Kuntem 变体完整覆盖 47 个 ANSI Base/Shift 位置；Whix2 精确保留 40 个赋值位置和 7 个空位，不复制、打包或运行参考布局资产
- 上一阶段内置键盘图增至一百五十八种：新增 BEAKL Zi、Snorkle、MALTRON、PRSTEN 与 RSTHD。五项完整覆盖 47 个 ANSI Base/Shift 位置；其中四项原生显示双拇指行，普通 Mac 的唯一物理 Space 按固定参考可观察语义映射到第五行首项，第二项仅作为布局提示，不复制、打包或运行参考布局资产
- 上一阶段内置键盘图增至一百六十三种：新增 Hands Down Promethium、Statica 3×5、Vestnik、Diktor 与 Diktor Voronov Mod。Promethium 原生显示 `R + 空格` 拇指行并由物理 Space 输入 `r`；五项的 AltGr 未重定义键保持布局 Base/Shift，Statica/Vestnik 另保留特殊 Cyrillic 层，Diktor 两项保留重排数字符号层，不复制、打包或运行参考布局资产
- 当前内置键盘图为一百九十三种：新增 Sturdy Ortho、HiYou、Xenia、Xenia Alt 与 Burmese。保留 HiYou ISO 单层符号键、Burmese 独立组合符和数字行、其余三项 ANSI 排列、完整 Base/Shift 与 AltGr 基础层回退，不复制、打包或运行参考布局资产
- 当前内置键盘图为一百九十八种：新增 Gallium v2 Matrix、Gallium NL、Maya、Gallaya Angle ANSI 与 Gallaya Angle ISO。Gallium v2 Matrix 按固定参考的实际声明保留 ANSI 物理类型，Gallaya ISO 保留额外 ISO 键和地区 Shift 符号；五项均覆盖完整 Base/Shift、AltGr 基础层回退、提示、模拟、反查、归档和 Layout Fluid，不复制、打包或运行参考布局资产
- 当前内置键盘图为二百零三种：新增 Gallaya Matrix、Minimak 4-key、Minimak 8-key、Minimak 12-key 与 Graphite Angle。五项均按固定参考的实际声明保留 ANSI 物理类型，完整覆盖 Base/Shift 与 AltGr 基础层回退；三个 Minimak 阶段保持各自渐进键位和英式 `£` Shift 符号，并全部接入提示、模拟、反查、归档和 Layout Fluid，不复制、打包或运行参考布局资产
- 当前内置键盘图为二百零四种：新增 Optimot。它完整覆盖 48 个 ISO 物理位置和 Base/Shift/Option/Shift+Option 四层；字母区的 `⌫` 位走原生向后删除动作，不会作为文本进入提示、计分或回放。布局同时接入提示、模拟、反查、归档和 Layout Fluid，不复制、打包或运行参考布局资产
- 当前内置键盘图为二百零九种：新增 Graphite Angle VC、Graphite Angle KP、Graphite Matrix、UGJRMV 与 ORNATE。五项均覆盖完整 ANSI Base/Shift 和 AltGr 基础层回退，保留三个 Graphite 底行差异、UGJRMV 特殊字母/符号及 ORNATE 非对称 Shift 配对，并接入提示、模拟、反查、归档和 Layout Fluid，不复制、打包或运行参考布局资产
- 原生设置窗口：难度、输入规则与字体大小会保存到本机
- 可选 macOS 系统键击音、错误提示音及 0–100% 音量；默认关闭，不携带音频资产
- 原生设置窗口支持中英文关键词搜索，可过滤测试、显示、主题、账户和恢复默认设置分组
- 字数模式可启用“最后一词快速结束”：最后一词达到目标长度即可收尾；遇错停下或遇错删除时自动不生效
- 计时、字数及两种自定义循环模式均可选择无限练习；计时器/词数正向累计，Typebar 自有提示按需循环，Bail Out 或双击 Shift+Enter 会显示但不保存结果
- 三套原创内置主题（纸白、午夜、林地）可切换并随本机设置与备份保存
- 可选择跟随 macOS 深浅色，在原创纸白和午夜主题间自动切换
- 可选择每次新测试时在原创纸白、午夜与林地主题间随机切换；跟随系统时自动暂停随机切换
- 练习字体可切换 macOS 系统等宽、圆角、衬线或默认设计，并随本机设置和归档保存
- 可创建、应用和删除本地自定义主题（背景、面板、强调色及明暗偏好），并随 Typebar 归档迁移
- 原生账户设置可连接自建服务进行注册、密码或 GitHub/Google/Discord 登录、会话恢复、密码重置、邮箱验证、资料刷新、公开资料编辑、第三方方式关联/移除、为第三方账户添加或移除密码方式、撤销所有设备会话和退出；访问令牌按规范化服务地址分别保存在 macOS 钥匙串，切换服务器不会跨域发送旧令牌。公开资料可包含简介、键盘说明、GitHub、X / Twitter 用户名与 HTTPS 网站，并可关闭活动日历和连续练习摘要；两者默认按 UTC 分日，账户可在 −11 至 +12 小时内按半小时档固定一次公开日界，该选择独立于本机统计日界且不修改成绩时间。邮箱、令牌、本机日界和本机练习内容不会公开。移除第三方方式、添加密码、撤销会话与删除账户均须先完成一次性重新验证：密码账户验证当前密码，纯第三方账户在 macOS 系统授权窗口确认已关联身份；凭据只保存哈希、五分钟后失效且使用即作废。重置码仅能使用一次、20 分钟后过期，完成重置会注销该账户所有设备；验证邮件在注册或改邮箱后自动发送，也可手动重发，验证码只能使用一次并在 24 小时后过期
- 已关联 Discord 的用户可主动在公开资料、WPM 榜和 XP 榜展示 Discord 头像；服务端默认不返回关联，也会拒绝异常 ID 或头像哈希，原生客户端加载失败时回退系统人物图标
- 原生账户设置会显示由服务端已接受成绩解锁的十枚 Typebar 原创公开徽章，覆盖完成次数、准确率、速度、累计时长、语言与模式广度；用户可选择一枚在公开资料、WPM 榜和 XP 榜显示，未选择、未解锁或删除相应服务端成绩时不会返回徽章。首次达到每枚徽章条件时，服务端会向当前账户投递一次不含提示或回放的私有奖励通知；重复上传同一成绩或后续同类成绩不会重复投递。参考中依赖开发者、捐赠或社区身份人工授予的徽章不会被伪造
- 原生账户设置可创建、重命名、禁用和删除最多五个 Typebar 开发者密钥；明文仅在创建时可见，服务端只保存哈希。密钥只允许自动化客户端通过 `X-Typebar-Access-Key` 读取或上传自己的成绩元数据，不能读取资料、同步数据或修改账户；设置页可查看近期服务端成绩，并以常规登录会话为每条成绩编辑最多五个原创标签
- 原生账户设置可在重新确认身份后重置服务端公开个人最佳而保留成绩、XP、徽章和排行榜；服务端以重置后的新接收成绩建立新 PB，本机历史与本机 PB 不受影响。也可另行永久清除当前账户的全部服务端成绩和相应 XP；本机练习历史、设置及其他账户数据不会受影响
- 原生账户设置可在不可撤销确认与重新验证后完整重置当前账户数据：服务端先幂等清除成绩、XP、PB、资料、密钥、同步档案和通知，再清理当前 Mac 的历史、预设、保存文本、设置、背景与字体；身份、会话、好友、屏蔽、投稿和统计日边界保留。服务端成功但本机失败时会明确提示安全重试；建议操作前先导出
- 自建服务可发布带可选计划日期的公开纯文本公告；正文支持当前地区的完整日期时间、日期和相对时间占位符；普通公告仅在当前 Mac 本机关闭，置顶公告持续显示至部署者删除，发布和删除只接受部署审核密钥
- 可保存、应用和删除完整测试预设
- 可用工具栏“命令”或 ⇧⌘K 搜索并执行重开、模式切换、历史、预设、数据、同步、好友和设置
- macOS“关于 Typebar”窗口从 bundle 显示版本/构建，解释本机数据与联网边界、核心指标和兼容性研究方法，并提供源码与问题反馈入口；不复制 Monkeytype 品牌页、广告或贡献者数据
- 应用菜单、关于窗口或命令面板可打开原生版本历史；仅在用户查看时分页读取 Typebar 自己的正式 GitHub Releases，以纯文本显示说明并过滤草稿、预发布和外部链接
- 可通过工具栏“分享”复制或导入自有 `typebar://test` 测试配置链接；链接不包含账户、成绩或本机设置
- 可从原生界面导入／导出版本化本地归档（设置、结果、预设、自定义文本；当前为 v3，导入去重合并并兼容 v1/v2 归档）
- 登录自建服务后，可从原生同步面板上传本机归档或拉取并合并远端归档；并发版本冲突会保留本机设置，把双方不同的预设、文本、主题和自定义键盘布局安全另存后重试上传
- 自建服务可保存基本校验后的成绩，并提供按模式/语言筛选的全局与好友 WPM（全部时间、今天、昨天、本周）及 ISO 本周/上周 XP 排行榜；常规登录会话可在同步页查看自己在当前榜单范围的实际名次，即使该条目不在前 25/100 名
- 可从榜单打开自建服务的公开资料卡（展示名、加入时间、完成/开始次数、服务端累计练习时长、最佳 WPM、可选简介/键盘说明/社交链接、活动日历和当前/最长连续练习摘要；不含邮箱）
- 自建账户可随时从全局及好友 WPM/XP 榜隐藏；已保存成绩、XP、同步和本机历史仍保留
- 已登录后可按公开展示名搜索用户，在原生好友面板查看好友请求、接受请求、取消请求或解除好友；也可从榜单资料卡发送请求
- 主工具栏显示服务端当前账户的未读通知数；原生通知中心显示好友、私信与徽章奖励及当前数量/100 条上限，可刷新、逐条标为已读、逐条删除或经确认清空，操作后徽标即时更新；超限时仅淘汰该账户最旧通知，删除通知不会删除好友关系、私信或已解锁徽章
- 可启用最多五个本机活动标签；之后开始的完成成绩会自动写入这些标签，完整预设、归档、当前统计、当前设置历史筛选与活动标签个人最佳节奏引导均会保留相同语义；完成页会基于本机可比历史显示每个标签的首次、新增或既有 PB，并可开关已有标签 PB 的图表水平线
- 实时 WPM、Raw WPM、单词 Burst、准确率和错误统计
- 练习区可选显示近 10 次同设置本机平均，或符合资格的同设置本机个人最佳；两者均不要求登录
- 测试完成后的原生结果页：WPM、准确率、Raw、错误、用时，以及按最终输入映射统计的“匹配/错位/额外/跳过”字符；同一分类会保存到历史详情，本机新 PB 皇冠反馈、重开和历史入口保持可用
- 原生输入桥会在本机统计已闭合物理按键的按住时长、连续按下间隔与多键重叠时长；完成页和历史详情显示相应摘要，未释放的末键、未闭合重叠和自动重复不会伪造样本
- 结果页区分“重复本轮”（相同配置与提示）和“再来一次”（按当前选择生成新内容）；重测不会继承输入、计时或回放
- 完成页显示今天累计的本机练习时长和完成次数；未保存的成绩在本次运行中也会计入，避免遗漏练习模式
- 结果页可从本机回放复制实际输入；缺少回放时明确拒绝生成，绝不从提示或统计推断文本
- 结果页可复制文字、复制 Typebar 原创结果卡 PNG，或通过 macOS 保存面板导出 PNG；卡片使用当前主题并显示准确度刻度
- 练习历史可将当前筛选后的本机成绩导出为 CSV；文件使用 UTC 名称和标准 CSV 转义，包含成绩、配置、标签、完成前重开次数、本机派生指标与四项字符分类，但不含提示、实际输入或回放
- 练习历史摘要随当前筛选即时统计开始次数、完成数与完成率、每次完成重开比、有效键入时长、估算词数，以及 WPM、Raw、准确率、稳定度的最高、平均和最近 10 次；速度类数值遵循当前显示单位
- 近 28 日练习图随历史筛选和本机统计日界更新，可切换完成次数、有效分钟、每日平均/最高速度、平均准确率、平均稳定度和每次完成重开比；空白日期保留，但不会伪造平均值
- 本机历史可按日期、速度、Raw、准确率或稳定度升降排序，每次渐进显示 10 条；CSV 导出全部匹配项并遵循当前排序
- 速度分布直方图随 WPM/CPM/WPS/CPS/WPH 单位换算并采用对应档宽，从零保留空档；异常大导入值安全汇入有界溢出档
- 速度与准确率历史趋势可拖动选择最近成绩，两图同步标记并显示完整本机摘要，可继续打开成绩详情或清除选择
- 历史统计与图表上方显示紧凑的当前筛选摘要，默认只显示“全部成绩”，复杂条件可横向滚动并由 VoiceOver 逐项读取
- 近 28 日活动的练习分钟指标显示按真实练习日期拟合的原生虚线趋势，不把空白日误计为零分钟
- 历史列表行直接显示模式参数、四元字符统计和结果标签，长摘要保持单行并可悬停查看全文
- 账户设置可分页导出当前账户的全部服务端成绩 CSV，而不是只导出近期列表；快照变化会中止并提示重试，文件不含提示、输入回放、邮箱、令牌、本机历史或其他账户数据
- 结果页会在至少五个词有有效词速时，生成本机最慢四分位目标词的有限加权练习；无法计时的词不参与
- 结果页可从本机输入回放重建最多 120 秒的 WPM、Raw、Burst 与错误轨迹；三条可选轨迹及普通/活动标签 PB 基线均可独立开关并保存显示偏好
- 以空格分词的完成结果可一键用本次实际输错的目标词重开练习，不会把未完成的后续词误判为错词
- 错词练习可选择仅练去重错词，或按每次实际尝试保留“前词 + 错词”上下文；两者都只来自本轮本机输入
- 以空格分词的完成结果会显示本次实际尝试词的目标/输入对照与正误状态
- 可选按本轮实际输入速度为结果单词历史显示 Typebar 原创五分位 Burst 热力图；没有可测间隔的词保持中性
- SwiftData 本地成绩存储；容器打不开时保留原文件并显示可定位、可复制诊断的恢复页，不静默创建空库
- 原生历史列表，显示、标记、添加标签并可删除本地成绩
- 本地历史汇总、WPM 趋势图、近 28 日完成/练习分钟柱状图、近 12 周活动热力图与个人最佳标记；可按同类计时/字数设置查看本机个人最佳表。可首次设定并锁定本机统计日分界（−11 至 +12 小时，每 30 分钟），连续天数和两类活动图同步采用该分界
- 新增原创 العربية المصرية 离线词流及四档引语，使用 macOS Arabic 输入源、RTL 提示和原生连写字形，暂不进入双向多语混排；固定参考配置的 `bcp47: ar-EG` 映射为 `ar` 知识短文与 `ar-EG` 系统朗读。参考未设置 `noLazyMode`，因此保留用户显式选择的简化输入，但不继承 Typebar 针对标准 Arabic 的自动快捷开关；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 العربية المغربية 离线词流及四档引语，使用 macOS Arabic 输入源、RTL 提示和原生连写字形，暂不进入双向多语混排；固定参考配置的 `bcp47: ar-MA` 映射为 `ar` 知识短文与 `ar-MA` 系统朗读。参考未设置 `noLazyMode`，因此保留用户显式选择的简化输入，但不继承标准 Arabic 的自动快捷开关；其 `orderedByFrequency: false` 会在启用 Zipf 时显示不支持提示而保留修饰器，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 پښتو 离线词流及四档引语，使用 macOS Pashto 输入源、RTL 提示和原生连写字形，暂不进入双向多语混排；固定参考配置的 `bcp47: ps` 映射为 `ps` 知识短文与 `ps` 系统朗读。参考设置 `noLazyMode: true`，因此非自定义练习禁用简化输入，而自定义文本仍保留该能力；未声明词频排序，启用 Zipf 时显示可能不支持提示而保留修饰器，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 سنڌي 离线词流及四档引语，使用 macOS Sindhi 输入源、RTL 提示和原生连写字形，暂不进入双向多语混排；固定参考配置的 `bcp47: sd` 映射为 `sd` 知识短文与 `sd` 系统朗读。参考未设置 `noLazyMode`，因此保留用户显式选择的简化输入，但不继承标准 Arabic 的自动快捷开关；其 `orderedByFrequency: false` 会在启用 Zipf 时显示不支持提示而保留修饰器，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Occitan 离线词流及四档引语，使用 macOS Occitan 输入源和 LTR 空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: oc-FR` 按首段映射为 `oc` 知识短文，并精确映射为 `oc-FR` 系统朗读。参考未设置 `noLazyMode` 或词频排序，因此保留用户显式选择的简化输入；启用 Zipf 时显示可能不支持提示而保留修饰器，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Oromo 离线词流及四档引语，使用 macOS Oromo 输入源和 LTR 空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: om` 映射为 `om` 知识短文与 `om` 系统朗读。参考未设置 `noLazyMode`，因此保留用户显式选择的简化输入；其 `orderedByFrequency: true` 保留 Zipf 高频词，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Македонски离线词流及四档引语，使用 macOS Macedonian 输入源和 LTR 空格词界，可加入默认和自选多语混排；固定参考配置没有 BCP-47，因此知识短文和系统朗读严格回退为 `en` 与 `en-US`。参考设置 `noLazyMode: true`，普通练习禁用简化输入而自定义文本保留例外；词频排序未定义，Zipf 显示可能不支持提示而保留修饰器，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Қазақша 离线词流及四档引语，使用 macOS Kazakh 输入源和 LTR 空格词界，可加入默认和自选多语混排；固定参考配置没有 BCP-47，因此知识短文和系统朗读严格回退为 `en` 与 `en-US`。参考设置 `noLazyMode: true`，普通练习禁用简化输入而自定义文本保留例外；词频排序未定义，Zipf 显示可能不支持提示而保留修饰器，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Tiếng Việt 离线词流及四档引语，使用 macOS Vietnamese 输入源和 LTR 空格词界，可加入默认和自选多语混排；固定参考配置没有 BCP-47，因此知识短文和系统朗读严格回退为 `en` 与 `en-US`。参考未设置 `noLazyMode`，因此保留用户显式选择的简化输入；词频排序未定义，Zipf 显示可能不支持提示而保留修饰器，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Jyutping 离线词流及四档引语，保留 ASCII 与声调数字的空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: zh-Hant` 按首段映射为 `zh` 知识短文，并精确映射为 `zh-Hant` 系统朗读。参考未设置 `noLazyMode`，因此保留用户显式选择的简化输入；词频排序未定义，Zipf 显示可能不支持提示而保留修饰器，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Pinyin 离线词流及四档引语，保留 ASCII 转写的空格词界，可加入默认和自选多语混排；固定参考配置未提供 BCP-47，因此知识短文和系统朗读严格回退为 `en` 与 `en-US`。参考未设置 `noLazyMode`，因此保留用户显式选择的简化输入；词频排序未定义，Zipf 显示可能不支持提示而保留修饰器，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Western Armenian 离线词流及四档引语，使用独立的西部亚美尼亚语正字法和 LTR 空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: hyw` 同时映射为 `hyw` 知识短文与系统朗读。参考未设置 `noLazyMode` 或词频排序，因此保留用户显式选择的简化输入，并在 Zipf 启用时显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Bashkir 离线词流及四档引语，使用 macOS 原生 LTR 西里尔排版和空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: ba` 映射为 `ba` 知识短文与系统朗读。参考未设置 `noLazyMode`，因此保留用户显式选择的简化输入；其 `orderedByFrequency: true` 保留 Zipf 高频词，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Euskera 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: eu` 映射为 `eu` 知识短文与系统朗读。参考未设置 `noLazyMode` 或词频排序，因此保留用户显式选择的简化输入，并在 Zipf 启用时显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Frisian 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: fy-FY` 按首段映射为 `fy` 知识短文，并精确映射为 `fy-FY` 系统朗读。参考未设置 `noLazyMode` 或词频排序，因此保留用户显式选择的简化输入，并在 Zipf 启用时显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 isiZulu 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考配置未提供 BCP-47，因此知识短文和系统朗读严格回退为 `en` 与 `en-US`。参考未设置 `noLazyMode` 或词频排序，因此保留用户显式选择的简化输入，并在 Zipf 启用时显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 ʻŌlelo Hawaiʻi 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考基础与 1k 配置的 `bcp47: haw` 映射为 `haw` 知识短文与系统朗读。参考未设置 `noLazyMode`，其 `orderedByFrequency: true` 保留 Zipf 高频词；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Taqbaylit 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: kab` 映射为 `kab` 知识短文与系统朗读。参考未设置 `noLazyMode`，其 `orderedByFrequency: false` 会在启用 Zipf 时显示不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Maltese 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: mt` 映射为 `mt` 知识短文与系统朗读。参考未设置 `noLazyMode` 或频率排序，启用 Zipf 时会显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 toki pona 基础、ku suli 与 ku lili 三个独立离线选择及四档引语。ku suli 在 Typebar 自有基础集合上增加 15 个独立整理的核心词，ku lili 使用与 ku suli 互斥的 20 个扩展词；三者均使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排。固定参考配置未提供 BCP-47，知识短文与系统朗读按 `en`／`en-US` 缺省路径处理；`noLazyMode: true` 会在普通练习禁用简化输入但保留自定义文本例外，Zipf 显示可能不支持提示。三者均接入预设、归档、社区投稿、成绩和排行榜，不导入官方 ku 词表。
- 新增原创 isiXhosa 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；主参考配置的 `bcp47: xh` 映射为 `xh` 知识短文与系统朗读。参考未设置 `noLazyMode` 或频率排序，启用 Zipf 时会显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Tibetan 离线词流及四档引语，使用 macOS 原生 LTR 连写字形与空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: bo-TI` 映射为 `bo` 知识短文与 `bo-TI` 系统朗读。其 `joiningScript: true` 使用原生塑形、较紧行距并避免圆点逐字替换；`noLazyMode: true` 会在普通练习禁用简化输入但保留自定义文本例外，Zipf 显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Kyrgyz 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: ky-KY` 映射为 `ky` 知识短文与 `ky-KY` 系统朗读。参考未设置 `noLazyMode` 或频率排序，启用 Zipf 时会显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Yiddish 离线词流及四档引语，使用 macOS 原生 RTL/连写排版和空格词界；固定参考配置的 `bcp47: yi` 映射为 `yi` 知识短文与系统朗读。其 `joiningScript: true` 使用原生塑形、较紧行距并避免圆点逐字替换；参考未设置 `noLazyMode` 或频率排序，保留显式简化输入与 Zipf 未知提示。它不加入尚未完成双向交互验收的多语混排，但已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Udmurt 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考配置未提供 BCP-47，知识短文与系统朗读按 `en`／`en-US` 缺省路径处理。参考未设置 `noLazyMode` 或频率排序，启用 Zipf 时会显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Yoruba 离线词流及四档引语，使用 macOS 原生 LTR 排版、空格词界与声调字符，可加入默认和自选多语混排；固定参考配置未提供 BCP-47，知识短文与系统朗读按 `en`／`en-US` 缺省路径处理。参考未设置 `noLazyMode` 或频率排序，启用 Zipf 时会显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Swahili 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考配置未提供 BCP-47，知识短文与系统朗读按 `en`／`en-US` 缺省路径处理。其 `noLazyMode: true` 会在普通练习禁用简化输入，但保留自定义文本例外；Zipf 显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Kinyarwanda 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: rw-RW` 映射为 `rw` 知识短文与 `rw-RW` 系统朗读。其 `noLazyMode: true` 会在普通练习禁用简化输入，但保留自定义文本例外；`orderedByFrequency: true` 启用 Zipf 高频词；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Shona 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考配置未提供 BCP-47，知识短文与系统朗读按 `en`／`en-US` 缺省路径处理。参考未设置 `noLazyMode` 或频率排序，保留简化输入，启用 Zipf 时会显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Belarusian Łacinka 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定配置的 `noLazyMode: false` 保留简化输入，未提供 BCP-47 或词频排序，知识短文与朗读按 `en`／`en-US` 缺省路径处理，Zipf 显示可能不支持提示；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Qırımtatarca 与 Къырымтатарджа 离线词流及各自四档引语，作为两个独立书写选择使用 macOS 原生 LTR 排版和空格词界，均可加入默认和自选多语混排。固定参考的十个相关词表档位均定义 `noLazyMode: true` 与 `bcp47: crh-CRH`，故普通练习禁用简化输入而自定义文本保留例外；知识短文使用 `crh`，系统朗读精确使用 `crh-CRH`，Zipf 显示可能不支持提示。两者均已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 tlhIngan Hol 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排。固定参考基础与 1k 配置均定义 `bcp47: tlh`，未定义 RTL、连写、`noLazyMode` 或词频排序；大小写和词内 `'` 保留为输入语义而非装饰标点。知识短文与系统朗读均使用 `tlh`，保留简化输入，Zipf 显示可能不支持提示；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Quenya 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排。固定参考配置未定义 BCP-47、RTL、连写、`noLazyMode` 或词频排序，知识短文与系统朗读严格按 `en`／`en-US` 缺省路径处理；保留显式简化输入，Zipf 显示可能不支持提示；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Viossa 与 Viossa · Njutro 离线词流及各自四档引语，作为独立的 LTR 空格分词练习加入默认和自选多语混排。两项均未提供 BCP-47，知识短文与系统朗读严格按 `en`／`en-US` 缺省路径处理，且 `orderedByFrequency: false` 会显示 Zipf 不支持提示；Njutro 额外按 `noLazyMode: true` 在普通练习禁用简化输入、自定义文本保留例外。两个词流都是 Typebar 明示的原创练习 idiolect，不导入参考词表或引语，均已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Te reo Māori 离线词流及四档引语，保留长元音 macron 并作为 LTR 空格分词练习加入默认和自选多语混排。固定参考仅提供 `maori_1k`，未定义 BCP-47、RTL、连写、`noLazyMode` 或词频排序，故知识短文与系统朗读严格按 `en`／`en-US` 缺省路径处理，保留简化输入并显示 Zipf 可能不支持提示；它已接入预设、归档、社区投稿、成绩和排行榜，且不导入参考词表或引语。
- 新增原创 Lojban · gismu 与 Lojban · cmavo 离线词流及各自四档引语，作为独立的 LTR 空格分词练习加入默认和自选多语混排。前者只练习五字母词根，后者独立保留 `.` 与 `'` 的语言内输入语义。两个固定参考配置均有 `noLazyMode: true`，故普通练习禁用简化输入而自定义文本保留例外；均未定义 BCP-47、RTL、连写或词频排序，知识短文与系统朗读严格按 `en`／`en-US` 缺省路径处理，Zipf 显示可能不支持提示。两个词流不导入参考词表或引语，均已接入预设、归档、社区投稿、成绩和排行榜。
- 新增 Unicode Ol Chiki 的 `ᱥᱟᱱᱛᱟᱲᱤ`（Santali）离线词流及四档 Typebar 自有练习文本，作为 LTR 空格分词选择加入默认和自选多语混排。固定参考只定义 `bcp47: sat-IN`，因此知识短文使用 `sat`、系统朗读使用 `sat-IN`，保留显式简化输入并在 Zipf 启用时显示未知支持提示；它已接入预设、归档、社区投稿、撤回、成绩和排行榜，且不导入参考词表或引语。
- 新增 Bulgarian Latin、Nepali Romanized、Persian Romanized、Sanskrit Roman 与 Urdu Roman 五种独立的 LTR 空格分词练习；每种都有 Typebar 自写词流和四档文本，不导入参考内容，也不宣称运行时可逆转写。它们按固定元数据分别处理简化输入、Zipf、百科和系统朗读，并全部进入默认／自选多语混排、预设、归档、社区投稿、撤回、成绩和排行榜。
- 新增 Hinglish、Tanglish 与 Urdish 三种独立的拉丁字母代码混合练习；每项均使用 Typebar 自写词流和四档文本，不导入参考或网络语料，也不把自然拼写变体伪装成统一标准。固定配置均未提供 BCP-47、`noLazyMode` 或词频排序，因此三者使用 LTR 空格词界、`en`／`en-US` 在线与朗读回退、可选简化输入和 Zipf 未知提示，并接入多语混排、预设、归档、社区投稿、撤回、成绩和排行榜。
- 新增 Ἑλληνιστικὴ Κοινή、Pig Latin 与 Lorem Ipsum · Typebar。Koine Greek 使用 Typebar 自写的多调希腊语词流和四档文本，并按 `el`／`el-GR` 处理知识短文与朗读；Pig Latin 只确定性转换 Typebar 自有英语内容；Lorem Ipsum 只使用 Typebar 自写伪拉丁内容。三者均使用 LTR 空格词界并接入多语混排与完整服务数据面，后两项按固定 `noLazyMode` 配置禁用普通练习简化输入。
- 当前内置键盘图为二百四十四种：新增独立的 Hungarian (ISO)、JCUKEN (ANSI) 与 Bulgarian (BDS)，保留它们各自的 ISO/ANSI 物理行、符号层与数字行显示策略。固定官方布局矩阵已达到 239 项精确原生、0 项相关替代、0 项回退；这不代表整个重写范围已经完成，也不复制、打包或运行参考布局资产
- 387 个引擎、内容、存储、偏好设置、预设、统计、归档、CSV 导出、账户响应及官方布局矩阵单元测试
- 74 个自建服务自动化测试，覆盖账号、完整账户数据重置、密码重置与邮箱验证、一次性重新验证与会话撤销、OAuth 授权码/PKCE/一次性状态、第三方与密码身份关联保护、Discord 头像公开隐私、十枚服务端公开徽章的边界、选择、撤销与幂等奖励通知、公开资料 UTC 连续练习/活动隐私/开始次数与搜索、公开个人最佳重置纪元、通知容量与隔离、开发者密钥与私有远端成绩及标签管理、排行榜隐身、好友关系、同步、成绩、WPM/XP 排行榜、审核引语/资料举报、社区评分、服务公告、请求限速与维护模式

## 后续范围（尚未完成）

- 更多原创语言与物理键盘映射
- 真实 macOS 设备与第三方账户验收
