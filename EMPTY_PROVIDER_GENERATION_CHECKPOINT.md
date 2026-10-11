# 在线空内容生成检查点（未验收）

## 首次生成重试调用方实证（2026-10-12，原生尚未修改）

新增自有 `check-source-initial-generation-retries.mjs`，只读提取并执行固定参考 test-logic.ts 的完整 init 函数；生成器结果、语言和 UI 为显式自有适配器。连续三次异常、空生成／异常混合、第三次恢复三组通过，日志 `work/initial-generation-retry-caller-source.log`。每组恰好三次生成及三次词表重置；两组耗尽时显示一次初始化失败、提交一次捕获错误、退出 restarting 状态且无第四次生成；第三组发布有效目标并成功返回，不显示初始化失败。异常和 WordGenError 共用重试计数，配置来源未被调用方关闭。此探针不执行真实生成器、提供者网络或实际界面，不能据此声称诗词 false 不会关闭来源；其关闭来源发生在原版生成器另一边界。

探针已接入后续完整门禁的独立日志阶段；zsh 语法检查、固定参考原创性检查通过（`work/initial-generation-retry-caller-originality.log`），未启动主程序。当前原生首次百科 nil 仍立即关闭来源并离线重建，且空段／异常没有统一计数；本轮未修改产品或声称兼容性修复。下一步以真实不可见宿主建立百科连续失败／恢复／已开始输入边界红测，再落实有界初始化重试。新探针未运行新完整门禁，旧冻结通过仅覆盖其原提交，goal active。

## 诊断开启的冻结完整门禁通过（2026-10-12，非全部功能验收）

冻结提交 `8038bcea2849a13fba0ee4f31b5024bad3556726`，开启 `TYPEBAR_QA_COMPOSITION_DIAGNOSTICS=1`，固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41`；单会话完整门禁退出 0，文件校验退出 0，870 个跟踪文件保持一致。证据 `work/frozen-readiness-composition-diagnostic.3zeTnk` 含 commit.txt、files.sha256、hash-check.log、result.txt、gate.log 及自动留存的 77 份日志。本次日志留存成功不代表旧失败路径未留存的原因已修复。

客户端 4389 项零失败无跳过，2122.632 秒（墙钟 2123.135）；29 项在线宿主 205.336 秒（墙钟 205.340），随后同进程 19 项 PB 台账 0.219 秒（墙钟 0.221）；10 万词耐久 160.504 秒；42 项组合宿主 963.277 秒（墙钟 963.284），原失败用例 21.592 秒通过且未触发缺失投影／宿主诊断；Tape 换行 10 项 4.846 秒（墙钟 4.848），包含实际异步退役通知用例。服务端 501 项零失败，11.052 秒（墙钟 11.111）。Release 构建 416.94 秒；未启动应用包的严格签名、第三方许可、资源边界及原创性检查通过。全程无 Typebar 主程序实例，终态后确认无 xctest，工作区干净。

本轮完整绿色记录覆盖上述冻结提交，不撤销 `cf43af4` 的历史组合输入失败，也不证明其因果机制已经解决；当前只能记为诊断开启后未复现。Tape 观察修正通过本轮完整序列，但不扩展为所有异步边界已验收。首次百科失败重试、旁路发布顺序／阈值／同调用空段重取、重复历史原版语义、实体 IME、视觉与 Release 性能、主题及其他覆盖缺口继续开放。不要继续以重复绿色测试代替尚缺用户可见行为的实现，下一步应回到来源初始化等已确认兼容性差异；整体 goal active。

## 缺失投影有界诊断（2026-10-12，非修复）

连续宿主未复现后，沿渲染调用方检查发现：期望使用投影但 PromptCompositionPresentation 返回 nil 时，提示可走普通 Text 分支；仅观察 PromptFieldNativeView 缺失无法区分该分支与挂载问题。新增 CompositionProjectionDiagnostics，在 Debug 且 `TYPEBAR_QA_IN_MEMORY_STORE=1`、`TYPEBAR_QA_COMPOSITION_DIAGNOSTICS=1` 同时启用时，只对带 marked text 的缺失预期投影输出最多 20 次状态；仅含 started／finished／fieldAvailable 布尔值，不记录提示、输入、身份、错误内容或结果。开关进程级缓存；Release 不执行诊断，不修改呈现选择、输入、排空或断言。后续完整门禁需要显式打开诊断以收集失败时状态；没有输出本身不能证明没有挂载问题。

此为未复现缺陷的观察性增量，按行为优先流程的探索性例外，不伪造产品修复红测。三项诊断测试验证双开关、仅目标状态消耗预算和第 21 次抑制、固定无内容记录格式。首次诊断与原宿主共 4 项通过，21.298 秒（墙钟 21.300）。缓存开关后的最终回归 35 项零失败无跳过，21.626 秒（墙钟 21.630），实际覆盖诊断、字段、投影和原失败宿主；筛选中的不存在类名 PromptCompositionPresentationTests 不计覆盖，随后补跑真实 PromptCompositionRenderingTests／PromptCompositionPlanTests 共 31 项零失败无跳过，0.714 秒（墙钟 0.717）。日志 `work/composition-projection-diagnostics-{regression,final-regression,rendering-regression}.log`；宿主未触发缺失诊断，不算原失败根因已定。原创性脚本直接执行因权限退出 126，随后 zsh 调用退出 0，两份日志分别保留于 `work/composition-projection-diagnostics-originality{,-zsh}.log`。仅不可见串行测试，零主程序实例；Release 和新完整门禁尚未执行，goal active。

## 组合输入连续宿主复现结果（2026-10-12，未定位）

在 `0a3d8c9ddcb3bdea11ba683d0e803ed172e24d9b` 上，保持产品和测试不变，单独运行原失败用例：1 项／0 失败，21.589 秒（墙钟 21.591），日志 `work/composition-diagnostic-focused-01.log`。随后只启动一个测试会话，以 `PracticeCompositionHostTests` 筛选连续执行；该筛选同时匹配 SpecialPracticeCompositionHostTests。实际共 44 项／0 失败／无跳过，987.743 秒（墙钟 987.750）；其中普通组合宿主 42 项，978.608 秒（墙钟 978.614），特殊宿主 2 项，9.135 秒。原失败用例本轮通过，21.174 秒，日志 `work/composition-diagnostic-class-sequence-01.log`。退出码 0，终态后确认无 xctest 或 Typebar 主程序进程，工作区未改动。

仅保留该测试类的前序执行顺序不足以复现完整门禁中的提示缺失；本轮没有触发已有失败诊断，不能判定原因或声称修复。旧失败用例仅执行 8.828 秒，不能直接归因于默认 30 秒计时结束；组合确实启动真实计时，但仍缺少失败时会话／投影状态证据。后续应区分投影失效与原生视图挂载边界，不盲目延长排空、放宽断言或重跑直到绿色。完整门禁的失败记录继续有效，功能未升级验收，goal active。

## 冻结百科修复门禁失败及 Tape 通知观察修正（2026-10-12）

冻结提交 `cf43af495c9bdcbd6d26d4351553d1f20070f2a4` 的完整门禁已退出 1，文件校验退出 0；868 个跟踪文件保持一致。证据目录 `work/frozen-readiness-encyclopedia-rejection.N0lV1Y`。客户端 4386 项／3 个失败断言／无跳过，2114.325 秒（套件墙钟 2114.927）；三个断言来自两个用例：PracticeCompositionHostTests.testProductionCompositionModesUpdateAndCancelWithoutCommitting 在当时第 389 行、下方候选已存在时无法取得 PromptFieldNativeView；TapeNewlineTransitionTests.testActualNewWordAwaitsVerticalDeletionBeforeHorizontalRequestAndAsyncNotification 的当时第 73／74 行未看到退役通知及尝试 ID。42 项组合宿主共 1 失败，943.894 秒（墙钟 943.900）。此前 29 项在线宿主及随后同进程 19 项 PB 台账通过，10 万词耐久 162.451 秒通过；均不覆盖上述失败。客户端失败后服务端及 Release／打包阶段未执行，不引用历史通过替代本次结果。

退出清理没有将日志保存到指定 logs 目录；原临时目录仍存在，终态后已以不覆盖方式补存 75 份日志。保留原 gate.log、result.txt、files.sha256 及 hash-check.log；没有修改失败记录或删去诊断。该日志留存机制的原因尚未修复。

未修改实现的两项最小复现 `work/composition-and-tape-unmodified-focused-repro.log`：组合宿主通过（21.799 秒），随后 Tape 再现相同两个断言失败；共 2 项、2 失败，21.866 秒（墙钟 21.868）。Tape 单独运行通过（`work/tape-newline-isolated-unmodified-repro.log`，0.129 秒，墙钟 0.131）。因此不能以单次通过声称两项已修复或未经验证地归为同一原因。

Tape 的实际 deliverRetirement 使用主队列异步投递，测试原本仅排空主循环 2 毫秒。观察探针保留该排空并等待真实通知：明确记录 `rtl=false` 在旧排空结束时仍未通知，随后实际回调到达、值与尝试 ID 断言通过（`work/tape-newline-real-notification-observation.log`，2 项／0 失败，21.429 秒，墙钟 21.431）。最终测试改为 XCTestExpectation 有界等待真实回调，仍在等待之前断言原生前缀已删除、水平运动已开始、会话通知未同步执行；未修改产品通知策略或增加盲目 sleep。相关其他测试继续保留其自身排空语义，本次不推广为全部通知时序已验证。

组合输入提示缺失尚未重现其门禁失败：仅在该原断言之前增加失败时的有限诊断，记录宿主轮次、尺寸策略、组合样式、marked 状态、输入所有者身份、候选数和布局次数；不记录用户内容、不放宽断言、不增加等待或替代提示。根因仍未确定，不能把之后的绿色组合用例算成修复。

首轮相关回归 `work/tape-notification-boundary-regression.log` 为 61 项／0 失败／3 跳过，缺少参考与锁定依赖环境；未计跳过为通过。补齐固定参考、Node 和既有锁定 Anime.js 档案后，同组最终回归 `work/tape-notification-boundary-complete-regression.log`：61 项／0 失败／无跳过，28.939 秒（墙钟 28.947），含原组合宿主及 Tape 前缀、换行、退役、可见性和组合前进。仍需解决组合宿主门禁失败并重跑完整门禁，不升级功能验收。全过程仅不可见 XCTest，Typebar 主程序零实例，goal active。

## 原生百科续取异常保留来源（2026-10-12）

真实不可见练习宿主新增回归，在旧实现中两项／9 个断言预期失败（`work/provider-encyclopedia-rejection-host-red.log`，18.980 秒，墙钟 18.982）：无锁生成器失败关闭了百科来源与预设；旁路失败重置为离线提示、关闭来源并阻止后续在线恢复。产品现在按固定两种提供者契约处理续取 nil：诗歌保持既有 false 处理；百科生成器失败结束尝试并呈现失败结果，但保留来源与预设；百科旁路失败只收束当前异步任务，保留尝试、提示、原生输入所有者及 NoQuit 状态，可在后续前进时再次续取，不立即循环重试。

有界会话内决策审查（非独立审查）检查了 NoQuit、来源预设及取消边界。没有增加实际提供者不会产生的 undefined 状态；仍以现有来源身份区分诗歌 false 与百科拒绝的契约。原生在任务边界收束旁路异常，**不复刻未捕获异常影响宿主稳定性的行为**；此为明确的原生异常承接方式，不是网页全部错误呈现等价声明。Optional 仍未保留具体传输／解析原因，且实际百科 onload 内 schema 异常等边界未执行，不将所有 nil 都称为已经证明的原版 Promise rejection。

修改后五项新宿主测试通过（`work/provider-encyclopedia-rejection-host-green.log`，49.753 秒，墙钟 49.755），含有／无 NoQuit 的生成器失败和旁路恢复，以及离页后晚到生成器失败。扩大回归 `work/provider-encyclopedia-rejection-native-regression.log` 144 项／0 失败／无跳过，221.046 秒（墙钟 221.061），其中 29 项真实宿主 199.861 秒；涵盖诗歌旧路径、百科传输、生成器、源字段、整段预览、LF／中文及代码输入。首轮筛选的三个类名未匹配，不算执行；随后以实际类名补跑 `work/provider-encyclopedia-rejection-storage-boundaries.log` 31 项／0 失败／无跳过，0.248 秒（墙钟 0.252）：19 项 PB 台账、8 项字段目标、4 项 NoQuit。它们是**两个独立测试进程**，不能替代完整门禁同进程宿主后 PB 序列。三个只读保存错误来自台账的既有明确失败场景，相关断言通过，不据此忽略其他存储错误。

本次未改初始化失败策略；其百科拒绝重试／来源保留仍待对齐。旁路阈值、发布顺序、同调用空段重取、实际网络／实体 IME／Release 性能等原有缺口继续开放。仅不可见 XCTest 宿主，Typebar 主程序全过程零实例。历史完整门禁不覆盖本次改动；目标保持 active，不升级为全功能验收。

## 实际调用方拒绝传播探针（2026-10-12）

在既有固定参考完整 addWord／真实生成器／真实字段存储探针中新增两个拒绝 Promise 场景，自有提供者适配器抛出同一个可辨认 Error，而非返回 false：一字段的旁路请求将该拒绝原样传播，未发布新字段、未消费已有余池、未通知、未派发失败、未切换来源、未重启；100 字段的生成器请求捕获拒绝，派发 word generation error 并通知，但不切换来源、不重启、不发布字段。两项及既有全部探针通过，日志 `work/provider-rejection-caller-source.log`。新增探针先验证外部契约，不做生产修改，因此没有原生红绿修复结论。

这把上一节百科拒绝传播的调用方推断推进为可执行证据，但适配器仍绑定 poetry 名称，仅隔离相同函数契约的拒绝传播；并未执行实际百科网络模块、真实浏览器导航或错误呈现，不能冒称百科端到端验收。原生 fetch 的 Optional 仍将百科拒绝折叠到 nil，生成器 nil 分支可能请求关闭来源，与本探针的拒绝路径不同；需保留这一已定位差异，后续在真实原生宿主建立回归后区分提供者失败原因，不能据此复刻网页未捕获异常而破坏宿主稳定性。旁路顺序、阈值、同调用空段重取仍开放，goal active。

## 提供者响应可达性审查（2026-10-12）

固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41` 的 poetry/wikipedia funbox 包装只转发实际提供者。`getPoem` 的成功路径返回 Section，空数组及捕获的异常返回 false，没有正常返回 undefined 的路径。新增只读探针 `Scripts/check-source-poetry-outcomes.mjs` 在隔离 VM 中执行完整实际 poetry 模块，仅替换网络响应与 Section 数据容器：自有正常两词、成功空段、空数组、缺少 lines、JSON 拒绝、传输拒绝共六项通过，日志 `work/provider-poetry-outcomes-source.log`；已接入完整门禁，但本轮未重跑完整门禁。空段是成功内容而非 false。VM 模块及类型擦除实验性警告不影响本次断言，也不证明后续 Node 版本兼容。

百科的实际 getSection 返回 Section 或拒绝 Promise，包装没有 catch 转 false；旁路 addWord 的 await 位于生成器 try/catch 之外。因此其拒绝不能直接宣称与诗歌 false 的通知、关闭来源及重启路径等价。本轮只做源码定位，未运行百科异常端到端探针，不能断言网页可见错误呈现或最终状态。原先 authored undefined 响应测试仅证明调用方防御分支，不是实际提供者可达性证据；保留其边界身份，不据此新增原生 undefined 产品状态。

会话内有界决策审查（非独立审查）的反例是百科 Promise rejection：原生 Optional 折叠失败可能抹去来源间异常差异，不能仅增加三态枚举就认定兼容。下一步仍需明确异常传播及旁路发布顺序、已发布字段阈值和同调用空段重取；本轮没有修改生产失败策略或升级功能验收分类。全程零 Typebar 主程序实例，目标保持 active。

## 真实异步宿主接线与前进需求时序修正（2026-10-12）

生产练习现在在实际词前进时选择独立生成器请求；少于 20 词的既有旁路请求仍优先，初始化不会凭空发生成器请求。沿用单飞、请求身份、配置及取消守卫；生成器成功响应通过新会话入口只发布一个字段并保留余池，不替换原生输入所有者。生成器成功空段立即结束尝试、保持来源；传输失败结束原尝试，不重启离线练习，关闭来源须先通过活动 NoQuit 守卫。锁定时保留来源及预设但仍以生成失败结束尝试；未锁定时关闭失败来源并保存对应预设。该路径与旁路失败的“保留活动 NoQuit 尝试/允许重启时离线重建”分开。

真实宿主红测 `provider-generator-host-red.log` 出现 7 个预期失败，10.529 秒：空生成器没有发请求，没有发布新字段。初版四项宿主通过（`provider-generator-host-green-check.log`，35.904 秒）后，会话内有界决策审查（非独立审查）发现上节实现仍会提前一词取段。固定完整 addWord/真实 generator 的新增两步探针证实：消费最后余池字段时不取段，下一次前进看到空池才取段（`provider-generator-tail-transition-source.log`）。对应原生红测出现 1 个失败，0.652 秒（`provider-generator-tail-transition-red.log`）。现在由实际逐词前进入口记录需求，接纳响应后清除；不再通过“前进后池已空”的派生值直接触发。异步返回期间的回退不凭空产生新请求；没有因活动索引回退重新检查未来窗口而丢弃已发请求的字段。

修正需求时序后的中间验证 `provider-generator-forward-demand-check.log` 有 3 个失败：有限预算已加载但仍在余池中时，消费入口被错误停止。现保留“有余池就继续逐词发布”条件，末词、下划线和真实宿主对应断言通过；没有放宽这些断言。既有旁路宿主由一次批量输入直接到达低于 20 词边界，避免把错误的“131 词后仍不生成”冻结为预期；新的独立宿主明确覆盖首字符不取段、消费最后余池字段不取段、下一次前进取段、在途单飞、单字段发布及随后余池消费。批量输入经 SwiftUI 合并 count-change 的行为不等于固定网页逐按键/并发导航完整等价。

还保留两次扩大序列失败：`provider-generator-host-regression.log` 109 项/1 个 Pace 断言失败（158.073 秒），`provider-generator-forward-demand-regression.log` 110 项/同一个 Pace 断言失败（169.530 秒）。该用例单独复查通过，不据此称其已修复。定位发现宿主主光标检查会显式调用真实 presenter，最终 Pace 检查却只依赖不可见窗口 timer 是否已交付。现在确认真实 presenter 存在，再按既有主光标测试方式实际采样 Pace，保留原来的标记可见性/当前设置断言。没有改产品 Pace 实现、跳过用例或增加盲等待；这不是首帧、计时漂移或设备性能修复。

最终 `provider-generator-native-final-regression.log` **171 项、0 失败、无跳过**，175.651 秒（总墙钟 175.670 秒）：24 项在线宿主、7 项生成器、19 项 PB、28 项百科传输/会话、字段目录/会话，以及中文实时提交、无空格 unit、普通 unit 统计、延迟代码输入、生成排序和 NoQuit。来源源码探针及原创边界通过（`provider-generator-native-originality.log`）。输入路径使用真实不可见宿主/原生输入对象；删除测试调用生产输入回调，不冒充实体按键或系统 IME。零 Typebar 主程序启动，无迁移或新服务端点。

上节“异步宿主未接线”是历史状态，本节已更新，但**完整在线调度仍未对齐**：旁路阈值仍计入未发布池；有效旁路段仍先排空旧池再追加段，未按参考先段后取一个旧词；旁路 false/undefined 分类及空段同调用再次取词未完整实现。全部修饰器、网络并发/等待末词导航、真实 HTTP、实体 IME/视觉/Release 性能及新完整冻结门禁仍待验；旧冻结门禁不覆盖本增量。目标保持进行中，不把 171 项定向通过解释为全部功能已重写。

## 独立生成器需求与单字段接纳：会话层实现（2026-10-12）

依据下一节固定源码探针，TypingSession 新增独立 `needsLiveContentGeneration` 和 `acceptGeneratedLiveContent`，不复用少于 20 词的旁路需求作为生成器需求。已有词前进、来源有效、尚未结束、剩余池为空、有限目标尚未发布完且已发布未来窗口不超过配置边界时，才允许接纳生成器响应。响应在同次变换中保留整段字段，只发布第一个字段；之后由已有逐词入口消费余池，不重新变换/采样。有限预算裁剪和最后字段无提交符保持，非最终普通段末字段补提交空格；内部 LF、分解重音及下划线字段有测试。新段同时进入既有不可变重复历史。

本轮行为测试证据分开记录：新 API 最初不存在，`provider-generator-demand-api-red.log` 是编译失败，**不是运行时红测**。首轮 4 项组件验证通过后，有界会话内决策复核（非独立审查）发现首词部分输入也会误产生需求；新增回归在初版实际出现三处断言失败，0.773 秒（`provider-generator-partial-input-red.log`）。现在要求至少一次词前进，该回归通过。补充下划线提交/有限完成及余池存在时拒绝第二段响应。

最终 `provider-generator-demand-engine-regression.log` 共 84 项、0 失败、无跳过，100.589 秒（总墙钟 100.599 秒）：新入口 6 项、在线宿主 18 项、百科传输/会话 28 项、来源字段目录 12 项、来源字段会话 16 项及 NoQuit 4 项。原创边界通过（`provider-generator-demand-engine-originality.log`）。测试和审计使用不可见宿主，零 Typebar 主程序启动；没有存储迁移、新端点或服务变更。

**异步生产宿主尚未接入新入口。** 既有 `appendLiveContent` 旁路调用保持旧行为；本节不代表网络生成调度差异已经消除。下一步需在真实词前进时选择生成器请求，沿用单飞/请求身份/配置/取消守卫，并在返回时只接纳一个字段；不能让删除回退或仅首字符输入触发请求。成功空段须走生成失败而非旁路等待；nil 的生成失败与活动 NoQuit 旁路失败须分开，false/undefined 的旁路分类仍需继续实现。首段工厂、全部修饰器/语言变换、真实网络/IME/视觉/性能及完整门禁仍待验证；上一轮完整冻结证据不覆盖本增量，目标保持进行中。

## 生成器耗尽时的独立取段需求补证（2026-10-12）

新增六项固定完整 addWord、真实 words-generator/funbox-functions/词存储探针（`provider-generator-demand-source.log`）：活动索引为 0、已发布 100 或 101 个字段而 currentSection 为空时，仍取段一次；有效两词响应只发布第一个字段，第二个留在生成器池。已发布 102 个字段时超过未来词边界，不取段也不追加。100 字段时成功空段派发 word generation error，不请求关闭来源；false/undefined 均请求关闭来源并派发生成失败，不请求 restart。三个失败场景均没有追加字段或重取。

提供者响应、UI、活动索引、通知和配置边界是自有适配；此组 toggle 为记录器，仅证明关闭请求，**不证明真实 setter 会允许关闭活动 NoQuit 来源**。既有真实 NoQuit setter/restart 守卫及后续恢复探针在同次执行仍通过。未执行完整导航模块、真实 HTTP 或设备输入；没有以本组证据宣称这些边界等价。

这确认下一项原生修正必须区分生成器取段与少于 20 个已发布目标时的旁路续取。当前 `needsLiveContentPrefetch` 仍按已加载总数（含未发布池）计数；`appendLiveContent` 仍先排空旧池再追加整段；仅调整 20 词阈值不足以对齐实际词序及失败处理。应先为无剩余池的逐词生成建立独立需求/响应入口，再分别处理正常段、空段及 false/undefined，保留请求身份、取消、输入所有者、有限预算与重复历史；这些原生修改本轮尚未实现。

本轮是探索性行为证据增强，没有人为改坏产品制造红测。六项新增及原有排序/弱词/完整 addWord/NoQuit 守卫探针全部通过；`zsh -n` 与原创边界通过（`provider-generator-demand-originality.log`）。探针现接入完整 readiness 的独立日志阶段；只验证了该阶段命令与脚本语法，未重新运行全门禁，上一节冻结验收不覆盖此次门禁脚本改动。零 Typebar 主程序启动，目标保持进行中。

## 结果容器修复后的完整冻结门禁通过（2026-10-12）

冻结提交 `abaa01a31b686068958fe2fc5461d3a5b3f4cf52`，参考仍为固定只读 `91bd24bb8513785c7364cbea29296ff7adafac41`。`work/frozen-readiness-result-container.Rl3Bob` 保存冻结提交、866 个跟踪文件的 SHA-256 清单、75 份阶段日志和终态检查；`result.txt` 为 `gate_exit=0 hash_exit=0`，866 项终态哈希全部一致。显式使用 QA Redis 6.2.6、默认临时目录；测试、构建和审计期间未修改源码。

- 客户端全部 4,368 项、0 失败、无跳过，1,975.047 秒（总墙钟 1,975.553 秒）。其中在线宿主 18 项通过后，PB 台账 19 项也通过；原来的完整序列存储崩溃没有重现。全部组合输入宿主 42 项通过，946.093 秒（总墙钟 946.099 秒）；十万词耐久通过，156.662 秒。
- 自托管服务端全部 501 项、0 失败、无跳过，11.075 秒（总墙钟 11.134 秒）。
- Release 优化构建 429.70 秒；未打开应用包的严格签名、第三方许可证、资源边界与固定参考原创性检查通过。门禁没有启动 Typebar 主程序，全过程零主程序实例。

日志缓冲期间始终核实同一会话及测试/编译进程，没有以观察超时重启。一次只读 `/usr/bin/sample` 未及时产出报告，已停止并确认仅该自有辅助进程退出；原测试未中断。随后日志继续刷新且最终通过，不能把这次采样无输出解释为卡死或任何具体栈结论。

本节更新下述历史记录中“完整门禁尚待重跑”的状态，不撤销原失败证据。通过仅覆盖当前冻结实现及已有验收范围，**不是原版全功能等价或最终发布就绪证明**：旁路续取与生成器取词的调度、false/undefined 分类、空段同调用重取、所有实体 IME/字体/视觉、真实 Release 首键及计时性能、精确主题及其他人工验收仍开放；结果呈现是否及时释放及所有支持系统的生命周期也未由“不再崩溃”证明。目标保持进行中，下一步继续对齐实际在线生成流程，不缩小为当前通过的子集。

## 结果呈现的数据容器所有权修复（2026-10-12）

下述旧崩溃记录保留为历史证据。本轮最小复现及扩大序列已通过，完整门禁仍须重新执行，不能据此宣布发布就绪或功能等价。

临时指针追踪将崩溃接收者定位到 `testEmptySectionAtExhaustedTargetsFailsWithoutDisablingSource` 的旧 ModelContext，而非随后写入的 PB 上下文（`provider-storage-context-identity-probe.log`）。本机已安装框架的离线反汇编及公开 getter 分派入口、ModelContext 虚表对应关系确认触发点为 `ModelContext.container`：强容器槽为空，弱容器加载也为空时触发断点。未把最近导出符号猜测作为该结论依据；诊断工具和地址不进入产品。

窗口边界诊断发现失败结果生成了不可见的 `SheetPresentationWindow`，但它尚未出现在根窗口的 attachedSheet/sheets/childWindows 中；替换根内容及关闭根窗口后呈现内容仍存在。因此不能仅根据旧原生输入已拆除，就认定查询页面的所有呈现所有者都已退出。单个失败结果宿主接独立 PB 保存即可 signal 5（`provider-storage-exhausted-result-minimal-red.log`）；新增持久回归在原实现也发生同样崩溃（`provider-result-presentation-retirement-red.log`）。

撤回的无效尝试：仅关闭本次新建的结果窗口、清空其 contentView 并保持容器到 teardown 结束，仍崩溃（`provider-result-presentation-retirement-green.log`，文件名不代表通过）；父页面 onDisappear 清空 completedResult 仍崩溃（`provider-result-binding-disappearance-check.log`）。NotificationCenter.debugDescription 的能力检查连自有注册观察器也不枚举，因此空输出不能证明没有观察器。没有保留这些诊断、窗口扫描清理或猜测性产品改动。

实际修复在结果 sheet 内容上显式应用父页面的 ModelContainer，使呈现内容存活期间持有对应容器；不隐藏失败结果，不使用全局容器缓存，不改变成绩保存或 NoQuit 行为。回归断言失败结果确实创建了新的呈现内容，随后退役练习宿主并向另一份存储实际保存；另设已有窗口哨兵，验证宿主清理没有关闭或替换无关窗口。teardown 显式保留本次容器直到根内容拆除结束。

验证：`provider-result-explicit-container-check.log` 最小 3 项通过，15.427 秒（总墙钟 15.429 秒）。最终命名和注释后的 `provider-result-container-ownership-regression.log` 共 42 项、0 失败、无跳过，92.202 秒（总墙钟 92.208 秒）：18 项在线宿主、19 项 PB 台账、1 项输入拆除、4 项结果终止策略。日志中的三个只读存储保存错误来自实际只读失败路径测试，相关断言通过，不据此推广任何其他错误可忽略。原创边界通过（`provider-result-container-originality.log`）；已安装 Swift 6.2.4 的 SwiftData / _SwiftData_SwiftUI 接口确认公开 container getter 和 modelContainer modifier 签名。

只使用不可见 XCTest 宿主，Typebar 主程序零实例。以上证明当前失败序列不再因容器失效崩溃，**没有证明呈现内容会及时释放、没有内存残留，或全部 macOS 版本生命周期正确**；这些仍需单独验证。原生在线生成调度及下述功能差异仍开放，目标保持进行中。

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
