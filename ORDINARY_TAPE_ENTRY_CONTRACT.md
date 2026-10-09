# 普通多行 Tape 生产入口与高度所有权

## 投影实测推进距离增量（2026-10-10）

推进槽接口新增 inlineAdvance：按实际槽 ID 的 allocation 宽度顺序求和，不以 canonical offsets 或墨迹并集代替；hidesExtras 跳过 .extra，下一槽明确为零宽时扣除最近正宽，缺失下一槽不误判为零宽。直接复核固定参考 test-ui.ts 的完整 scrollTape 当前词宽计算段；调用者仍须提供真实下一槽以及 blind／hideExtra 设置，字段前缀、方向和退休补偿不在此函数中。

两新增测试包含真实 PromptFieldTextLayout 测得的 emoji／虚拟候选槽宽，以及受控隐藏 extra／零宽／缺失下一槽边界。`../../work/tape-measured-advance-red.log` 保留初始红灯（缺接口及错误测试枚举类型）；修正测试类型后的 `tape-measured-advance-red-verified.log` 仍因缺接口失败。最终 `tape-measured-advance-verified.log` 34 项零失败零跳过（3.578 秒，墙钟 3.583 秒），参考与动画归档环境齐备。行为先行及差异风险复核约束本增量；真实量测不是浏览器像素等价，受控框不代表全部字体和连接塑形验收。

尚未接入 TapePromptNativeView，也未解除生产组合投影保护；这不是可见功能完成。完整门禁未重跑，无新图、零主程序启动；词容器几何、候选主／pace、结构行与队列组合仍开放，goal active、兼容分类不升级。

## 投影推进槽接口增量（2026-10-10）

新增 TapePromptProjection.advanceCells：从活动原始字段的 inputUTF16.count 选择最终 fieldRuns 中非提交 gap 的前缀，保留独立槽 ID 与属性，不用候选主光标终点或拼接字符串字符偏移。off／word／无 map／空输入返回空前缀。固定 scrollTape 对应行为为以 input.length 遍历实际 letter 节点，因此一个已提交 emoji 的两个 UTF-16 单位可能选择一个额外候选槽；这项源混合单位行为不擅自改为 grapheme 计数。隐藏 extra 和下一槽零宽回退仍由待接几何层处理。

证据 `../../work/tape-advance-cells.CjtdUn/`：红灯 `../tape-advance-red.log` 为新接口不存在；focused.log 四项一处失败，夹具目标有可复用 canonical ID，无法满足虚拟槽断言，改为目标末尾的真实候选溢出。broad.log 32 项零失败但缺参考环境而跳过一项，不计完整成功；补齐固定参考与归档后的 verified.log 最终 32 项零失败零跳过（3.585 秒，墙钟 3.589 秒）。四新增检查接受前缀／候选终点分离、UTF-16 与真实虚拟槽、空输入及活动字段归属。行为先行和差异风险复核约束本次接口；无持久化、输入、计分或时钟改动。

这是原生几何适配的前置接口，尚未接到 TapePromptNativeView；生产 Tape 组合投影保护仍保留，不能计作可见功能完成。完整门禁未重跑、无新图、零 Typebar 主程序启动。实际候选槽布局、隐藏 extra／零宽补偿、pace 别名、退休队列、方向与实机 IME 仍待验，兼容分类不升级、goal active。

## Tape 事件快照锚点证据（2026-10-10）

下一步组合投影适配前先核对固定参考的真实事件 getter／logger／helpers。既有完整 scrollTape／Caret／RAF 探针不再用 getCurrentInput 替身，而由真实 input 快照提供推进长度；六类 composition 更新（含 emoji、组合符、控制字符、清空和中文）不改变快照，切活动字段后无新 input 返回空。480 个已提交快照共 2,880 次候选隔离断言通过，128 普通、32 前缀退休和 28 方向例的输出 JSON 与改动前逐字节相同。

证据 `../../work/tape-event-anchor.lQ5PzM/`：before／after 为初始替换对照；verified.log 保留计数预期误算 3,072 的失败，按实际循环 480×6 修正为 2,880；final.json 与 before.json 的 cmp 通过。native.log 中 TapePromptPresentationTests 17 项零失败（3.555 秒，墙钟 3.558 秒），含完整固定源横向通道对照，参考环境齐备、没有跳过。源码仅 QA 动态读取，不复制进原生产品。

本次为减少实现不确定性的源码探针增量，不改产品行为，未做产品红灯测试。使用源码驱动与行为先行技能，差异风险复核未见新增产品路径；候选事件虽保持为最后更新，DOM 仍是受控的三字母框，未执行真实候选排版、系统 IME 或事件控制器。原生 Tape 组合投影仍未接通：必须分开已提交推进锚点与候选主光标，不可直接以候选终点替代 Tape advance。完整门禁本轮未重跑；零主程序启动，无新增截图，兼容分类不升级、goal active。

本轮解除普通目标含换行时的 Tape 生产回退，复用既有 SwiftUI／AppKit 词框，不复制 Monkeytype 产品代码、字体或资产。固定只读参考仍为 `91bd24bb8513785c7364cbea29296ff7adafac41`。这是完整原生重写的一个增量，不是功能等价完成声明。

## 行为与源码依据

生产 `ContentView` 与实际挂载测试共用 `TapePracticePrompt(session:...)`。目标初始声明换行时，从尚未生成 Return 的引语首词起就预留三个原生实测行高；Zen 仍为两行。引语初始控制字符能力与后来生成的文本拓扑分开：messagingStyle 后来生成 LF、初始能力仍为 false 时，按已生成词框自然高度呈现，四行不误截成三行，也不因此准入 Return。普通无换行仍单行。

固定源 `frontend/src/ts/test/test-ui.ts` 完整 `updateWordsWrapperHeight` 的普通 Tape 分支，声明换行选三行，否则选实际 words 高度／当前词高度；raw showAllLines、计时／无限、自定义、force、页面／结果／缺失活动词仍有各自门禁。`test-logic.ts` 初次生成保存控制字符能力，`input/handlers/before-insert-text.ts` 按该能力准入；未修改原生对应输入能力。QA 探针执行完整固定函数的 768 组自有测量，并以 24 组有效夹具对照挂载组件的三行比例。CSSOM 是受控边界，不宣称浏览器排版或字体像素等价。

Tape 自己拥有高度和滚动，不能再嵌入生产父层的独立 184 点 `PracticePromptViewport`。抽取并共用 `PracticeLineDisplayPolicy.needsOuterViewport`，普通非 Tape／ASL／Choo 保留原外层，Tape 直接呈现；16 组策略组合及实际挂载的无 NSScrollView 检查覆盖该边界。静态生产路由断言加共用策略／初始化器挂载，不等于完整 ContentView 运行期或实体键盘证明。

完整固定 `test/test-words.ts`、`utils/strings.ts` 与 `buildWordHTML` 的八组实际建词证明：末尾分隔符不会另生成未来空词。原生导航的 target.count 空尾仅在未物化 future、无字形／Return／缺口且非隐藏边界时过滤；真正的中间空词、活动空词、连续 Return 空行及隐藏边界空目标保留。隐藏边界直接复用会话既有事实，不根据语言或当前修饰器猜测；`TypingEngine` 只提取同一呈现条件，无输入接受、计分、持久化或服务协议改动。

真实会话挂载覆盖 word／letter、四种模式短题、引语按需生成、错误 Return replacement 与纠正、连续退休及完整成绩／可移植记录／回放、RTL／emoji／组合字符、字号、狭窄独立缺口和平滑重开。所有窗口从未显示，defer 中 stop／close；本轮零 Typebar 主程序启动，没有新 timer、依赖、设置字段或迁移。

## 先行证据与修正

- `/tmp/typebar-ordinary-tape-entry-red.log` 最初夹具字段／参数顺序编译错误，不算行为红测；修正后 `entry-behavior-red.log` 七项有 27 个预期失败（10.636 秒），随后 `entry-first.log` 28 项零失败（8.553 秒）。此处简写文件均位于 `/tmp/typebar-ordinary-tape-` 前缀。
- `/tmp/typebar-ordinary-tape-outer-viewport-red.log` 一项两失败（1.119 秒），实际 Tape 外层确有独立滚动容器；修正共用父层策略，而非只修测试根视图。
- `/tmp/typebar-ordinary-tape-entry-expanded.log` 41 项四失败（13.494 秒）：自然四行错误变成五行。完整源码建词后，`tail-red.log` 两项 15 失败（1.681 秒）确认多余末尾词是产品缺陷；保留四行期望，修正投影。`entry-corrected.log` 52 项零失败（11.879 秒），`entry-regression.log` 304 项零失败零跳过（51.413 秒）。
- `/tmp/typebar-ordinary-tape-boundary-red.log` 同时暴露真实隐藏空词误删与一个错误测试假设（中文不走空格提交）。读取实际语言策略后纠正后者，`captured-boundary-red.log` 一项仅剩真实空词误删失败（0.763 秒）；改为会话实际隐藏边界条件。未修改输入策略来迎合错误假设。
- `/tmp/typebar-ordinary-tape-entry-final-regression.log` 304 项零失败但 15 跳过（27.593 秒），因漏传参考路径，不能算完整对照成功。补齐固定参考／锁定 Anime.js 后，`entry-pinned-regression.log` 304 项零失败零跳过（50.186 秒），其中十二个普通入口测试通过（6.737 秒）。

十一张定向图位于 `/tmp/typebar-ordinary-tape-focused-images.WA8xid/ordinary-tape-*.png`，主代理已逐张查看。非空断言要求灰色文字像素，不允许只凭蓝色光标通过；短题三行、后来两行／四行、退休与纠错另有实际几何断言。窄图裁剪是预期，不据此宣称完整设备可读性。

## 有界风险复核与未完成项

同会话三轮复核分别检查初始能力／拓扑／高度分离、生产外层所有权、空尾与真实隐藏边界身份。反例先失败再修正；不是独立审计。两个旧静态测试只删除与本次新生产行为矛盾的“必须保留回退”断言，原几何／退休断言不变，新入口测试明确断言解除保护。

任意 IME／组合 replacement、hint、no-space 内部 LF 完整导航、零偏移别名、未来缺失目标激活、反向纵横队列及字体重建确认时序、可见范围性能、原版字体／主题资源、ASL／Choo 全部组合与实体设备仍开放。CFG-02／MET-67 与 tapeMode 仍部分兼容；94 配置的 90 映射／3 部分／1 不适用不代表功能全通过。此前普通换行生产回退的历史结论仅在本合同范围更新，其余缺口不升级，完整 goal active。

## 最终冻结验收

首轮十五文件冻结哈希始终一致；`/tmp/typebar-ordinary-tape-final-readiness.log` 终态退出 1，在页面证据审计发现旧测试符号引用，尚未执行原生全量／服务／打包，不计成功。修正页面证据矩阵的重命名符号，登记本轮十三项真实测试，不提升兼容分类；原始失败日志保留，之后重新冻结运行。

最终重新冻结十六个文件，`/tmp/typebar-ordinary-tape-verified-frozen.sha256` 在启动、中途与终态逐项一致。`/tmp/typebar-ordinary-tape-verified-readiness.log` 终态退出 0：原生 3,953 项零失败零跳过（978.921 秒），服务 501 项零失败零跳过（11.730 秒）。十二项普通入口测试 7.026 秒，十一项控制投影测试 0.037 秒、九项 Zen 入口 2.807 秒；十万词耐久 177.552 秒，16 项隔离磁盘迁移 5.589 秒。原生全量中实际只读失败／损坏存储夹具和系统 Contacts／CoreData 诊断均保留，不能当作 XCTest 失败，也不据此宣称设备环境无诊断。

固定源码门禁（含本轮 768 组／八组实际建词）、53 页面／modal 表面、1,126 唯一人工场景结构、94 配置的 90 映射／3 部分／1 不适用、未启动应用包／签名／资源及原创长文字边界检查全部通过。人工结构检查不是实际人工验收，原创边界检查不证明全部功能、字体或设备等价。73 份原始日志位于 `/tmp/typebar-ordinary-tape-verified-logs.7Ob20I`，210 张图位于 `/tmp/typebar-ordinary-tape-verified-images.ayvvel`。主代理终态后逐张复查十一张 `ordinary-tape-*.png` 与八张 `zen-tape-*.png`；普通图有灰色文字像素，Zen 黑字／透明背景限制沿用旧合同。退休 pace 开／关整张 PNG 仍精确一致。

终态确认无测试、编译、门禁或 Typebar 主程序残留，再仅补本合同、README、规范和盘点的验收记录；其余十二个冻结文件保持一致。参考始终为干净固定 pin，本轮零主程序启动，完整 goal 继续 active。
