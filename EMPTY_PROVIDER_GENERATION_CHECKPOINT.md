# 在线空内容生成检查点（未验收）

## 后续定位与已验证的原生输入拆除修复

**完整门禁的存储崩溃仍未解决。** 本节输入生命周期修复不能替代门禁修复或证明功能等价。最终源码重跑 `provider-native-input-final-host-sequence.log`：输入拆除测试通过，17 项在线宿主断言全部通过（85.487 秒，总墙钟 85.489 秒），随后 PB 保存仍收到 signal 5。没有跳过保存测试、增加等待来掩盖问题或改变其预期。

进一步缩小所得证据：

- `provider-storage-four-hosts.log` 与 `provider-storage-five-hosts.log` 的两组分别通过，共 5 项/23.347 秒及 6 项/25.762 秒；不能把任意多个宿主直接解释为必然崩溃。
- 临时弱引用诊断的 9 宿主序列通过（`provider-storage-lifetime-probe.log`，10 项、49.407 秒），各自 teardown 时宿主、窗口、容器和上下文都已释放；扩大至 17 宿主仍崩溃（`provider-storage-full-lifetime-probe.log`），另有一次 Pace 断言失败。诊断改变了分配/时序，未据此宣称修复，临时诊断已经撤掉。
- 新增销毁断言证实替换为空根视图后，旧输入与提示视图均从宿主移除；17 项断言通过后保存仍崩溃（`provider-storage-root-disposal-sequence.log`，85.797 秒）。这些断言保留，检查的是可观察原生视图树，不等于证明全部查询观察器已释放。
- 自有临时最小查询宿主连续 20 次挂载、观察真实保存、销毁并向另一份存储保存，测试通过（`provider-query-saved-lifecycle-probe.log`，1.040 秒）。仅添加捕获查询页面值的未绑定延迟任务即可触发 signal 5（`provider-query-unstructured-task-red.log`）；报告 `xctest-2026-10-11-234341.ips` 的前三个框架栈帧与门禁相同。这证明一种触发机制，不证明已找到真实练习页的全部触发路径。
- 将焦点提示延迟改为视图绑定任务的实验仍未消除完整序列崩溃（`provider-focus-task-lifecycle-green.log`：17 项宿主通过后保存崩溃，文件名不是通过结论）。该实验与临时 SDK 查询测试均已撤回，最终 `TypebarApp.swift` 没有此实验改动。

另一个可独立证明的缺陷已修复：`NativeTypingInput` 原先没有拆除清理，AppKit 继续持有原生视图时，其页面回调也继续持有页面。新增真实 representable 拆除测试在修改前出现 4 个预期断言失败（`provider-native-input-lifecycle-red.log`，0.701 秒）：捕获对象未释放、组合结束谓词和时钟未清理、18 个晚到回调仍执行。现在拆除时清空全部页面回调和测试时钟、移除窗口观察器及本地按键监视器，排队聚焦改为弱引用。

会话内决策审查（非独立审查）另发现拆除与实际脱离窗口之间仍可能存在排队聚焦。新增断言在仅清回调的版本明确失败（`provider-native-input-retired-focus-red.log`，0.726 秒）；现以退役状态阻止排队聚焦、再次接受第一响应者以及重新安装窗口观察器。未对正常仍挂载的输入禁用回调或快捷键。

最终相关回归 `provider-native-input-retirement-regression.log`：131 项、0 失败、无跳过，4.332 秒（总墙钟 4.344 秒），覆盖拆除、焦点投递、组合选择/子串/完成/快捷键、实时指标与反馈、运行中输入规则、字边界删除、组合字符输入和位置恢复。只在 macOS 26.1 / Apple Swift 6.2.4 验证，不宣称所有最低支持系统或实体输入法已验收。所有宿主窗口不可见，未启动 Typebar 主程序。

原创边界检查通过（`provider-native-input-retirement-originality.log`），未发现与固定参考源码的长字面量或受保护资源重叠。本轮保留的产品修改仅为原生输入生命周期修复；存储崩溃继续定位，在线生成调度等原始功能差异仍开放，目标保持进行中。

## 最新完整门禁失败：宿主序列后的存储崩溃（2026-10-11）

冻结提交 `f263ce264c0036093319825da9a9ee153e531f58` 的完整门禁未通过，不能作为发布或功能等价证明。证据目录 `work/frozen-readiness-live-pool.70eThg` 位于项目所在工作区：`result.txt` 为 `gate_exit=1 hash_exit=0`，865 个受跟踪文件的 SHA-256 检查通过。客户端进程 xctest（PID 84359）在 `LocalPersonalBestLedgerTests.testAccountResetCreatesKnownEmptyLedgerInsteadOfRebuildingOldHistory` 的首次保存处收到 signal 5；服务端测试和发布打包阶段没有执行。失败退出后日志仍在门禁临时目录，已另行复制其中 73 份日志至证据目录的 `logs/`，没有覆盖已有日志。

崩溃报告 `xctest-2026-10-11-232211.ips` 的主线程栈为本地 PB 保存 → SwiftData 保存通知 → `_SwiftData_SwiftUI` 观察器 → SwiftData EXC_BREAKPOINT。这定位了边界，但尚未识别具体失效查询对象，不能断言已经找到根因。十万词耐久用例在该轮通过，耗时 162.375 秒，不代表后续客户端完整套件通过。

缩小验证均使用 `TYPEBAR_QA_IN_MEMORY_STORE=1 swift test`（已有构建时加 `--skip-build`），没有启动 Typebar 主程序：

- `provider-full-gate-storage-reproduction.log`：连续运行 17 项 `LivePracticeReplacementHostTests` 后，接上述 PB 测试，再次 signal 5。宿主阶段另有一次 Pace 标记断言失败，未删除或放宽断言。
- `provider-storage-tail-half.log`：后半组 9 个宿主场景接 PB 保存仍崩溃；组合输入场景另有一次提示视图不存在的断言失败。尚不证明这些表现与存储崩溃具有同一根因。
- `provider-storage-autorelease-lifetime-check.log`：临时尝试显式保留 ModelContainer，并将宿主操作置于 autorelease pool。17 项宿主断言全部通过，随后 PB 保存依旧崩溃；该无效改动已经完整撤回。
- 单独的 NoQuit 失败恢复、组合输入、三次空初始化场景分别接 PB 保存均通过，见 `provider-noquit-storage-minimal-red.log`（文件名不代表实际失败）、`provider-composition-storage-minimal.log`、`provider-empty-init-storage-minimal.log`。
- 其余后半组六个场景逐个与 PB 保存配对均通过，见 `provider-storage-pair-test*.log`：未锁定续取失败、初始化填充失败、晚到初始化失败、离开练习取消、输入后晚到响应、单飞续取。
- 两个续取失败宿主场景连续运行再接 PB 保存也通过：`provider-storage-two-hosts.log`，3 项、0 失败，15.902 秒（总墙钟 15.904 秒）。因此还不能把“多个宿主”泛化为任何两个宿主必然触发，须继续缩小具体序列或累积条件。

当前没有保留猜测性的产品或测试修复。下一步定位具体连续宿主组合及保存通知观察器生命周期，修复后必须重跑失败序列及完整门禁；在线生成调度、false/undefined 分类等下述功能差异仍然开放。目标保持进行中。

参考源码固定为 `91bd24bb8513785c7364cbea29296ff7adafac41`，不表示最新版本。
本次原生实现没有复用参考实现代码或资产。

## 本次行为

- 成功解析但清洗后没有词的诗歌，与传输或解析失败区分，保留标题和作者。
- 初始化空生成最多尝试三次；终止时保留来源开关，不产生未开始练习的成绩。响应不能替换已经输入的练习。
- 运行中空段落不按网络失败关闭来源或恢复离线提示；仍有目标时保留当前练习，后续输入进度才再次请求。目标耗尽则以词生成失败终止，保留已接受输入及回放。

## 验证与未解决项

`poetry-empty-regression-final.log`：36 项相关测试，35 项通过，1 项失败，耗时 72.392 秒（总墙钟 72.397 秒）。所有新增空内容用例通过。原有 `testLiveResponseAfterFirstInputPreservesPromptAndMainCaret` 未改断言，仍失败：响应前主光标 x 为 -8.654296875，响应后为 8.654296875。

单独临时诊断运行通过，但诊断前后位置均为 8.654296875，不能证明显式呈现修复了问题，也不能据此认定根因。临时诊断代码已撤掉。此前相关运行亦出现同样光标失败，仍需定位输入接受、布局与呈现之间的顺序。

后续 `caret-pre-transport-presentation.log` 在同一测试回复前抓到 sampled=-8.654296875、presented=8.654296875：尚未回复时，真实呈现器已能解析接受首字符后的位置，证明之前基准可能是过期呈现帧。不可见宿主测试现在在输入前、输入后和响应后显式执行同一真实呈现器；增加首字符必须前进的断言，并保留响应前后精确相等断言，不增加等待或重试。`caret-presented-baseline-regression.log` 联合光标组件、在线替换、诗歌清洗、来源字段会话共 51 项通过，耗时 71.123 秒（总墙钟 71.129 秒）。这只修正状态保持测试的采样边界，不证明真实窗口的自动首次呈现延迟已经解决。

独立复跑上述光标用例和空初始化不能替换已开始练习用例，2 项通过（`caret-presented-baseline-repeat.log`，9.362 秒，总墙钟 9.364 秒）。本次原创边界检查通过（`provider-addword-caret-originality.log`）；未重跑客户端全量、服务端或发布打包门禁，因为本次仅修改测试、只读参考探针和审计文档。

原创边界检查通过，日志 `poetry-empty-originality.log`。测试仅使用不可见宿主，未启动 Typebar 主程序；错误文案可读性没有完成可见界面验收。旧版本全量验收不覆盖本次修改。

参考运行中 `addWord` 在收到空段后仍会调用 `getNextWord`，可能消费剩余段或继续取段。本次“等待后续进度再请求”的时序没有证明与完整参考调用链等价，需继续执行完整调用链行为探针并对齐。初始化传输失败的修复见后续章节，仍保留原生请求期间可输入的交互差异。本文件不是完整功能等价或发布就绪证明，目标保持进行中。

## 完整 addWord 函数探针所得差异

`check-source-generated-backwards-order.mjs` 从固定只读源码在内存中提取完整 `addWord` 函数，调用实际完整 generator、funbox-functions 和 test-words 模块。提供者响应、活动词索引、UI、通知、重启及计时失败出口是自有边界；不是完整 test-logic 模块、真实网络或浏览器验收。日志 `provider-complete-addword-probe.log` 的六例均通过：

| 响应及生成器残留 | 固定参考的实际结果 |
| --- | --- |
| 空段，有残留词 | 取段一次，追加一个残留词，不关闭来源 |
| 空段，无残留，第二次有效 | 同一 addWord 内取段两次，追加新词，不等待后续输入 |
| 空段，无残留，第二次仍为空 | 同一 addWord 内取段两次，以 word generation error 失败，不关闭来源 |
| false，有残留 | 请求关闭来源并重启，不追加残留词；是否允许执行须另验真实守卫 |
| undefined，有残留 | 直接返回，不关闭来源、不重启、不追加词 |
| 有效两词段，有残留 | 追加段内两词后，仍追加一个生成器残留词 |

这证实当前原生“空段后等待输入”与参考不等价；网络 API 把 false/undefined 合并为 nil，以及原生续取与生成器残留词池关系，均需继续设计与实现。不能把当前已通过的原生测试解释为这些差异已被消除。

## 初始化传输失败修复

固定 `poetry.getPoem` 在网络、JSON、缺少首个文档等失败时返回 false；实际 generator 探针已证明 false 会请求关闭 poetry 并抛出一般生成错误。对于允许切换的正常未开始初始化，`test-logic.init` 的 catch 再调用 init，此时该来源已经关闭。记录器不能证明活动 NoQuit 也允许关闭，见后续真实守卫更正。原生原先收到 nil 后仅显示离线回退文案、保留来源开关，与此不同。

现在在请求 ID、取消、配置及未开始守卫通过后，nil 会仅移除失败来源，保留 NoQuit 等其他修饰器，重建未开始的离线练习。不为旧的未开始尝试创建成绩。成功解析的空段仍走三次空生成边界，不进入该分支。若输入已开始，则保持当前尝试、输入所有者与光标，不关闭来源、不绕过 NoQuit；这是原生已有“请求期间可输入离线提示”边界的保护，不证明与参考完整初始化交互等价。

红测 `provider-initial-transport-red.log` 的两项未开始场景各有来源开关和预设未关闭的产品断言失败。另有三项请求数断言错误地假设启动只发一次请求；实际切换完整预览会先取消旧请求，已改为记录回复前计数并要求失败不增加请求，而非容许额外重试。修改后聚焦三项通过（`provider-initial-transport-green.log`，9.019 秒，总墙钟 9.021 秒）。补充“首段有效、补齐阶段失败”覆盖丢弃部分在线词，联合在线替换、完整预览、字段会话/目标、诗歌清洗、NoQuit 及公开内容解析共 55 项通过（`provider-initial-transport-regression.log`，85.459 秒，总墙钟 85.466 秒）。仅使用不可见宿主，未验收失败提示的可见可读性；未重跑全量或发布门禁。

本轮决策审查（会话内审查，非独立审查）发现不能只把空段分支改成再取一次：`loadedLiveContentWordCount` 把尚未发布的 `externalPromptContinuation` 也计算在阈值中，而参考 `addWord` 只按实际 TestWords 长度计算，剩余词保存在 currentSection。参考 `word-navigation.goToNextWord` 在每次前进时调用 addWord；原生当前只在目标耗尽时批量追加 continuation。因此后续须区分已发布目标、逐词生成器剩余池和旁路续取段，保持来源字段、有限预算、重复回放与取消守卫，再对齐正常段、空段和失败路径；不能靠调整一个阈值宣称完成。

## 剩余词池逐词消费：第一阶段

固定只读源码的新增连续探针执行完整 addWord、真实 generator 与词存储模块，以自有活动索引模拟前进前的 0、1、2：100 个已发布字段和 3 个剩余字段时，每步只发布一个，不取段；到有限目标 103 后不再添加，最后字段没有提交符。`provider-sequential-tail-source.log` 通过。未执行完整导航函数、浏览器或实体输入，不能据此证明这些边界。

原生新增同样的连续会话断言，修改前 1 项出现 4 个预期位置/词序失败（`provider-sequential-tail-red.log`，0.842 秒）：前进和重复练习都未逐词暴露尾词。现在把在线剩余池接入既有前进补词入口，沿用可见未来词边界；普通非在线 external continuation 仍按原批次边界暴露。已验证来源字段保留内部 LF、组合字符与无空格词元，不重新随机采样或变换；重复练习使用不可变初始池。

风险审查发现每次重建整个尾批会反复复制长段。因此实际已验证字段使用整数游标消费，只构造当前字段；新段到来时仅拼接未消费的尾部，并清零游标。loaded 预算扣除已消费游标，避免重复计数；初始历史不随游标改写。缺少字段元数据的旧调用者保留 ASCII 空格回退，不宣称其全部换行语义或长内容性能已经等价。

验证：会话聚焦 12 项通过（`provider-sequential-tail-green.log`，0.143 秒，总墙钟 0.145 秒）；扩大 133 项通过（`provider-sequential-tail-regression.log`，102.252 秒，总墙钟 102.266 秒）；游标版同范围 133 项通过（`provider-sequential-tail-cursor-regression.log`，101.357 秒，总墙钟 101.371 秒）。随后增加普通/下划线两种“消费部分尾词后追加新段”场景，检查不重复、不超预算和完整重复词序，会话共 16 项通过（`provider-sequential-tail-partial-section.log`，0.374 秒，总墙钟 0.377 秒）。这些是不可见测试，不是自动首帧性能或真实输入法验收；本轮未跑客户端全量、服务端或发布门禁。

仍未完成：网络续取阈值尚计入未发布剩余池；旁路续取新段与生成器取段没有分开；空段的第二次取词及 false/undefined 分类仍未完整对齐。新段到来仍会一次发布剩余池再追加段，不能把本阶段逐词消费的通过结果解释为完整运行中调度等价。

## 活动 NoQuit 的失败守卫更正

继续审查调度前发现旧证据边界遗漏：之前完整 addWord 函数的 toggleFunbox/restart 都是自有记录器，只证明请求被发出，不证明真实 setter 和 restart 会允许执行。固定 `config/setters.toggleFunbox` 和 `test-logic.restart` 都会拒绝活动 NoQuit 的请求，不能据记录器得出“来源失败可以先结束锁定会话再关闭来源”。此前名为 `testFailedPrefetchRestartsOfflineEvenWhenNoQuitLockedTheActiveAttempt` 的测试冻结了错误预期，现已由真实守卫所证明的保留/恢复断言替代，未跳过用例。

新增探针在内存执行完整固定 addWord、toggleFunbox、restart 函数，使用真实 generator/词存储，活动状态、配置对象、通知及提供者是明确的自有边界；守卫后的未用依赖没有伪造成功实现。活动 NoQuit、续取 false 时，setter 和 restart 各发拒绝通知，来源和剩余池不变，不派发 generation failure，不追加词。之后提供有效两词段，仍能追加它们及原剩余词。`provider-noquit-real-guards-source.log` 与 `provider-noquit-real-guards-recovery-source.log` 均通过；不是完整事件总线、浏览器或生产网络验证。

原生现在在失败续取的结束/移除来源操作前检查当前尝试的 NoQuit 策略：锁定时仅结束本次请求和 loading，保留活动会话、输入所有者、提示、来源、预设和锁；不紧循环重试，后续前进可再次续取。未锁定时原有关闭失败来源并重建离线练习的行为保留。成功解析空生成的分支没有被改为 NoQuit 传输失败处理。

证据：新的宿主红测 1 项出现 8 个预期失败（`provider-noquit-prefetch-red.log`，10.178 秒，总墙钟 10.179 秒），明确显示来源关闭、锁释放、在线提示被离线词替换且无法按后续进度恢复。修复后锁定/未锁定两项通过（`provider-noquit-prefetch-green.log`，16.297 秒，总墙钟 16.299 秒）；相关联合 138 项通过（`provider-noquit-prefetch-regression.log`，103.497 秒，总墙钟 103.512 秒）。本轮未启动 Typebar 主程序，使用不可见宿主；未验证错误提示可读性、真实 NoQuit 输入法、耗尽全部已发布目标后的重试或完整调度等价，也未重跑全量和发布门禁。
