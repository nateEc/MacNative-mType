# 官方配置兼容性审计

## 范围与方法

- 参考源码：Monkeytype `91bd24bb8513785c7364cbea29296ff7adafac41`。
- 权威入口：`packages/schemas/src/configs.ts` 中的 `ConfigSchema`；它列出当前网页端所有可保存配置键。
- 本审计只记录用户可见设置的代码级映射。`已映射` 不代替真实设备验收；`部分` 和`未实现`不能在其他文档中表述为已完成。
- Typebar 的实现、文案、数据模型和测试均为原创；该表不复制参考实现的代码、资产、词表、布局定义或主题数据。

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
| `language` | `TypingLanguage`、`mixedLanguageComponents` | 部分；十四种原创单语（含繁体中文、俄语、乌克兰语、日语平假名、韩语、土耳其语与波兰语）、中英混合和自选多语组合，不复制官方语言目录。 |
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
| `customLayoutfluid` | `layoutFluidLayouts` | 已映射；官方上限 15，当前 17 个原创内置布局可任选至多 15 个进入原生序列。 |
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
| `lazyMode` | `TestModifier.lazyLatin` | 部分；语义为提示文本简化重音/连字，当前以显式练习修饰器而非全局开关呈现。 |
| `layout` | `KeyboardInputLayout` | 部分；系统输入源为默认，17 种原创物理布局和用户自写四行布局（可选等长 Shift 图例）的基础映射可显式模拟；官方全部命名布局尚未覆盖。 |
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

1. 官方 239 份命名 `keymapLayout` 资产与输入模拟尚未全部覆盖。当前策略优先使用 macOS 当前输入源（普通、Shift、Option、Shift+Option 四层标签，并通过 TIS 输入源切换通知刷新）、17 个原创内置模拟布局（含独立实现的 Russian JCUKEN），以及可由用户自写四行/Shift 图例定义的基础映射，避免复制资产；仍需继续扩展原创输入映射覆盖。
2. 官方语言、词表、主题、字体和声音的完整目录不应复制。后续以原创或明确授权内容扩大用户可选范围，并逐项标注差异。
3. 网页账户页图表、猴子外观和广告设置不适合作为原生逐像素复刻目标；对用户可见意图的原生替代仍需设备验收。

## 本轮新增验证

- Russian JCUKEN 自动化测试覆盖 `ё`、`й`、`ж`、`э`、`я`、`ь`、逗号与 ISO `< >` 的提示高亮、普通/Shift 物理 keycode、反查 keycode；独立设置快照覆盖键盘图、输入模拟与 Layout Fluid 持久化。映射为 Typebar 原生实现，不导入参考布局 JSON。
- 乌克兰语自动化测试覆盖原创词表中的 `ї`、`є`、`ґ`、四档原创引语、多语混排、弱项复练、`uk-UA` 朗读 locale 与 `uk` 百科入口；服务端测试覆盖成绩提交、语言筛选排行榜与引语投稿白名单，未读取或导入参考词表/内容。
- 完整客户端 `swift test` 通过 255 项、独立 Vapor 服务 `swift test` 通过 66 项；两次测试前 `pgrep -x Typebar` 均无输出，未启动图形应用。
- `SystemKeyboardGuide` 的注入式测试验证四行 ANSI 物理键位、Shift 图例、下一键匹配字符及缺失键位的安全回退。
- 设置快照测试覆盖键盘图来源的持久化、恢复与旧归档默认回退。
- 自定义键盘输入映射测试覆盖 Unicode 字母普通/Shift 映射、用户定义的符号 Shift 图例、旧归档默认、Option 的系统回退、归档恢复和删除选中图后的安全回退。
- Discord 头像隐私测试覆盖默认不公开、显式开启、资料卡与 WPM/XP 榜显示、关闭后立即隐藏与非法哈希拒绝；客户端同时拒绝非 ASCII 标识与异常 CDN URL。
- 原创公开徽章测试覆盖服务端成绩派生、未解锁拒绝、显式选择/清除、公开资料与 WPM/XP 榜显示、旧字段省略及删除服务端成绩后的即时隐藏。
- 公开资料连续练习测试覆盖服务端 UTC 日界下的当前/最长连续派生、活动隐私开关联动隐藏，以及客户端对新旧资料响应的解码。
- 公开资料练习统计测试覆盖服务端从已接受成绩起止时间聚合累计时长，以及按随完成提交的重开次数派生开始次数；重复提交同一成绩 ID 不会重复累加，客户端对新旧资料响应安全解码。未完成且未提交练习与本机历史不进入该值。
- 引语长度与队列测试覆盖多选长度通过预设和 Typebar 配置链接保存、旧单长度配置迁移，以及同一候选集每轮不重复且避免立即重复当前引语；队列仅存于当前进程，不引入参考内容或实现。
- 服务公告测试覆盖公开读取、部署审核密钥发布/删除、计划日期往返、空白公告拒绝、原生完整日期/日期/相对时间占位符替换，以及本机普通公告关闭、置顶公告保留和服务端移除后的本机确认清理；不复制参考文案、样式或实现。
- 完整客户端 `swift test` 已通过 255 项测试；测试前 `pgrep -x Typebar` 无输出，未启动图形应用。
- 独立 Vapor 服务的 `swift test` 已通过 66 项测试，其中覆盖 GitHub/Google/Discord OAuth 的 PKCE 授权 URL、一次性 state、原生回调、注册/关联、提供商匹配重新验证、安全移除、Discord 头像公开隐私、原创公开徽章、公开连续练习/开始次数隐私及服务公告；测试前 `pgrep -x Typebar` 无输出，未启动图形应用。
