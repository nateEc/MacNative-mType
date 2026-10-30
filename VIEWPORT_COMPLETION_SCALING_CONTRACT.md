# 全文视口完成状态的分隔符查询开销

起点 13cf54f04206b107a918277a90b37a326625a0f5。本批检查现行 showAllLines 的真实原生生产路径，不把旧阶段文档的未接线状态当当前事实。TypebarApp 的 prepareWholePreview 已实际调用 WholePreviewViewportAdmission.check，再调用独立字段画笔；尚需完整高度后才解锁输入的边界不在本批改变。

作用范围由实际入口明确限定：usesPreparedPromptViewport 为 wholePreviewViewportEnabled 或 publishedPresentation 存在；普通未启用的原生入口仍保留完整呈现。本批没有改默认开关，也不把未走该准入的页面计入收益。新十万词测试实际调用生产准入与真实画笔，不是整份 ContentView 的首屏／首键计时；扩大中的真实页面测试承担其相应行为证据范围。

## 发现与合同

TypingSession.promptViewportCompletedIndices 原先为每个窗口构造 Set(separatorOffsets)，即使空输入也构造整个目标的分隔符集合。100,001 词、每批 32 字段的生产准入会检查 3,126 个窗口，导致这一步同时随总字段量和窗口数量增长。函数唯一生产调用者是 PromptViewportTargetDirectory.completedIndices；目录按已验证连续递增的源字段范围顺序生成分隔符下标。相同有序性已由该目录其他二分定位使用，不依赖用户输入的声明。

优化不改原文、字段数量、目标身份、计分、存储、可达滚动范围或准入门禁。空输入在原有 typed／target 数量一致检查后直接返回空集合；非空输入对实际输入目标二分查询有序分隔符，缓存本次 typedTargetIndices 读数，保留首次目标归属、已接受分隔符及最后接受位置的全部语义。没有新增跨输入缓存，因此退格／重开不会读取旧完成状态。

## 修改前的实际证据

新增 PromptViewportCompletionScalingTests，直接构造真实会话与目录，对首段和末段交替查询 200 次；检查完整字段、首末 ID 和空完成状态。另以相同真实生产画笔走完十万词准入的全部窗口，记录访问区间连续、字段数／窗口数和完整原文保持。正确输入、错误输入、内部 Return、双空格及每步退格的局部完成状态，对照独立完整 completedPromptCharacterIndices。

首次单点基线 /tmp/typebar-viewport-completion-before-20261030-driver.py/.json/.log：千词 200 次约 0.028841 秒，100,001 词约 3.055277 秒，新一项通过，driver 27.158 秒，输入保持。补充语义测试时曾将 Character 直接传给 String 接口导致编译失败（semantics-before 日志），已修正 String(character)，不计行为失败。

完整修改前 /tmp/typebar-viewport-completion-full-before-20261030-driver.py/.json/.log：新三项全部通过，真实准入 100,001 字段／3,126 窗口，67.817063 秒。该轮单点千词／十万词分别 0.039769／3.099400 秒。连既有目录共 20 项、零失败但有一项旧条件耐力测试跳过；不能称为零跳过完整成功。native 71.541 秒、driver 94.172 秒，inputs_unchanged=true。

## 修改后同范围测量

/tmp/typebar-viewport-completion-after-20261030-driver.py/.json/.log：新三项全部通过，200 次千词／十万词空输入查询分别约 0.000328／0.000187 秒；真实准入仍 100,001 字段／3,126 窗口，18.570291 秒。连既有目录为 20 项、零失败但同一旧耐力项跳过，native 19.146 秒、driver 58.527 秒，inputs_unchanged=true。

这是同机单次 Debug 路径测量，不是稳定统计、Release 指标、可见窗口帧率或首键延迟证明。准入整体约减少 72.6% 用时，其他源准备／完整高度／输入发布成本并未据此消失；showAllLines 仍部分兼容。

## 扩大验证进行中

已显式设置 TYPEBAR_ENDURANCE_TESTS=1 启动 /tmp/typebar-viewport-completion-regression-20261030-driver.py（原会话 66065，启动时 driver PID 63837、Swift PID 63851，ps 已确认存活），覆盖目录／画笔、全文准备、真实视口页面、字效及全部 146 项必需固定源码方法；结束后自动做正式来源证据检查。运行期间冻结所有非 Markdown 文件，不因日志缓冲重启。当前仅聚焦与新十万词实际路径有结果，更广回归／最终包／单次开发分支推送未完成。

同一会话续检中，旧 testHundredThousandWordDirectoryMaterializesOnlyRequestedFields 已明确 0.787 秒通过，实际 driver env 的 TYPEBAR_ENDURANCE_TESTS=1 已核对，不再凭测试名称算执行。独立重算 1,423 个非 Markdown 成员及哈希，与启动记录一致。PERF-VIEWPORT-COMPLETION-66 自动／人工追踪已登记，人工待验收；Ruby 清单结构 1,472 个唯一场景通过。包驱动 /tmp/typebar-viewport-completion-package-20261030-driver.py 仅准备，尚未启动。预先只读远端：main 8c52fb13028f82fd8e8718d55cb7ed65463b034e、开发分支 13cf54f04206b107a918277a90b37a326625a0f5，开放 PR 0，Actions 826、最新 39118939684 completed/success。完整回归终态仍待实际结果。

## 最终验证与独立渲染开关补跑

原 66065 成功终态：364 项中 363 通过、一项跳过、无失败，native 620.068 秒、driver 631.639 秒，inputs_unchanged=true。同名 .evidence.log 正式通过全部 146 项必需源码方法。跳过的是 PromptRenderPlanTests.testLargeFirstInputSeparatesProjectionAssemblyAndAppearanceCosts，另需 TYPEBAR_RENDER_ENDURANCE_TESTS=1；不能把 TYPEBAR_ENDURANCE_TESTS=1 当作所有专项均开启。

先串行包检查 /tmp/typebar-viewport-completion-package-20261030-driver.py/.json/.log：退出 0、42.930 秒、inputs_unchanged=true，Debug 严格签名、41 份 txt 逐字节比较、固定参考原创性边界通过，无主应用启动。脚本删除临时包，日志临时路径不是安装交付物。

包终态后，/tmp/typebar-viewport-completion-render-endurance-20261030-driver.py/.json/.log 用实际记录的 TYPEBAR_RENDER_ENDURANCE_TESTS=1 只补该一项：通过、无跳过，native 36.448 秒、driver 39.696 秒、inputs_unchanged=true。100,001 词全量渲染的原文、完整字格范围及首字属性修补断言均执行；该完整路径测量不是分段准入收益。没有重跑已通过的整批，也没有并行原生任务。

按实际 XCTest 方法名合并两份日志，363 项通过加原跳过项一次通过，共 364 个唯一方法均执行成功；跳过集合与补跑通过集合完全相同。/tmp/typebar-viewport-completion-combined-evidence-20261030.json 保存合并校验。扩大、包及补跑的非 Markdown 工作输入逐项完全一致，期间只有追踪文档更新。1,472 项人工清单仍是结构证明而非实体操作完成，整体 goal 保持 active；完成此实质批次后仅一次开发分支推送，不改 main／通知／工作流或创建 PR。
