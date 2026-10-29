# 客户端完整测试范围的本地基线

`GATE-CLIENT-BASELINE-39`，冻结起点 `1ee242d7f74be670025afa7018c106263558f7ec`。本记录不是完整重写验收通过声明。

## 冻结与范围

运行 `/tmp/typebar-client-baseline-20261029-driver.py`，记录 `/tmp/typebar-client-baseline-20261029.json`，客户端日志同前缀 `.log`。对全部 1,288 个受跟踪及非忽略、非 Markdown 文件记录 SHA-256；代码、脚本和清单在测试期间冻结。仅允许追加本类 Markdown 证据。测试默认串行，没有启动 Typebar 主程序或触发远端 Actions。

启用 `TYPEBAR_ENDURANCE_TESTS=1` 和 `TYPEBAR_RENDER_ENDURANCE_TESTS=1`，不是原先的定向正则集合。固定网站参考、Zod、完整来源依赖及 Anime／Solid／Hangul 等归档均通过已有 QA 环境提供。先串行准备 initial、before-elapsed、before-incomplete、before-local-pb、before-account-tags、current 六个历史模型写入器，只在自有临时目录生成，不打开用户数据库。

排除三个会明确显示窗口的测试，保留同类其他隐藏检查：

- `WebsiteConfigStartupHostTests/testActualCommandPaletteHandsOffToCurrentConfigurationExportSheet`
- `WebsiteConfigStartupHostTests/testSettingsExportActionPresentsLatestStoreInProductionManualCopySheet`
- `ResultSheetTerminationTests/testActualSwiftUISheetDoesNotPreventTermination`

因此即使本轮通过，也不能称所有实体窗口／结果页退出或全部客户端路径已经验收。测试自身的跳过、失败和最终退出状态仍须单独审计。

## 冻结基线终态

原 session 68355 已正常结束，退出码 1；驱动 3,113.198 秒，Swift 测试阶段墙钟 3,106.227 秒，XCTest 报告 3,101.755 秒。共 6,750 项测试、六个失败方法、11 处断言失败、零运行时跳过；三个显示窗口的显式排除仍另列，不能混同为零排除。全部 1,288 个冻结输入哈希保持不变。

`CodePoolSamplingTests.testReplayCanGenerateNewWordsAfterItsCapturedFutureAndRepeatAgain` 出现三处断言失败；`CodeSectionGenerationTests.testRepeatCopiesTargetsThenStartsFreshSectionInsteadOfOldPendingTail` 一处；`OrdinaryEntryGenerationTests.testRepeatedEntryCacheEndsAtAFreshSectionWithoutMutatingOriginalPendingTail` 一处。三者都用 words=0 夹具，却要求重复缓存耗尽后继续生成。固定源生成器只在 wordIndex < Config.words 等条件下继续，零值不满足；此前来源证据及现行 `GeneratedRepeatedWordPolicy` 已按此执行。先保留失败，等本轮终态后再统一修正并验证，不在运行中改夹具或生产策略。

`TypingVisualFocusIntegrationTests` 的两个方法各一处失败，实际是在读取源码后匹配旧属性字符串 ownsConfigurationSelection；当前生产条件改用 ownsPresentedConfigurationSelection，仍按真实视觉焦点条件移除配置面板。不能将两条字符串失配直接称作产品布局缺陷，也不能把更新字符串说成修复了实机布局。

`ViewportPracticeHostTests.testWheelOverPromptScrollsPageWithoutMovingInnerClipOrReplacingInput` 四处失败，两种 scroller 样式下页面原点均未按下／上滚轮改变。捕获的页面 bounds 起点为 153，完整提示及输入准入已就绪，overlay／legacy 宽度分别为 1000／983。该项 61.521 秒包含四次有界等待超时，不能据后续连带超时猜测根因。必须在原代码下单独复现并记录原生事件与实际滚动轨迹，禁止删除用例、扩大超时或仅凭重跑通过关单。

`CustomSequentialStreamingTests.testOptionalHundredThousandWordEndurance` 通过，176.792 秒；这包含真实十万词输入、799,999 单元、冻结指标及回放检查，不等同于跨设备性能保证。六种历史声明的 `DiskModelMigrationTests` 类也已通过。故障场景的 Core Data 诊断不是 XCTest 失败计数。

日志暂时不刷新时，通过实际 session／PID 及 `/tmp/typebar-full-client-20261029-first.sample` 确认进程仍在该耐久测试内逐字输入、记录及计分；未因观察超时重启或截断。单次采样不作为性能根因结论。

为后续串行服务端基线准备了隔离的 LRU 11.5.1：`/tmp/typebar-service-baseline-deps-20261029`，仅临时 npm 前缀，禁用安装钩子，无仓库依赖变更。确认自有 QA 路径 `work/typebar-qa-runtime/redis-6.2.6/src/redis-server` 实际为 6.2.6；该目录没有 redis-cli，系统 CLI 为 8.6.1 且支持 JSON 传输。后续来源检查须显式指定 Redis 服务端路径，不能使用系统的 8.6.1 服务端。服务端测试尚未启动，不能据准备动作称已验证。

冻结基线已结束，失败基线不升级为全绿，完整 goal 继续进行。

## 复现与已确认的夹具修正

未修改生产代码的聚焦复现 `/tmp/typebar-client-baseline-ui-reproduction.log` 执行四个源码／界面方法，再现六处断言失败：两个旧属性匹配和四个滚轮断言。后续诊断均串行运行，记录实际终态和输入哈希，未在活跃原生作业期间修改非 Markdown 输入。

三个生成用例改用剩余有限预算，分别为 4、3、3；原来的缓存、继续生成、再次重复、原游标 pending tail 及 hasRemaining 断言均保留。新增零词数反例覆盖 codeSwift／arenaStrategy 与有／无 noSpaces 四种组合：缓存 bay 必须复用且不抽签，缓存耗尽后空输出、replayExhausted、hasRemaining=false，不得抽取新候选或清空原游标 elm。生产 GeneratedRepeatedWordPolicy 未改动，不能把夹具修正说成产品策略修复。

两个视觉焦点源码断言仅将旧 ownsConfigurationSelection 属性更新为生产使用的 ownsPresentedConfigurationSelection，保留配置面板结构移除及其他条件断言。不能据此宣称实体窗口布局已修复。

五个相关测试类共 66 项通过，XCTest 0.429 秒、驱动 21.031 秒、冻结输入保持不变；日志 `/tmp/typebar-client-baseline-fixture-fixes.log`。这不是完整客户端重跑。

## 滚轮仍开放：反证与边界

原 `testWheelOverPromptScrollsPageWithoutMovingInnerClipOrReplacingInput` 保留原样，未删断言、扩大超时、跳过或改动生产滚动。临时探针、打印、ObjectiveC IMP 调用及合成事件构造实验已全部撤回，ViewportPracticeHostTests.swift 恢复到冻结起点内容。

| 诊断 | 实际观察／限制 |
| --- | --- |
| wheel-probe | 完整提示、输入准入及高度均就绪，两种样式原点 153；下／上事件即时及等待后均不移动。手动 clip +40 可跨五次布局保持，不能称发生了布局后回弹。 |
| bare-wheel-probe | 普通 AppKit 隐藏窗口的 coarse CGEvent 缺少窗口字段时不移动；补公开 CG 窗口字段后可移动。pixel 则可移动。该负对照探针自身有一处预期失败，不是产品通过证据。 |
| wheel-associated／wheel-position | 补 CG 窗口字段、实际提示区域坐标后，原界面用例仍四处失败；这些字段不是充分修复。 |
| wheel-cocoa-window | 由公开 NSEvent.mouseEvent 窗口种子转 CG scrollWheel，确实得到正确 Cocoa windowNumber／window，原四处断言仍失败。不能继续将根因称为缺少 Cocoa 窗口关联。 |
| framework-wheel-nonedge／framework-wheel-dispatch | 将实际 SwiftUI.HostingScrollView 原点设为 300，排除边界；line／pixel，直接父级／内层转发／直接 AppKit 实现／原 CG 桥接／window.sendEvent 均不移动。原生视图身份及父子关系未变，documentRect 高度 1838、clip 高度 720、scroller enabled。探针无业务断言，仅用于缩小故障范围，零失败不代表滚轮通过。 |
| framework-wheel-visible | 确认无运行中主程序后，单个隔离窗口 orderFront 对照约三秒后关闭；同样不移动，排除“仅隐藏窗口”猜测。该临时探针末尾旧 isVisible=false 断言按预期失败，不能当功能回归或通过；defer 已关闭窗口，无遗留 Typebar 主程序。 |

上述文件均位于 `/tmp/typebar-client-<诊断名>.log`，其中首个为 `/tmp/typebar-client-wheel-probe.log`。公开字段／转换契约依据本机 MacOSX26.2.sdk 的 CGEventTypes.h、NSEvent.h；未引入私有窗口字段或运行时实现替换。实际物理鼠标／触控板路径尚未验证，不把合成事件故障直接外推为真实硬件失效。父级启用状态和公开事件信息尚不能解释不移动的原因，需继续定位 AppKit／SwiftUI 滚动边界。

进一步在仓库外制作 `/tmp/typebar-minimal-wheel-boundary.swift` 及 flipped-control／responsive-control 变体，分别以普通 NSView、反向坐标 NSView、NSHostingView 文档和最小 SwiftUI.ScrollView 对照，均只用一个隐藏窗口逐个关闭，不含 Typebar 业务代码。普通文档在派发时同步移动，两个 hosting 形态首次未移动，后续出现派发后 RunLoop 才移动；在未包含 responsive 子类的 flipped-control 脚本中连续三个独立进程均可复现后者。反向坐标普通文档能正常移动，直接 adjustScroll 也保留提出的目标，不能把 flipped 坐标或该公开调整方法称为根因。responsive-control 子类的对照也有异步移动，**不能将其中一次成功归因于关闭 responsive scrolling**。

对应 `.log` 与 `/tmp/typebar-minimal-wheel-repeat-{1,2,3}.log` 保留；这些探针只是观测，未作为正式通过用例提交，也不能证明 Typebar 生产父级在相同事件下已恢复。现有根因判断仍不充分，原滚轮失败继续开放；下一步应区分合成事件的目标元数据与 hosting 异步处理条件，而不是将最小页面一次重跑成功当修复。

## 修正后的扩大检查

`/tmp/typebar-client-baseline-source-regression.log`：261 项通过、零失败、零运行时跳过；XCTest 355.624 秒，驱动 366.632 秒，全部非 Markdown 输入哈希未变。范围包括全部 145 项必需来源方法、上述五个测试类、生成缓存／前瞻／活动设置、视觉焦点状态、页面滚轮转发及三个隐藏阅读位置用例。`check-source-qa-evidence.py` 对该完整日志给出 145 required tests 通过；它验证已执行的方法状态，不证明比较本身充分或全部功能等价。

这不是 6,750 项完整客户端重跑，原滚轮故障未纳入这个绿色定向集合，也没有因此关闭。原冻结全量失败与三个显示窗口排除仍有效。客户端生产代码、资源、清单及构建脚本都未变，本批不额外重复应用打包或启动主程序。

## 服务端完整基线

`/tmp/typebar-service-baseline-20261029.log`：501 项通过、零失败、零运行时跳过，XCTest 11.299 秒；含依赖编译的驱动总耗时 296.295 秒，全部非 Markdown 输入哈希未变。该作业在客户端及最小页面探针均退出后才启动，无并行原生作业。

显式提供自有 Redis 6.2.6 服务端、支持 JSON 的系统 Redis CLI 8.6.1 及隔离 LRU 11.5.1 来源依赖。来源 Redis 使用测试拥有的临时 Unix socket；邮件来源检查使用测试计数适配器，没有向用户发送邮件。这个本地结果不代表部署服务、用户账户数据或远端 Actions 已验收。

原创性 self-test 及固定参考重叠扫描均通过。客户端完整基线仍红；主分支和 CI 触发条件不因这些未解决项改变，也不重新推送主分支试探远端门禁。本批仅安排一次开发分支推送，推送前复核无打开 PR，推送后核对远端提交及 Actions 总数。
