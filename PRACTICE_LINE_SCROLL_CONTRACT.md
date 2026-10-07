# 原生换行滚动与平滑动画

后续普通旧词移除、动画完成回调与回删保护见 [旧词裁剪合同](PROMPT_WORD_RETIREMENT_CONTRACT.md)。以下旧词仍全部留在文档的描述属于该滚动阶段；特殊渲染、混合行高及原版重叠队列仍开放。

普通文本有界练习现在按活动词推进整行：进入第二行不滚动，后续连续换行保留前一行在顶部。平滑开关接通 125 毫秒、二次减速曲线；关闭或减少动态效果时立即定位，重开和移除视图取消旧动画。旧词删除及其回删边界仍未对齐，CFG-02 部分兼容、完整重写 goal active。

## 原版规则与原生实现

固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41` 的 [活动词更新](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-ui.ts#L155-L209) 只在有界模式的活动词向下一行移动时调用 [lineJump](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-ui.ts#L1174-L1243)。第一次仅增加行计数；之后删除上一活动行之前的节点。平滑时先移动词和两个光标的上边距，125 毫秒后删除并归零。原版锁定 Anime.js 4.2.2，实际默认曲线是 `out(2)`，不是自行假定的线性或 easeInOut。

生产 `PromptAutoScrollOverlay` 取得活动词的稳定目标 ID、本轮 UUID 和完整渲染偏移映射，不按每个光标字符提前推进。`PromptLineScrollGeometry` 与光标共享字体和段落准备，按 Character 转 UTF-16 后读取 TextKit 行片段；连续前进使用上一活动词的行顶，字体／宽度变化重新居中。极长原生词跨多行时另保留光标可达性，回到保留文字的原生导航仍可向上跟随。

文字、主光标与节奏光标位于同一滚动文档，一起移动。定位使用 [NSClipView 的 bounds 约束](https://developer.apple.com/documentation/appkit/nsclipview/constrainboundsrect(_:)) 和原生 scroll，不引入浏览器。普通测量容器增加一屏底部空白，使末尾仅剩两行时仍可推进；可见区域仍由 [两行与三行高度](PRACTICE_VIEWPORT_HEIGHT_CONTRACT.md) 控制，特殊渲染回退和全部行路径不改变。

每个跟随视图至多持有一个主 RunLoop 计时器，继承既有全局有效帧率环境，并按屏幕最大刷新率限制请求频率；无屏幕时回退 60 Hz，不是固定忽略设置的 60 Hz。NSScreen 最大刷新率 API 自 macOS 12 可用，本项目最低 macOS 14；最大值限制不证明实际 vsync 或可变刷新率调度。弱目标不保活视图，计时器身份拒绝旧回调；同终点不反复重启动画，改帧率保留原始时间／位置，新终点从当前位置替换旧动画。重开立即归位；移除／拆卸视图停止计时器。用户与系统减少动态效果合并，主光标自身的移动动画与此共享滚动仍是不同层次。

归档 32、设置 5、偏好 v3、五实体／32 列、六个历史 writer 及服务协议不变。产品未添加 Anime.js、参考源码或资产；完整库仅在仓库外用于 QA，原生曲线是独立数学实现。

## 自动化与离屏证据

先行五项产生四个有效失败断言：两次连续推进的终点，以及减少动态效果／平滑模式的最终位置，日志 `/tmp/typebar-line-scroll-red.log`。词内移动和重开用例在旧路径上已通过，不冒称它们产生失败。首次实现因 Swift 6 的 Sendable Timer 参数跨隔离域捕获而编译失败，改为主线程弱目标／selector；扩展测试另修正局部 ViewBuilder 的显式捕获要求，没有降低并发检查或断言。

首阶段相关 32 项零失败零跳过，3.413 秒，日志 `/tmp/typebar-line-scroll-expanded-fixed-focused.log`。帧率复核另建立先行测试：15 FPS 下固定 60 Hz 旧实现提前移动 13.090 点，产生一个有效失败，日志 `/tmp/typebar-line-scroll-frame-rate-red.log`。修正后最终相关 34 项零失败零跳过，4.142 秒，日志 `/tmp/typebar-line-scroll-frame-rate-focused.log`。新增十六项覆盖首次与后续换行、词内光标、实际逐帧移动、减少动态效果、重开、连续动画、移除视图、字体重排、RTL、Emoji／组合字符、长词可达性、末尾短提示生产组件、源码对照、进度端点、低帧率／运行中改帧率及屏幕上限。实际生产组件还验证自定义帧率环境确实传到跟随器。

`Scripts/check-source-line-scroll.mjs` 校验固定提交和干净工作树，执行完整 `removeTestElements`／`lineJump` 函数。六组均匀行高／开关序列包含 30 次连续换行，实际函数执行删除并传递词及两个光标动画参数，逐步与生产原生定位策略比较。DOM、动画 promise 和包装高度更新使用自有替身，不运行整个 UI 模块，也不证明真实异步重叠。

探针验证 Anime.js 4.2.2 压缩包 SHA-512 与参考锁文件一致，在仓库外读取完整 ESM bundle，实际创建数值动画并 seek 六个时间点，逐项对照原生曲线。另执行完整 `applyEngineSettings`，以自有存储 getter 提供五档帧率，检查实际引擎及动画默认帧率；不代替存储 schema 或低帧率模式测试。完整门禁接入该探针并向原生对照测试传入固定包路径；包既不安装到产品依赖，也不进入应用资源。

未显示的 NSWindow 中，实际生产有界容器完成三词输入后显示 `birch`、`cedar` 和一行留白，滚动原点 45 点、区域 135 点；截图 `/tmp/typebar-line-scroll-qa.SYHwlx/short-last-word.png` 已检查。没有 Typebar 图形进程，不把该组件截图计为整应用、真实键盘或设备验收。

## 尚未对齐的滚动范围

旧文字仍留在原生滚动文档，可手动回看和回删；原版会删除旧词，并由 DOM 可用性影响回删边界。原生终点一致不等同已实现删除。混合字体／行高、空白行跳跃、特殊渲染、Zen 长词盒布局、Slow Timer、原版重叠动画的 `currentLinesJumping` 累积与光标队列时序仍需对齐；当前重入测试只证明原生最终采用最新有效目标。

输入时切换全部行／字体／窗口、节奏光标实际动画、系统减少动态效果、VoiceOver、可变刷新率和长提示输入帧率尚待唯一隔离候选验收。既有全局低值帧率差异已由后续 [慢计时帧率合同](ANIMATION_FRAME_RATE_CONTRACT.md) 修正为固定 30 及设置恢复；实际设备与完整 Slow Timer 词更新仍开放。整段富文本转换和字形生成仍有完整提示成本，未宣称性能有界。同会话风险复核检查稳定 ID、重开、弱引用、计时器替换、帧率继承、底部空间和旧词导航反例，不是独立审计。三个新增人工场景保持待验收。

## 首轮完整验证与最终版本边界

帧率接入前的首轮完整门禁原生 3,297 项零失败零跳过，689.390 秒；服务 465 项零失败零跳过，10.046 秒。十万词耐久 145.644 秒，15 项磁盘迁移冷读 5.958 秒；990 场景仅结构、未开窗包／签名／资源／原创性通过，33 份日志在 `/tmp/typebar-line-scroll-final-logs.gYSc0t`，总日志 `/tmp/typebar-line-scroll-final-readiness.log`。首轮不冒充随后帧率修正版本的全量证据，最终版本再次串行验证。

最终帧率修正版本的完整串行门禁通过：原生 3,299 项零失败零跳过，690.369 秒；服务 465 项零失败零跳过，9.760 秒。十万词耐久实际执行 145.434 秒，15 项磁盘迁移冷读 5.418 秒；990 个人工场景仅结构审计通过，未开窗应用包、签名、资源及原创性边界通过。

最终 33 份日志在 `/tmp/typebar-line-scroll-final-fps-logs.Da5iDZ`，总日志 `/tmp/typebar-line-scroll-final-fps-readiness.log`。七个产品／测试／脚本 SHA-256 与最终门禁前冻结值完全一致，完成后仅补验证文档。既有 Contacts XPC 提示和故意触发的只读 SwiftData 保存失败不算 XCTest 失败。零 Typebar 图形启动、真实用户库写入及部署；旧词、低帧率模式和设备等价仍未完成，完整 goal active。
