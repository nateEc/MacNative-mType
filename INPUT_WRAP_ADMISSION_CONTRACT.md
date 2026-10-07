# 额外输入的原生换行保护

普通提示中的额外输入若会使活动词下移或增加占用行高，在计分、停错预览、声音反馈与回放之前被拒绝。判断接入引擎逐字符入口，批量输入、递归替换与延迟自动 Tab 使用同一入口；普通行数与全部行模式都接入实际提示宽度。完整重写 goal active，CFG-02 与 MET-67 仍部分兼容。

## 规则与生产接线

固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41` 的完整 `before-insert-text` 模块，仅在当前输入达到显示词 UTF-16 长度、字符不提交下一词时触发布局检查。空格提交不属于显示词，Return 属于；归一化发生在判断之前。Slow Timer、盲打、隐藏额外字母、hard 错误删除和 Zen 绕过检查，soft 错误删除不绕过。停错／删除规则不能提交的分隔符仍可触发检查。

原生 `TypingInputWrapAdmission` 只在一次输入调用期间存在，`defer` 恢复旧值；递归与同步自动输入继承，下一次独立输入不继承。实时延迟回调采用执行时的宽度、字体与 Slow Timer，并保留既有尝试 UUID 门控。布局拒绝不增加尝试数或错误数、不发出该字符反馈、不制造 stopped-input 回放；已开始测试的键盘活动记录保持原语义。

普通 Text 提示附加不可交互、无辅助功能节点的原生宽度桥。弱引用只接受仍挂载到窗口的视图，读取当前 bounds，避免旧异步宽度或脱离窗口的树参与拒绝。探针从当前逐字符会话生成同一 `PromptRendering`，保留旧词裁剪、提示、替换样式与方向，再追加缺失字段字母；不通过模拟修改会话预测布局。Return 的结构标记不重复计作输入，额外字母在原生标记前测量。

TextKit 与光标共享字体／段落准备。词范围的首末占用行构成几何高度，并扣除末行因后续词换行才增加的 trailing lineSpacing，防止仅后面的词换行就误拒绝。正常词内输入不调用排版探针；超过长度的候选仍可能排版整个已呈现提示，没有长提示帧率保证。

归档 32、设置 5、偏好 v3、五实体／32 列、六个历史 writer 和服务协议不变。没有导入参考产品代码、资产或依赖；源码执行只在 QA 探针中读取固定 checkout。

## 自动化证据

最初两个行为测试产生九个失败断言，日志 `/tmp/typebar-input-wrap-behavior-red.log`；旧实现会接受额外字母并增加计分／回放或停错预览。此前测试错误访问私有字段导致的编译失败另存 `/tmp/typebar-input-wrap-red.log`，不计行为反例。

扩展几何夹具复现三项“仅后续词换行”误拒绝；行框和 boundingRect 都包含 trailing spacing，最终改为首末行范围扣除该间距。来源夹具先错误调用无参 SlowTimer.set 并尝试用不可实时修改的 stop 规则建立前缀，修正为实际模块生命周期与可建立字段；早期失败日志保留，不作为通过证据。

挂载审查另复现脱离窗口仍返回 150 宽度，日志 `/tmp/typebar-input-wrap-detach-red.log`；窗口条件修正后通过。首次 129 项相关回归因未提供既有 Anime.js QA 归档而失败两项断言，日志 `/tmp/typebar-input-wrap-related.log`；补齐环境后最终 130 项零失败零跳过，16.997 秒，日志 `/tmp/typebar-input-wrap-final-focused.log`。

新增 13 项覆盖批量拒绝与计分／回放隔离、停错、整词下移／首词增高、后续词换行不误拒绝、三种字号、RTL 段落、旧词裁剪坐标、各绕过规则、Unicode UTF-16 门槛、Return、递归省略号、延迟 Tab、陈旧尝试、宽度调整和离窗保护。两个 NSHostingView／NSWindow 夹具均未显示窗口；不等于整个应用人工验收，零 Typebar 图形启动。

`check-source-input-wrap.mjs` 执行完整 before-input、validation、util、strings、test-words、SlowTimer 六个模块，456 个可建立字段夹具逐项比较原生探针调用次数、候选值和受拒绝输入不变。配置、输入状态、排版和 type-only Language 绑定是自有边界；三种几何结果受控，不执行 DOM 排版函数，不声称浏览器像素或事件队列等价。该检查已加入完整门禁。

## 兼容性仍开放

ASL、Choo 与卷带暂不接入普通 Text 的几何拒绝，仍需各自的实际渲染对照。空 no-space 字段、非 BMP 的 DOM scalar 字母数与 UTF-16 临时追加差异、混合字体／连接文字／复杂 IME、提示 hint 几何和真实 SwiftUI／TextKit 布局差异仍开放；RTL 测试是原生段落边界，不是阿拉伯连接字形验收。

本轮逐字符拒绝不替代浏览器最外层多字符 beforeinput、RAF pendingWordData 或原版 activeWordTop／Height 快照时序。Zen／Slow Timer 的同一活动词重排滚动、lineTransition／wordTopBeforeLineJump 顺序、特殊渲染前缀和完整结束调度继续追踪；不以光标可达性或这些受控夹具关闭缺口。三个新增人工场景保持待验收，只允许后续唯一隔离候选。

## 最终完整验证

冻结版本完整串行门禁通过：原生 3,336 项零失败零跳过，742.162 秒；服务 465 项零失败零跳过，10.559 秒。十万词耐久实际执行 156.262 秒，15 项磁盘迁移冷读 5.843 秒；1,000 个人工场景仅结构审计通过，未开窗应用包、签名、资源及原创性边界通过。

37 份保留日志在 `/tmp/typebar-input-wrap-final-logs.5p2ViG`，总日志 `/tmp/typebar-input-wrap-final-readiness.log`。五个产品源文件、一个测试、一个源码探针及门禁脚本共八个 SHA-256 与冻结值一致，门禁后仅补验证文档。既有系统 Contacts／CoreData XPC 提示、隔离坏库和故意只读保存错误不是 XCTest 失败。零 Typebar 图形启动与服务部署；特殊渲染、复杂文字、同词重排和完整功能等价未完成，goal active。
