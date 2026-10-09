# 组合显示投影与完整固定源码证据

固定只读参考 `91bd24bb8513785c7364cbea29296ff7adafac41`；独立 Swift 实现，不复制原版产品代码或资产。本增量是组合显示重写的模型／证据阶段，**尚未替换生产渲染**，不声称已修复实际 IME 界面。完整 goal active。

## 原版行为与现有缺口

读取完整 `frontend/src/ts/test/test-ui.ts` 的 `updateWordLetters`、`test/caret.ts`、`input/listeners/composition.ts` 和 CSS dead 样式。普通活动词中，组合串占据多个目标槽；off／below 显示对应目标文字，replace 显示候选（普通空格为下划线）。超出词尾的候选仍属于该活动词，后续目标不重复。marked 槽独立下划线且逐槽匹配正确色；Zen 始终显示候选，组合存在时不保留空词占位。主光标跟随整段候选，不等于接受输入或推进 pace。原版 below 的另行候选 UI、实际排版与调度不由本探针证明。

现有 `ContentView.renderedPrompt(for:)` 仍只在 `index == caretIndex` 时把整个组合串塞进一个字形，后面目标未按候选长度消耗；主光标仍读会话 canonical caret。直接把显示字符串变长无法同时修复普通、Tape、ASL 与 Choo 的词身份／几何／滚动。这是已核实的生产缺口，不把本次模型当作已接线。

配置盘点因此将 `compositionDisplay` 从已映射更正为部分，生成器、生成 JSON 及分区测试同步变为 94 项中的 89 映射／4 部分／1 不适用。原 `tapeMode` 行关于普通 LF／Zen 仍未接线的陈旧描述依据此前已提交合同纠正，仍为部分；没有新增配置或提升状态。

## 原生模型与 Unicode 边界

`PromptCompositionPlan` 只接收一个活动词的 target／input／composition 和显示模式，输出未提交尾部 cells、目标相对身份、组合身份、逐格匹配、消耗目标范围、空 Zen 占位及 target／afterComposition／afterInput 三类 caret 锚点。词尾候选没有伪造下一词 target ID，caret 在候选末端也不借用无关目标。输入、计分、计时、归档与服务协议不改动。实际颜色、控制符结构行、hint 和跨呈现几何仍由下一阶段适配。

原生 target ID 是完整 grapheme；模型保留该坐标，同时单独保存原版 `input.utf16.count + composition.utf16.count` 坐标。固定源的普通候选按 UTF-16 下标迭代、目标按 code point 分割，Zen 候选按 code point 迭代，而 caret 始终按 UTF-16：例如普通 😀 候选产生两个孤立 surrogate 槽；Zen 一个 emoji 槽的 caret 索引仍加二。探针保留这些原始单位，测试明确承认差异，不能把 132 组常规相同扩展为所有 Unicode 等价。是否及如何在实际 renderer 适配这些源坐标尚未完成；不改变既有原始单位输入／计分／回放来迎合显示。

## 完整源码对照与行为证据

QA-only `Scripts/check-source-composition-projection.mjs` 从干净固定 checkout 读取完整 word-update span、完整 caret 模块及真实 Words／Strings，执行 132 组 off／below／replace、普通／Zen、空／取消、错误前缀、溢出、空间／Tab／Return、中文／RTL 案例，以及 36 组显式 Unicode 案例（含预组合／分解重音互换）。DOM／RAF 与 caret 几何是明确自有适配，不执行真实浏览器布局、完整输入监听器或系统 IME；不复制网页字体／资产，也不进入产品运行时。探针已接入完整门禁。

九项 `PromptCompositionPlanTests` 覆盖跨度／身份、三种模式、词尾溢出、控制字符、Zen 空占位、取消、完整 grapheme／RTL 及严格原始字符身份；其中实际 `TypingInputView.setMarkedText` 多次更新、取消及随后接受输入证明组合不被误提交。两项 `CompositionProjectionSourceTests` 直接对照 132 组完整源输出及 caret，另对 Unicode 原始单位／原生差异作明确断言。并非完整 ContentView、实体键盘或全呈现证明。

先写模型测试时 `/tmp/typebar-composition-plan-initial.log` 因类型尚未实现编译失败，不称为生产行为红测。首个七项模型测试通过，日志 `plan-first.log`（0.002 秒）。`plan-regression.log` 因新缓存未隔离触发 Swift 6 编译检查；与既有对照测试一致改为 MainActor，不关闭并发检查，`plan-verified-regression.log` 33 项零失败零跳过（0.545 秒）。最终 `plan-final-regression.log` 94 项零失败零跳过（3.440 秒），含十项新增及相关光标／Tape／ASL；本段简写文件均为 `/tmp/typebar-composition-` 前缀。

首次分类测试筛选名错误跑零项，保留 `/tmp/typebar-composition-classification-red.log`，不计成功；准确筛选 `classification-behavior-red.log` 一项四个预期失败（0.617 秒），旧矩阵确实仍错误声称映射。修正唯一表格源并正常生成 fixture 后，`classification-green.log` 一项通过（0.008 秒），元数据重生成无漂移。

同会话有界决策／风险复核（非独立审计）检查词尾候选误跨词、Zen 空占位、控制结构、UTF-16／scalar 混用及取消／接受边界。模型不解决真实 session 词字段到 canonical ID 的映射，也不冒称普通／Tape／ASL／Choo 接线；这些是必须继续的工作，不缩减完整重写范围。工具链为 Swift 6.2.4／macOS SDK 26.2、最低 macOS 14，QA Node 22.22.1；本轮零 Typebar 主程序启动。

第二轮有界复核发现 Swift Character 默认 canonical equivalence 会把预组合／分解重音误判正确，与既有 `InputTextIdentity` 原始身份及固定源码都不同。首轮十四文件冻结在 `/tmp/typebar-composition-final-frozen.sha256`，中途仍逐项一致；明确确认自有门禁 84550 → swift-test 98715 → xctest 98856 后仅向该测试进程发送 INT，门禁 session 90580 终态退出 1，随后确认无残留才改文件。不计作成功，服务／包未运行；`/tmp/typebar-composition-final-readiness.log` 保留中止状态，终态后从确认属于该轮的 `typebar-native-rewrite-readiness.V2GgRh` 临时目录以不覆盖方式保留 72 日志至 `/tmp/typebar-composition-final-logs.IbuULK`。

`/tmp/typebar-composition-identity-red.log` 一项两处预期失败（0.607 秒），改为复用既有严格 `InputTextIdentity.matches` 后 `identity-green-regression.log` 96 项零失败零跳过（3.372 秒）。扩充源夹具后 `expanded-source-regression.log` 十一新增项零失败零跳过（0.550 秒）。不把新模型的规范等价误色留给生产接线解决，也不改变 Unicode 原始输入或计分政策。

## 下一阶段与冻结验收

下一阶段必须从会话的真实活动字段建立全局 ID 映射，统一所有呈现分支的候选 cells 与 after 锚点，保留主／pace 独立、词归属、连续控制结构、退休／回删／重建和新尝试取消；随后完成真实系统 IME／模式／设备验证。不能只让普通 Text 看起来正确，或把重复 offsets 当作多槽字形。字体／主题资源、性能、任意队列及其他功能缺口仍开放。

最终重新冻结十四文件于 `/tmp/typebar-composition-verified-frozen.sha256`；启动前、中途及门禁终态均逐项一致。唯一重新运行门禁 session 10912 最终退出 0，主日志 `/tmp/typebar-composition-verified-readiness.log`；前述中止轮不计成功。原生 3,970 项零失败零跳过（890.671 秒，All tests 墙钟 891.103 秒），服务 501 项零失败零跳过（11.435 秒，墙钟 11.492 秒）；十一新增分别为模型九项 0.002 秒、完整源码对照两项 0.490 秒。十万词耐久 152.114 秒、十六磁盘迁移 4.669 秒通过，耗时不作为优化结论。

最终门禁同时通过元数据再生成无漂移、53 表面、1,130 唯一人工场景结构、94 配置分区 89／4／1、固定完整源码探针、未启动应用包的构建／签名／资源与原创性边界检查。结构审计通过不等于 1,130 场景人工执行。保留 74 日志于 `/tmp/typebar-composition-verified-logs.CAKu7v`，210 既有组件图于 `/tmp/typebar-composition-verified-images.xkJLGp`；本轮查看 `ordinary-tape-corrected-return.png` 和 `zen-tape-rtl-emoji.png`，仅作现有组件输出复查，非新组合模型接线或系统 IME 的图像证据。日志中的 CoreData 故障夹具及系统诊断保留，不把 XCTest 后独立 Swift Testing 的零项摘要误当完整套件结果。

终态再次确认固定参考 pin 未变且干净，无 Typebar 主程序、门禁、编译器或测试进程残留；本轮零主程序启动。第三次同会话有界风险复核（非独立审计）检查严格字符身份、词尾溢出、双坐标、源探针适配边界与部分分类，没有发现需再次改动的代码问题。终态后仅本合同及 README／规范／功能盘点补充验证结果，其余十个冻结输入保持一致。只证明模型与有界源码证据，不宣称生产组合功能完成；四呈现接线与实际 IME 继续开放，goal 保持 active。
