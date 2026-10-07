# 原生换行重叠动画与完成通知

普通有界文本的换行滚动现按待完成跳行数累计位移，新跳行替换旧完成通知，不再将两次裁剪下界取最大值。原生自动播放采用固定参考引擎的 12 毫秒预进；125 毫秒仍是动画参数时长，不等于每次实际等待都正好 125 毫秒。非跳行更新保留原动画时间，第一跳和无可移除前缀仍不因此滚动。完整重写 goal active，CFG-02／MET-67 仍部分兼容。

## 固定源码与真实引擎证据

固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41` 的完整 [lineJump 与移除函数](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-ui.ts#L1174) 使用 `currentLinesJumping` 累计次数，以最新活动词 outerHeight 乘该次数构造负 marginTop。完整 [promiseAnimate 方法](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/utils/dom.ts#L822) 只在 onComplete 中 resolve。实际 Anime.js 4.2.2 的 replace composition 取消被覆盖的旧动画，旧 promise 不完成，因此旧 lineJump 的 await 后移除与计数路径不执行。不能用手动 resolve 所有 promise 的替身代替此行为。

锁定归档的 SHA-512 与参考 pnpm lock 一致。完整真实引擎、composition、timer 和缓动代码在独立 VM 中运行，自有 Date 时钟逐毫秒推进。自动播放的 resume 将起点预进 12 毫秒；有效帧在墙钟经过 25 毫秒时使用 37 毫秒缓动位置。首次 requestTick 与帧率调度可能推迟首个有效帧，实际显示器仍单独验收。

`check-source-line-overlap.mjs` 执行完整上述函数与方法，覆盖 0／25／75 毫秒间隔、两次／三次跳行以及均匀／变化的受控词高，共 12 组；108 个运行中采样核对曲线、预进与完成。只有最新 promise 完成，旧动画 completed 为 false，最终只执行最新捕获的前缀移除；参考行计数仅增加一次。DOM、词盒高度和 offsetTop 是自有受控边界，动画对象是普通属性对象，不是浏览器 CSS 节点。[CSSOM View 的 offsetTop 接口](https://drafts.csswg.org/cssom-view/#extensions-to-the-htmlelement-interface) 使用整数 long；探针按整数模拟，具体像素舍入和真实 DOM 排版不在本证据范围内。

探索期的首帧墙钟假设与小数 offsetTop 替身曾失败，修正为真实 animationTime 与整数几何后通过；不把探针错误计作产品缺陷。已有六个 seek 曲线样本仍独立保留，但不再用它们声称证明实际引擎完成时序。

## 原生实现与验证

`PromptLineScrollOverlap` 保存本段动画的起始基线及待完成次数，目标使用最新原生行高乘次数，不累计各次旧行高。TextKit 最末行补回省略的行距，避免末尾词跳行变短；原生行高不宣称等同所有浏览器词盒 outerHeight。

只有有可裁剪前缀的真实跳行才累计并替换完成通知，即使物理终点相同也重启该次动画。普通同词／帧率更新不因此重启。受到原生 clip 限制而零距离的新跳行仍等待完成；关闭平滑或减少动态效果时立即处理。动画完成、重开、拆卸、字体／方向／宽度重排清理累计状态与旧通知。仍只有一个弱所有者计时器和一个最新完成通知，没有新增 GUI 实例、产品 JavaScript 或依赖。

先行四项产生 87 个失败断言，日志 `/tmp/typebar-line-overlap-red.log`。其中原生旧组件复现新跳行仍通知旧下界 3 而非最新下界 2；新累计状态的占位实现与旧自动播放时间模型不满足源码夹具。87 个断言不是 87 个独立产品缺陷。首轮修正后 43 项通过，日志 `/tmp/typebar-line-overlap-first-green.log`。

新增十项，最终相关 84 项零失败零跳过，21.479 秒，日志 `/tmp/typebar-line-overlap-final-focused.log`。覆盖累计目标、实际引擎采样、最新通知替换、相同终点的新跳行、零距离完成、即时路径、重开／拆卸／宽度取消及末行行距。实际生产 viewport／overlay 与真实 TypingSession 的未显示 NSWindow 夹具连续输入前三行，最终裁剪下界为 2，剩余 `cedar`／`delta`／`elder`／`flint`，原点归零；完整 35 字符输入的计分、回放及归档保持。夹具采用自有简化样式，不是完整应用窗口验收。

归档 32、设置 5、偏好 v3、五实体／32 列、六个历史 writer 和服务协议不变。源码执行和第三方引擎仅用于 QA，不进入产品。源码探针已接入完整门禁。

## 仍开放的范围

完整 RAF 与 updateActiveElement／词更新的相互排序、DOM 换行辅助节点、混合字体／词盒高度、专用渲染、Zen 特殊词盒、长词原生拆行、真实 IME 和显示器仍需对照。不同高度的受控数学夹具不证明浏览器和 TextKit 的所有实际字体布局一致。

原版平滑完成时在移除前缀前更新 activeWordTop，而原生前缀重建会重新锚定；无实际位移、多行重入及减少动态效果／设置切换的交错仍开放。原生保留拒绝隐藏当前输入字段的 UUID／单调裁剪护栏，不把最新通知测试当作所有退回时序均等价。原生光标与节奏光标相对动画尚未全部对齐。

同会话风险复核检查过替换所有权、累计重置、零距离通知、坐标与数据隔离，不冒称独立评审。十万词引擎耐久不证明超长提示 UI 帧率；三个新增人工场景保持待验收，只允许后续唯一隔离候选。旧合同中“相同终点始终不重启”和“重叠队列完全未执行”的描述为历史阶段，当前范围以本合同为准，不升级整体功能兼容状态。

## 完整验证

冻结版本完整串行门禁通过：原生 3,359 项零失败零跳过，735.972 秒；服务 465 项零失败零跳过，11.222 秒。十万词耐久实际执行 150.654 秒，15 项磁盘迁移冷读 7.266 秒；1,006 个人工场景仅结构审计通过，未开窗应用包、签名、资源及原创性边界通过。

39 份保留日志在 `/tmp/typebar-line-overlap-final-logs.wWwsUE`，总日志 `/tmp/typebar-line-overlap-final-readiness.log`。两个产品源文件、一个测试、一个源码探针及门禁脚本共五个 SHA-256 与 `/tmp/typebar-line-overlap-frozen.sha256` 一致，门禁后仅补验证文档。既有 Contacts／CoreData XPC 提示、隔离坏库和故意只读保存错误不是 XCTest 失败。零 Typebar 图形启动和服务部署；三个新增人工场景仍待单实例验收，完整功能等价未完成，goal active。
