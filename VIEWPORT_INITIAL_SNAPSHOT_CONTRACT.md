# 全文准备的重复快照与逐窗口全量光标查询

起点 001504fbaea501dffc446ac2fbe37fbcc8d68d00。上一批只证明准入计算更快；本批比较实际 ContentView 两条入口，不将 18.6 秒画笔准入当作整页首键收益。普通原生入口默认 false、完整配置或显式 true 的分段入口及所有回退条件保持不变，不切换默认入口。

## 实际页面反例

新增 ViewportPracticeHostTests.testHundredThousandWordDefaultAndViewportPublishCompleteInputAndCaret，TYPEBAR_ENDURANCE_TESTS=1 明确开启。两条路径使用相同自有 oak 原文、100,001 字段、隔离 UserDefaults、内存 SwiftData 和未显示窗口。先等待完整页面高度／全文辅助功能／输入准入，再验证两次真实输入回调、首字属性变化、正确目标光标、No Quit 状态和输入控件身份。准备超时 180 秒是明确失败，不能把被锁住的回调耗时算作首键性能；后续等待不延长该准备预算。

/tmp/typebar-viewport-host-comparison-20261030-driver.py/.json/.log 原实现：完整入口约 25.496 秒就绪，两次输入回调 0.127／0.132 秒、目标呈现检查 0.773／0.738 秒，通过。分段入口 180 秒仍未完成，仅测得 47,392／100,001 字段，输入被锁，主字段高度仍 1 点；原测试继续输入导致连带断言，共 9 处失败。native 329.596 秒、driver 353.273 秒、输入保持。现在准备失败后立即返回，不再让后续失败掩盖主因。同步渲染计数也细分目标长度，只检查是否渲染了这份大目标，不把启动占位的小目标调用误报为重复大呈现。

小型独立反例 PromptViewportUnchangedSnapshotTests.testUnrelatedParentRefreshPreservesFullyMeasuredPrefixAndReadiness：257 字段先实际完成，仅改变父页标签三次，原生控件身份不变，但前缀退回 32／64 字段、就绪撤销。/tmp/typebar-viewport-unchanged-snapshot-red-20261030.log 一项六处失败，native 1.450 秒、driver 25.391 秒，输入保持。

## 两项修复及边界

1. TypingSession.canReuseUnstartedViewportSource 只承认相同尝试、目标和配置，未开始／未完成、无输入、无拒绝输入、无退休、无缺字／提交错误且位于原始位置的状态。原生快照的样式和字体／宽度／方向度量也须相同，才保留当前测量；仍更新光标配置及快照所有者。输入开始、清空后再更新、配置／样式／目标／度量变化继续原重建，未引入跨尝试或持久化缓存。
2. PromptViewportFieldLayoutSequence 的会话不可变，但 makeWindow 原本每个 append／revisit 都调用 promptCaretGlyphIndex；该 getter 会构造全文 acceptedPromptGlyphs 再查当前字格。现在在每份序列创建时只计算一次原 getter，保留其完整光标语义；replacingSession 创建新序列时重新计算。不用 nextTargetIndex 代替复杂光标政策，也不缩小字段范围或估计页面高度。

第一项使小反例通过，字体／回退／任务相关 25 项零失败但一项旧耐力未开启，日志 /tmp/typebar-viewport-unchanged-snapshot-focused-20261030.log；不能称完整通过。独立再跑实际大页仍在 180 秒失败（comparison-verified 日志），证明重复快照不是唯一原因，没有据此宣称长文本就绪已解决。

新增单元检查覆盖输入后即便删除到空仍拒绝初始复用、新尝试拒绝复用，以及旧序列光标保留原快照、新序列采用新输入、远段窗口不能冒领当前光标。当前 /tmp/typebar-viewport-host-comparison-caret-verified-20261030-driver.py/.json/.log 共 4 项、0 失败／跳过，native 86.083 秒、driver 129.625 秒，inputs_unchanged=true。

相同十万词页面：完整入口 27.440 秒就绪，首／次输入回调 0.132／0.130 秒、目标呈现检查 0.787／0.705 秒；分段入口 55.124 秒就绪，回调 0.001437／0.001384 秒、目标呈现检查 0.730／0.720 秒。全文、所有字段、输入身份及两次状态／光标断言执行。仍为单次同机 Debug 隐藏宿主，非真实屏幕帧率；分段准备仍慢于完整入口，不能据此默认启用或声称整体更快。

## 后续门禁

已开启 TYPEBAR_ENDURANCE_TESTS=1 与 TYPEBAR_RENDER_ENDURANCE_TESTS=1 启动 /tmp/typebar-viewport-initial-snapshot-regression-20261030-driver.py，覆盖视口／画笔／全文准备及真实页面、同名字体资源更新、字效和全部 146 项固定源码必需方法，结束后正式核验来源证据。期间冻结全部非 Markdown 文件，沿原会话等待终态；尚未完成这轮扩大、最终包或推送。

实际原会话 31929，启动时 driver PID 95214、Swift PID 95228，已用 ps 确认存活。后续须从该 handle 或实际进程确认终态，不因一次观察超时或日志未刷新重复启动。

当前修复只优化未开始的重复快照和不可变序列中的光标查询。已开始后的重复快照、逐输入重建已测几何、远段滚动／IME 回退的十万词代价、更多字体／辅助功能与 Release 性能仍须后续证据。showAllLines 保持部分兼容，整个 goal active；没有显示或启动 Typebar 主应用。

## 2026-11-02 恢复后的完整重验

原 /tmp 驱动记录、日志和固定 QA 运行时已不在，实际进程清单也没有残留 Swift／XCTest。不能据旧状态文件宣称通过或继续等待一个不存在的任务。上面的前后对照为当时实际观察的历史记录，本轮门禁以新持久日志为准。

系统 Homebrew Node 因 ICU 74 动态库缺失不能运行；不修改全局安装。按照仓库工作流在 /Users/nathanshan/Documents/Codex/2026-09-01/wo/work/typebar-qa-20261102 恢复独立 Node 24.19.0、Unicode 17.0，官方归档 SHA-256 8294b7aa9b03997481c06babf1e8b270c859358f27da57a11509afe537ac381d 与官方 SHASUMS256 对上。Xcode 26.3／17C529 未变。准备脚本曾因系统 Python 3.9.6 不支持 extractall(filter=...) 失败，改用校验后官方归档的系统 tar 提取，仅为外部 QA 环境恢复，不是产品更改。

依现行工作流恢复 Zod、Anime.js、Solid 及固定源码依赖，前三者通过现有准备脚本的固定完整性验证；全部仅用于 QA，没有进入产品或参考仓库。env.json 和运行日志均在上述持久目录，不再以 /tmp 为当前验收唯一存储。

新驱动 run-initial-snapshot.py，日志 initial-snapshot-regression.log／.json／.evidence.log，原工具会话 91402，启动时 driver PID 21888、Swift PID 21902，ps 已确认存活；冻结 1,424 个非 Markdown 输入，两个耐力开关均为 1。范围为全部 146 项必需来源方法、视口／画笔／全文与真实双入口大页、字效及同名字体资源检查。不得因观察超时重开；须核对实际 handle／进程并等待终态。PERF-VIEWPORT-INITIAL-67 登记为部分完成／待实体验收；尚未取得本轮通过结果、打包或推送。

原 91402 最终成功结束：378 项、0 失败／跳过，native 760.700 秒、driver 777.553 秒，native_exit=0、evidence_exit=0、inputs_unchanged=true；持久 .evidence.log 正式确认全部 146 项必需源码方法通过。包括两个耐力开关下的新实际十万词双入口、小型重复刷新、序列光标归属、原有准备／回退／重开和同名字体检查，不是完整客户端或实体 IME 门禁完成。终态后才启动同目录 run-package.py，结果另记；未并行原生任务、未显示主应用。

本轮持久日志的实际十万词对照：完整入口 26.596 秒就绪，首／次输入回调 0.153／0.142 秒、目标呈现检查 0.983／0.792 秒；分段入口 57.133 秒就绪，回调 0.001274／0.001077 秒、目标呈现检查 0.655／0.341 秒。全部目标、就绪、两次输入、首字属性与光标断言执行；该数据再次确认初始分段仍较慢，不改默认入口、不声明真实可见帧率改善。

initial-snapshot-package.log／.json 串行检查退出 0、49.864 秒、inputs_unchanged=true：Debug 严格签名、41 份 txt 逐字节比较及固定参考原创性边界通过。没有启动主应用；临时应用由 EXIT trap 清理，不作为安装交付物。本轮所有门禁记录存放上述持久 QA 目录。人工清单 1,473 个唯一场景结构检查通过，PERF-VIEWPORT-INITIAL-67 实体验收仍待完成。

推送前只读状态：main=8c52fb13028f82fd8e8718d55cb7ed65463b034e、开发分支=001504fbaea501dffc446ac2fbe37fbcc8d68d00，开放 PR 0；Actions 仍 826 次，最新 39118939684 completed/success。仅把本批实质修复合为一次开发分支推送，不更改 main、通知或工作流，也不新建 PR；推送终态另存持久记录。
