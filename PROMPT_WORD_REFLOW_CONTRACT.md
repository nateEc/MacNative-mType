# Zen 与 Slow Timer 同词重排滚动

普通有界文本中，即使活动词 ID 不变，输入或替换使其整体下移时，Zen／Slow Timer 也会检查跳行。沿用原生平滑、减少动态效果、帧率继承和旧词裁剪；不靠光标溢出才滚动。首次跳行及没有可移除旧词的跳行只计数，不因此滚动。完整重写 goal active，CFG-02／MET-67 仍部分兼容。

## 固定源码规则与生产实现

参考固定提交 `91bd24bb8513785c7364cbea29296ff7adafac41`，只读完整 `updateWordLetters`、`updateActiveElement`、`removeTestElements`／`lineJump` 及真实 `debounced-animation-frame` 模块。词更新先写文字、等待提示合并、插入换行标记并调用卷带，再检查 `(zen || SlowTimer) && !Config.showAllLines`。这里使用原始设置，不是计时模式最终是否展开的派生策略。

活动词顶部严格高于保存基线才触发。非过渡状态保存本次顶部为重排门槛；过渡中必须继续超过该门槛，且重入不推进门槛。源码的 `offsetTop` 相对已定位的 wrapper，受 words 的 marginTop 动画影响；不能把纯文字绝对行顶当成动画中的可见顶部。

原生 `PromptWordReflowState` 独立维护基线与门槛。`PromptAutoScrollView` 使用同一 TextKit 布局，转换到文档／clip 坐标，再以旧基线查找可裁去前缀，保留第一跳不滚动的规则。即时定位与动画完成后重新锚定；尝试变更、裁剪、字体／方向／宽度重排及拆卸清理或重定位状态。仍使用既有单一最新终点的原生计时器，不新建应用窗口或后台动画队列。

同长度的文字／属性替换也重新测量，不再只比较字符数。真实文字更新标志跨同轮主队列合并保留，单纯启用 Slow Timer 不虚构一次词更新。普通练习区接入 `timerHealth.usesSlowTimer` 与原始 `settings.showAllPracticeLines`，NSViewRepresentable 转发新上下文；第一跳、旧词完成通知、尝试 UUID 和单调裁剪护栏保持。

归档 32、设置 5、偏好 v3、五实体／32 列、六个历史 writer、服务协议和产品依赖不变。不复制参考代码或资产进产品，参考函数仅在 QA 时从固定 checkout 读取执行。

## 行为证据

最初三项产生九个有效失败断言：同词移动未跟随、未裁剪、同长度替换未测量，日志 `/tmp/typebar-word-reflow-red.log`；首次三项修正后通过。设置切换反例再产生一个失败，日志 `/tmp/typebar-word-reflow-setting-red.log`；加入真实文字更新标志后四项通过。首次重排跳行反例产生一个失败，日志 `/tmp/typebar-word-reflow-first-jump-red.log`；限制第一跳与无可移除前缀的移动后通过。共十一项有效失败断言，不计扩展测试私有 `@Observable` 类型引起的编译错误。

新增十三项，最终相关 74 项零失败零跳过，18.575 秒，日志 `/tmp/typebar-word-reflow-final-focused.log`。覆盖等长宽字替换、原始全部行设置、动画门槛、首跳／无前缀、合并更新、设置切换、平滑完成、相同终点不重启、重开及拆卸取消。使用实际生产 viewport／overlay 和真实 `TypingSession` 的未显示 NSWindow 夹具，裁去 `aa` 后渲染为 `bb ccxx dd`，原点归零；完整输入、结果回放及导出归档保留。该夹具采用自有简化文字样式，不是完整应用验收。

离屏图 `/tmp/typebar-word-reflow-qa.hnYLiM/same-word-reflow-pruned.png` 已检查，显示保留的 `bb`、`ccxx`、`dd` 三行。全程零 Typebar 图形启动，不连接真实账户、不部署服务。

`check-source-word-reflow.mjs` 前后验证固定提交及干净 checkout。560 个完整词更新夹具执行真实 RAF 去抖、SlowTimer、strings 和 words 模块，确认最新输入覆盖、一次渲染、pending 数据清除，以及文字／提示／卷带／测量／跳行顺序；原生逐项比较重排谓词及门槛。另有八个完整 `lineJump`／移除函数夹具覆盖首次、无前缀、平滑与即时完成。DOM 几何、提示合并内部、卷带和动画 promise 为受控边界；560 组中的 lineJump 为记录替身，八组另行执行完整函数。没有运行浏览器排版或实际 Anime.js 重叠队列。该探针已加入完整门禁。

## 仍开放的兼容范围

原版 `currentLinesJumping` 累加、动画替换／promise 完成顺序、RAF 与活动词更新相互排序及光标相对动画仍未完全重写。原生采用最新终点，不能用门槛对照、125 毫秒曲线或最终位置证明完整队列等价。原版 smooth 与非 smooth 对基线更新的细节、没有实际移动的路径及连续多行重入仍需完整场景验证。

ASL／Choo／卷带不接入普通垂直跟随器；特殊渲染前缀、Zen 特殊词盒、混合字体／行高、复杂 IME／Unicode、换行辅助节点和真实 SwiftUI／TextKit 排版差异仍开放。整词在浏览器通常不拆开，原生长词仍可能跨行；既有光标可达性回退继续存在，不宣称等价。

富文本相等比较与逐次词顶测量仍有完整提示成本，十万词引擎耐久不证明十万词 UI 帧率有界。真实控件、单实例窗口、VoiceOver、显示器与人工输入仍待验收；三个新增人工场景保持待验收。同会话风险复核收紧第一跳、无前缀和设置合并，不冒称独立评审，不升级整体兼容状态。

## 完整验证

冻结版本完整串行门禁通过：原生 3,349 项零失败零跳过，733.409 秒；服务 465 项零失败零跳过，10.876 秒。十万词耐久实际执行 150.865 秒，15 项磁盘迁移冷读 5.699 秒；1,003 个人工场景仅结构审计通过，未开窗应用包、签名、资源及原创性边界通过。

38 份保留日志在 `/tmp/typebar-word-reflow-final-logs.E096Ww`，总日志 `/tmp/typebar-word-reflow-final-readiness.log`。三个产品源文件、一个测试、一个源码探针及门禁脚本共六个 SHA-256 与 `/tmp/typebar-word-reflow-frozen.sha256` 一致，门禁后仅补验证文档。既有系统 Contacts／CoreData XPC 提示、隔离坏库与故意只读保存错误不是 XCTest 失败。零 Typebar 图形启动与服务部署；三个新增人工场景仍待单实例验收，完整功能等价未完成，goal active。
