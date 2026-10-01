# 官方输入路径审计

2026-10-02 最终门禁（隐藏词界进度）：最终客户端 1408 项（0 跳过、0 失败，十万词约 34.39 秒，2,800 词跨块约 20.69 秒）、服务端 131 项、固定参考／原创性、651 场景清单和未开窗应用包通过。优化只复用既有书写簇缓存及二分进度；不将程序化耗时等同于人类输入、系统候选栏或 GUI 持续内存验收，goal active。

2026-10-02 隐藏词界长文补证：2,800 词非管道全文的下划线目标现按实际生成序号续接，首批与后续字符块不能各自裁掉末词 `_`；进入下一块的原始提交空格不变为额外目标。慢测试由确认属于本轮的 xctest 采样定位于准确率活动词界查找内重复 `String.count`，超过四分钟后中止，不计通过。复用已有书写簇缓存和二分提交进度后，完整输入／回放／隔离记录约 20.65 秒通过；另有组合书写簇、emoji、退格、末词恢复与准确率回归，相关 212 项（1 默认耐力跳过、0 失败）通过。只验证引擎，不声明 IME 全阶段、半代理、真人键盘或长 GUI 体验等价；无图形实例、真实库操作、回填或发布，整体 goal active。

2026-10-02 最终门禁（亚秒归档／显式耐力）：客户端 1390 项（0 跳过、0 失败，十万词再次实际运行约 34.49 秒）、服务端 131 项、固定参考／原创性、649 场景清单和未开窗应用包通过。仍不等于实体输入日志、真人长测或 GUI 内存已验证；当前增量不变更原生输入分发，goal active。

2026-10-02 耐力与恢复时间窗补证：只读固定参考 `packages/challenges/src/index.ts:236–251` 核对十万词自定义重复挑战预算；测试使用自有 `typebar` 目标，不复制参考专用词或实现。显式 `TYPEBAR_ENDURANCE_TESTS=1`，按每词虚拟 0.5 秒持续 100,000 词，99,999 词仍活动，终词一次完成，799,999 单位／回放事件、49,999.5 秒及词历史完整。正式归档的先行小用例复现日期截断造成回放尾键丢失；新增兼容精度元数据后精确恢复时间窗，新增 11 项及相关 84 项均通过（0 跳过）。这只证明引擎、编码与恢复，不证明真人耐力、GUI 响应性、物理键日志或设备内存；本轮无 GUI，既有人工状态保持，整体 goal active。

2026-10-02 最终字面分隔补证：累计新增 16 项与相关 210 项（1 默认耐力项跳过、0 失败）通过；最终源码完整客户端 1379 项（1 跳过、0 失败）、服务端 131 项、固定参考／原创性及未打开 GUI 的原生打包通过。下方本轮“待执行／重跑中”由此取代，未使用早期 1377 项绿灯替代最终验证。字面候选／首词接线不证明融合提交、零目标、段进度／未来批次、非分段长文或全量输入已等价，实际设备和历史迁移状态不提升。

2026-10-02 同轮首词选择边界：依固定 `words-generator.ts:859–890`，随机段游标也按字面空格找首词，不能因空格附组合标记漏掉最近两词的重抽条件。补充 2 项先行 3 个有效失败断言，累计 16 项新增、相关 210 项（1 默认耐力项跳过、0 失败）通过，Tab 内容仍保留；夹具缺参数的编译错误不计行为失败。14 项阶段客户端 1377 项（1 跳过、0 失败）、服务端 131 项与原生打包通过，最终源码门禁重跑中，下方 14／208 为早期阶段数量。普通融合提交及完整 UTF-16 输入边界不提升。

2026-10-02 自定义字面提交解析：固定 `components/modals/CustomTextModal.tsx:175–185`、`test/words-generator.ts:888–894` 按字面字符而非书写簇拆候选段和内词。原生分段游标以独立标量扫描折合 CRLF／CR、映射有限特殊空格，按字面空格和管道拆分；组合标记留在后一个词。14 项新增、相关 208 项（1 默认耐力项跳过、0 失败）通过，先行 10 项有 39 个失败断言、扩展 12 项有 44 个失败断言，均为运行到真实行为后的有效红测。Morse 的字数／段数预算、词历史、反写可映射目标、102 词跨批与重复、回放和隔离记录有证据；全量门禁待本轮执行，无 GUI 新证据。

候选段字面拆分可用不等于所有 Unicode 输入可用：普通提交字符与组合标记融合、零目标、分段进度／跨批融合、非分段自定义与长文源路径仍待统一，不能凭推测词界提升计量或设备验收。Tab／未映射空白／零宽内容维持源默认保留，不引入泛化空白分词。无新持久字段、归档／协议版本、真实历史回算或发布／部署。

2026-10-02 最终单次目标接线补证：新增 18 项与相关 176 项通过，完整客户端 1363 项（1 默认耐力项跳过、0 失败）、服务端 131 项、固定参考／原创性及未打开 GUI 的原生应用包通过。下方本轮“门禁待执行”由此取代；已录目标接线不证明零目标／融合词界、旧缺失事件或实体键盘完整等价，未进行实际库迁移或历史回填。

2026-10-02 单次词目标接线：固定 `words-generator.ts:973–994` 保留变换后的 `wordRaw`，提交字符不触发第二次随机变换；原生提示、隐藏词界、词历史及完成／计量现共用一次独立变换所得目标。首批代码不再丢弃已采样文本，自定义有限／顺序／随机续批直接传递批次词目标；可靠外部边界在变换前使用。18 项新增与相关 176 项通过，包括总长度仍相等时的错误分词、70 种代码语言、实际跨批输入、重复开场、回放和隔离记录。先行 4 项 18 个有效失败断言，扩展另发现 ASCII 空格附组合标记的 3 个失败断言，现按 Unicode 标量拆字面提交；编译夹具问题不计行为红测。全量门禁待本轮执行。

零目标／跨词书写簇不伪造偏移，缺失旧词界不从随机重算恢复；这不是全部 UTF-16 输入等价证据。未排序原始配置、一般 bound、任意自定义游标 Unicode、未来随机目标重复恢复、半代理／完整日志与实际键盘仍待验证。未改持久化字段、既有结果或协议，无真实迁移、回填、发布、部署或 GUI。

2026-10-02 最终规范逐词补证：新增 17 项与扩展相关 158 项通过；完整客户端 1345 项（1 默认耐力项跳过、0 失败）、服务端 131 项、固定参考／原创性及未打开 GUI 的原生打包门禁通过。下方本轮“门禁待执行”由此取代。只关闭已列规范顺序／候选池／提交边界，原始未排序配置、随机长度词界、一般 bound、完整 Unicode／日志和实际输入仍未证明等价。

2026-10-02 规范组合逐词补证：固定 `config/setters.ts:156–205` 排序直接 toggle 的官方名称，`test/funbox/active.ts`／`list.ts` 保持数组顺序，`words-generator.ts:368–377,639–666` 按词变换并先反候选池。原生共享逐词策略不再让无空格合并破坏大小写相位，也不提前变换下划线；Morse→ROT13、双写→消息／随机、四类换行不双写、首 UTF-16 单元大写与消息内部换行／有限尾裁均有回归。17 项新增、扩展相关 158 项通过，先行 12 项有 37 个有效失败断言。此前下划线／分段组合夹具依据错误假设，现按排序／反池来源更正，保留原有完成、计分与词历史检查。全量门禁待本轮执行，无 GUI 补证。

只补证规范直接启用路径；外部原始未排序数组、一般词流 bound、随机长度变化的单次采样词界传递、随机池／方向呈现、零目标词、半代理／完整事件日志和实际键盘继续开放。没有参考实现／文本导入、格式迁移、真实数据回算或部署，旧 prompt／回放保持原样。

2026-10-02 最终 Funbox 词目标补证：`CustomFunboxWordTargetsTests` 新增 22 项、相关 147 项通过；完整客户端 1328 项（1 默认耐力项跳过、0 失败）、服务端 131 项、固定参考／原创性审计与未开启 GUI 的打包通过。下方本轮“门禁待执行”由此取代。记录往返验证 prompt／回放／既有字段，不证明旧无隐藏词界记录的全量词历史恢复；零目标词、任意组合、完整输入语义与实际设备仍开放。

2026-10-02 自定义 Funbox 词目标补证：固定 `funbox-functions.ts:601–612`、`generate.ts:32–100`、`strings.ts:9–11`、`words-generator.ts:430–499,938–1003`、`test-logic.ts:575–655` 与 `test-words.ts` 区分目标和提交。Morse 的 nospace 禁止空格提交；下划线在 bound／全局序号决定的位置参与目标变换，完成尾词后只能裁掉真实提交，不能删除 `_`。原生段游标现保留该边界，有限预取词数仍由实际输入预算结束；Morse 去重音不折叠全角，Swiss German 在变换前展示。22 项新增、相关 147 项通过，先行 17 项 269 个有效失败断言；测试成员引用编译失败不计行为证据。全量门禁本轮待执行，没有 GUI／实体输入补证。

代码、夹具与输入文本独立编写；不导入官方实现／资源，不写真实数据，不回算旧提示与日志。本轮不关闭零目标 Morse 词、所有 Unicode 事件／组合顺序或其他生成路径的下划线 bound；审计状态不再用“全部等价”遮盖这些剩余风险。

2026-10-02 最终独立分隔补证：新增 23 项、相关 106 项（1 默认跳过）通过；完整客户端 1306 项（1 默认跳过、0 失败）、服务端 131 项、固定参考／原创性审计及未打开 GUI 的原生打包门禁通过。下方本轮“门禁待执行”以本段为准；只关闭所述配置／生成／消费缺口，不宣称完整输入或所有修饰器组合等价。

2026-10-02 独立分隔补证：`components/modals/CustomTextModal.tsx:64–194` 的分隔与 limit 独立，`test/words-generator.ts:430–499,630–716,760–904,973–1030` 将选中段逐词消费。管道词数首屏按候选段数预取（硬上限百词），并非截断为词预算；真实输入仍按词数结束，后续有限尾批不得丢长段余词。原生独立游标支持四种完成方式、三种排序、空格 section、现有换行及 Unicode 空格规范化；随机 section 避免前两整段，词数／计时随机段则依前两实际词检查首词。新增 23 项回归含 70 个代码选择、101 词尾批、无空格 Unicode 词历史、重复未来抽样及旧历史不回算。初始 112 个有效失败、格式 3 个、空池 2 个、有限排序 1 个先行失败均已记录；完整门禁本轮待执行，不提升未执行的实体输入／GUI 或完整 Unicode 语义。

2026-10-02 最终补证：分段新增 22 项与相关 74 项（1 默认跳过）通过；完整客户端 1283 项（1 默认跳过、0 失败）、服务端 131 项、固定参考／原创性审计和未打开 GUI 的原生打包门禁全部通过。先行红测、夹具更正和来源边界见下文；不宣称整体输入等价。

2026-10-01 section 补证：固定 `test/words-generator.ts:430–499,630–716,760–904,973–1030` 将段内文本拆成实际词；最多百词一批，未完成段继续，文本变换后再追加提交，最终已生成才去掉提交字符。原生独立游标替换前 N 段静态拼接：70 个代码选择段间提交、换行、长段续批、0 无限、三种顺序、段进度、UTF-16 长度变化、noSpaces 词历史、Quick End 和 word-stop 错误终词修正由 22 项新增回归覆盖。13 项有效先行红测有 246 个失败断言；快速重开／Bail Out 各 1 个先行断言，反写提交顺序另 4 个先行断言亦复现并修正。随机重取上限、重复位置权重和重复测试未来批次使用合成自有文本，不导入参考夹具。GUI／实体候选栏未启动；其他 limit 模式独立 pipeDelimiter、完整 Unicode 与日志不据此升级为等价。

本轮最终补证（取代首阶段 14／76 数量）：16 项新增、相关 85 项通过。按 `validation.ts:60–90` 及 `before-insert-text.ts:78–92`，严格词首分隔符继续属第一字段、Expert 空输入不误失败，word-stop 的分隔符也受 UTF-16 输入上限；2 项先行复现 4 个失败断言。完整回归曾暴露长文本提交检查全历史分词，采样定位后终止该次自有测试并恢复局部扫描；原 60 万字符测试 19.811 秒通过，没有跳过／删减或改写其输入。完整门禁另行重跑。

2026-10-01 代码词数及 word-stop 更正：固定 `test/words-generator.ts:430–499,615–716,893–1010` 与 `input/helpers/fail-or-finish.ts:82–118` 共用词数／终词规则，没有代码整程序完成例外。70 个原生代码选择按原创语法词流生成和续接，有限尾批截至真实词数，代码终词共享 UTF-16 Quick End、错误词可编辑与实际提交；无空格保留隐藏词界，原多行缩进测试使用实际五词提示而非错误的一词整程序假设。官方语料不导入，静态原创内容多样性差异保留。

`input/helpers/validation.ts:41–90` 与 `handlers/insert-text.ts:238–290` 证明停止输入 word 只阻止导航，空格仍在当前输入内。原生保留该边界及后续文本，不增加完成词数或下一词速度信用；退格、删词、活动信心互斥及 Expert 失败覆盖，目标末尾的提前返回不能绕过它。可选回放 `commitsWord: false` 贯通游标、删除恢复、定位、声音游标和图表。有效先行代码测试 8 项复现 748 个失败断言；后续 12 项中的一项复现图表误计 12 WPM，现新增 14 项与相关 76 项均通过。旧事件无字段回退、JSON 与既有记录载体往返已验证；无真实数据库迁移、部署或 GUI。回放分隔符具体绘制、复杂 Unicode／半代理恢复、完整日志和真实候选输入仍不宣称等价。

2026-10-01 Quick End 与输入长度上限更正：依据固定 `input/helpers/fail-or-finish.ts:82–118`、`handlers/insert-text.ts:363–369`、`handlers/before-insert-text.ts:78–92`，普通有限模式的长度相等和当前词上限独立按 UTF-16 计算。有限提示不再强制等字形游标到目标末尾才 Quick End，仍要求最终词及全部生成；其他正确完成／提交路径保留。`QuickEndUnicodeTests` 的 20 项与相关 109 项（1 跳过）通过，覆盖长度反向反例、长 ZWJ 的前置输入上限、续批、原生候选不误确认、实际确认后完成、计量与便携结果。没有 GUI 或完整系统输入法证据；无空格／代码专用完成、半代理拆分、组合恢复和完整事件日志仍待单独核对。

2026-10-01 活动规则接线更正：固定 `config/metadata.tsx:465–560` 明示五项输入规则不重启；原先原生界面仅更新偏好，活动会话仍持有旧规则。现由受控同步入口接通自由回退、反向 Shift、四档自动删除、信心及 Quick End；需重启字段仅在来源明示互斥关闭停止输入时例外。已输入文本不回溯更改，错误候选不能因 Quick End 自动确认，正确候选的值拷贝预演不重复计分。`RuntimeInputRuleTests` 22 项与相关 98 项通过，含真实命令消费、无窗口 AppKit、终态冻结／重复及旧字段往返；没有实体键盘或候选栏的新验收。反向 Shift 左右手判断和 Quick End 的完整 UTF-16 终词长度边界仍需逐项补证，不把动态接线当作全部输入算法等价。

固定参考：`91bd24bb8513785c7364cbea29296ff7adafac41`。本审计只记录行为与证据，不包含或复用参考项目的代码、词表、资源或事件数据。

| 参考路径 | 固定源码行为 | 原生映射 | 自动化证据 |
| --- | --- | --- | --- |
| `input/listeners/misc.ts`、`input/input-element.ts` | 聚焦或选区变化后把光标压回输入末尾，并阻止复制、粘贴与选择。 | `TypingInputView` 没有可编辑缓冲区；响应者与 AppKit 文本命令路径均拦截复制、剪切、粘贴、全选及导航选择。 | `testTypingInputEditingPolicyBlocksClipboardAndSelectionCommands`、`testTypingInputNavigationPolicyBlocksOnlyPracticeNavigationCommands` |
| `input/listeners/key.ts`、`handlers/keydown.ts`、`handlers/keyup.ts` | 记录物理按键；重复 keydown 不重复触发快捷操作；常规方向／Home／End／Page 导航只在方向键模式外被吞掉。 | 原生桥记录按下、重复和释放；重开、放弃、禅模式结束与方向键模拟只接受首次按下，文本、Tab、换行和退格仍按系统文本输入处理。 | `testNativeInputBridgeReportsPhysicalKeyDownRepeatAndKeyUp`、`testNativeInputBridgeIgnoresRepeatedShortcutAndArrowActions`、`testNativeInputBridgeSendsArrowKeysToTheTypingEngineOnlyInArrowMode` |
| `input/hotkeys/konami.ts` | 练习页识别 Up、Up、Down、Down、Left、Right、Left、Right、B、A 的隐藏键序，并在完成后打开外部键盘练习站。 | `KonamiSequenceTracker` 在 `TypingInputView` 原有分发前只观察按键；方向取 AppKit 物理键码、B/A 取当前输入源给出的逻辑字符。重复键不推进，Command／Control／Option 组合会重置；完成时仅让 macOS 默认浏览器打开 `https://keymash.io/`，不上传提示、实际输入或按键时序。 | `testNativeInputBridgeRecognizesKonamiOnceWithoutSwallowingTypedLetters` |
| `input/listeners/input.ts`、`handlers/before-insert-text.ts` | 只处理受支持的插入、组合、退格和向后删词输入；不支持的浏览器输入类型不会进入计分。 | `NSTextInputClient` 的 `insertText` 只把确认文本送入批量插入；`doCommand(by:)` 的计分编辑映射后退、向后删词及允许的 Tab／换行，候选取消只清组合态；前向删除不改写已有输入。 | `testNativeInputKeepsMarkedCompositionOutOfTheTypingEngineUntilCommit`、`testWordBackwardDeletionClearsTheCurrentWordAndRespectsWordProtection` |
| `input/hotkeys/utils.ts` | 练习框聚焦且组合文本非空时，普通 Escape 不执行应用快捷键，由输入法处理；显式 Shift+Escape 不受这一例外影响。 | 非空 marked text 的无修饰 Escape 优先交给 AppKit 输入系统，不打开命令面板、重开或触发长测试保护；明确的取消命令清空候选而不提交。按下来源保留至对应 keyup，候选结束后仍正常报告释放；候选结束后的新 Escape 恢复原快捷键。 | `CompositionHotkeyTests` 的 6 项回归覆盖候选优先级、长测试保护、取消不提交、普通快捷键恢复、Shift+Escape 及跨候选结束的释放配对 |
| `handlers/keydown.ts`、`handlers/before-insert-text.ts`、`states/hotkeys.ts` | 普通 Return 不在 keydown 中模拟换行，换行只允许于含换行目标或禅模式；目标含换行时 Enter 重开迁到 Shift。Tab 则明确按目标中的 Tab 模拟插入。 | 允许换行且候选非空时，无修饰 Return 先交给 AppKit，可由输入法提交候选；下一次普通 Return 仍按原规则插入换行。显式 Shift+Return 重开、禅完成和长测试退出优先级不变；无换行目标中的 Enter 重开和 Tab 模拟路径不变。 | `CompositionReturnTests` 的 8 项测试覆盖 CR／LF、两种重开设置、提交及后续换行、按键事件报告、原有显式快捷键、Tab 与多行会话完成／回放 |
| `input/listeners/composition.ts`、`input/listeners/input.ts` | `compositionstart` 启动测试；普通候选更新只显示组合文本，`compositionend` 才提交。例外是全部目标已生成且最后一个词的当前输入加候选完全正确时，会自动结束组合并提交终词。 | 首次非空 `setMarkedText` 调用 `TypingSession.beginComposition`，不写入字符。终词候选由 `shouldFinishWithComposition` 用值拷贝预演普通批量输入，确认当前词完整匹配且有限测试可完成才经原有 `insertText` 路径提交；清空 marked range 后通知 AppKit 丢弃转换会话。主界面完成判定与实际输入共用镜像转换；Mouse Warrior 禁止物理输入的边界保留。 | 原有组合开始／确认回归，以及 `CompositionCompletionTests` 的阿拉伯文原生桥、中文词界、分批提示、有限模式、误匹配、强制错误、镜像与延迟确认回归 |
| `input/handlers/before-delete.ts`、`handlers/delete.ts` | 普通退格和向后删词受自由回退、信心模式、正确已提交词保护及代码反缩进共同限制。 | `TypingSession.deleteBackward` 和 `deleteWordBackward` 共用对应保护、代码反缩进及可回放删除事件。 | `testFreedomModeOnlyAllowsDeletingCommittedCorrectWordsWhenEnabled`、`testMaximumConfidenceModeDisablesBackspaceAndNormalizesConflicts`、`testCodePracticeAutoIndentsUnindentsReplaysAndFinishesWordMode` |

## 当前结论

固定参考输入监听器的可观察练习语义均已有原生映射。`FUNCTIONAL_INVENTORY.md` 的 `INP-01` 与 `INP-02` 是面向用户的汇总；本文件保留源码路径、原生边界和对应测试，防止后续更改把“组合开始计时但确认后才计分”的语义退化。

2026-10-01 导航实机补证：`MANUAL_ACCEPTANCE.md` 的 `INP-NAV-01` 现记录源码 `7e71af2` 单实例内存库 GUI 的 32 组普通／Shift／Option／Command 导航键、继续输入后的 9 字符全匹配，以及字数模式四方向推进 4/50 且零错误。自定义模式的箭头冲突拒绝同样可见。因未验证系统音频、Control+F/B 的实际派发及真人实体键盘，本项只是部分验收；单实例已正常退出、进程归零，不借此提升候选输入或全部输入边界的验收状态。

## 仍需人工验收

真实 macOS 输入源会因用户安装的输入法、候选栏和系统版本而异，自动化测试不能替代以下验证：

1. 用中文、日文或韩文输入法开始、更新、确认和取消候选，确认时钟从首次候选开始、只有确认文本进入提示与回放。
2. 在带附属 sheet、失焦提示和外部文本框间切换，确认候选组合不会越过焦点边界。
3. 用真实物理键盘验证 Option-Delete、死键和按键连发；布局输入仍必须由用户选定的 macOS 输入源决定。
4. 用真实中文／日文／韩文候选栏及第三方输入法验证终词完全匹配时自动确认、候选栏收尾与延迟回调。当前证据是直接调用 AppKit 输入桥，不冒称已验收真人候选窗口。
5. 在真实候选转换的不同阶段按 Escape，确认输入法可以逐级回退或取消，不误开命令面板、不重开测试；候选结束后释放 Escape，再按新 Escape 验证原快捷键恢复。
6. 在自定义多行、代码和禅模式中，用真实输入法按普通 Return 确认候选，确认不多插一个换行；之后再按 Return 应换行，显式 Shift+Return 仍执行配置的重开、完成或退出。

2026-10-01 多行候选 Return 更正：先行测试在 CR／LF 与关闭／Enter 重开四种组合中均得到换行而非候选提交，marked text 仍在；原因为直接换行分支提前返回。原生桥现只在允许换行、候选非空、普通 Return 的边界调用 Apple 的 [interpretKeyEvents(_:)](https://developer.apple.com/documentation/appkit/nsresponder/interpretkeyevents(_:))，不假定系统必然把这个键解释为换行，也不覆盖该方法。为稳定验证交接，内部视图允许测试子类仅替换 `inputContext`；受控 `NSTextInputContext` 按 [handleEvent(_:)](https://developer.apple.com/documentation/appkit/nstextinputcontext/handleevent(_:)) 的消费语义确认自有候选。8 项新增回归及此前 16 项组合输入回归通过；真实会话还验证后续新 Return 的换行、零错误完成及回放精确重建。测试没有改变系统输入源或启动 GUI，不代表实际候选栏、第三方输入法和实体键盘已验收。固定参考的 Tab 模拟插入路径保持不变，没有把所有候选态按键笼统移交系统。

2026-10-01 候选 Escape 优先级更正：先行测试复现候选期间误开命令面板、误重开或显示长测试保护，以及明确取消命令未清空候选。首批修正后，追加按键释放测试又复现候选结束后 keyup 被动态快捷键判断吞掉；现跟踪该次按下的来源，至匹配释放才清除。6 项新增测试及 10 项终词完成回归全部通过。依 Apple 的 [interpretKeyEvents(_:)](https://developer.apple.com/documentation/appkit/nsresponder/interpretkeyevents(_:)) 将按键交给输入系统，不假定每次 Escape 都必须丢弃全部转换；只有输入系统明确派发取消命令时才清空 marked range，并按 [discardMarkedText()](https://developer.apple.com/documentation/appkit/nstextinputcontext/discardmarkedtext()) 通知系统结束转换。这是直接 AppKit 调用的自动化证据，未启动 GUI，真人候选栏和实体按键仍待上列人工验收。

2026-10-01 终词组合完成更正：先行行为测试在终词阿拉伯文候选仍保持 active、marked range 未清空且无结果的路径失败；独立实现后，匹配候选沿现有批量输入完成并可由回放重建。完成探测不会修改真实会话；错误候选与快速结束、词界前的跨词候选、无限／计时／禅模式、候选本身或当前前缀的强制错误均不能绕过边界。分批生成只按真实终止规则完成，不把当前小批末尾当作最终目标；追加代码游标边界测试还证明，达到实际词数上限时不能因生成游标仍存在而拒绝完成，首次失败后已纳入同一准入规则。AppKit 收尾遵循 Apple 的 [discardMarkedText()](https://developer.apple.com/documentation/appkit/nstextinputcontext/discardmarkedtext()) 文档：先清空客户端 marked range，再让系统丢弃转换会话。未引入新依赖，也不读取或导入参考输入实现。
