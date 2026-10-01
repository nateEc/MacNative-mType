# 官方输入路径审计

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
