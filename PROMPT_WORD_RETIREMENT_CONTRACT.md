# 原生旧词移除与回删边界

2026-10-09 换行 Tape word-only 增量：横向移除与纵向裁前缀现已分开。`TapeNewlineFlow` 持久记录缺失 word／filler 身份，真实 TextKit 重排仍保留 beforeNewline 与 newline 占用行；邻接变化、leading filler 补偿、cap 和空行纵向边界有完整函数与原生组件证据。视图发出独立 `PromptTapeWordRemoval`，不伪造 `PromptWordRetirement`，并修正删后测量导致普通重绘多滚动一次的缺陷。六新增／相关 181 项通过，120 组两次完整请求对照，四图非空且重复绘制一致。**独立词集合尚未接入 TypingSession 回删、共享显示投影与字体重建恢复，生产换行仍回退**；当前活动词保护是 native 防丢策略，任意未来／反向／纵横调度和复杂内容仍未证明。完整冻结结果见交付合同，tapeMode 部分、完整 goal active，下方为阶段历史。

2026-10-09 换行 Tape 实际 owner：现已接通 native 纵向等待、完成帧内部删行、leading-filler 补偿与异步会话确认去重；新词横向请求等待完成，同词输入仍独立滚动，重叠只由最新 owner 完成，尺寸／重启／拆卸取消。10 新增／相关 175 项、128 条归一化完整源码轨迹与六张 never-visible 实际组件图补证；完成与确认像素一致且非空。生产工厂仍不传 newlineWords，明确换行仍回退；换行横向溢出退休组合、反向异步等价、控制／Zen／hint／joining／混合行高／尾随 Return 与设备仍开放。回到待删前缀时拒绝删当前活动词，属防丢策略而非原版任意反向队列等价证明。完整冻结结果见 [交付合同](REWARD_INBOX_CONTRACT.md)，tapeMode 部分、goal active，下方为阶段历史。

2026-10-09 换行 Tape 前缀组件：确认移除旧行后，真实 native 词框读取已呈现的 leading-filler／行内前缀位移，不用可能超 cap 的数学词宽；保留 filler 在本次 lookahead 范围先重定再续动，重复确认不二次补偿、同轮新输入不被吞掉。九项回归与 64 组完整源码／TextKit 共享测量、四张实际裁前后图补证，保留两行像素一致。仍未接通实际纵向 owner 的 await／通知和生产含换行 Tape，单行退休禁用及生产回退保持。完整冻结结果见 [交付合同](REWARD_INBOX_CONTRACT.md)，tapeMode 部分、goal active；下方为阶段历史。

2026-10-09 Tape 纵横通道：修正 wordsDidFinish 清整个 words 的缺陷，纵向结束只清纵向 margin／ready／tween；运行中横向状态及其原时钟、独立 marker 和滚动原点保留。7 新增／相关 160 项通过，128 条完整源码／共享几何轨迹证明有界等待、重叠、leading filler 删除和退休补偿顺序；真实 follower 的重叠／重开无窗口回归通过。此处没有把源码 leading-filler 证明升级为实际 native Tape 前缀接线，生产回退与单行退休禁用保持。完整冻结结果见 [交付合同](REWARD_INBOX_CONTRACT.md)，tapeMode 部分、goal active，下方为阶段历史。

2026-10-09 换行 Tape 布局组件新增：累计缩进、Return 宽度与独立 filler 动画已有源码／原生框对照，但未接通生产换行退休。明确禁止该组件套用单行退休；生产普通换行回退保持，原版 lineJump 后的 leading-afterNewline 清理及纵横 await 顺序需另行组合取证。14 新测试／相关 99 项通过，完整冻结结果见 [交付合同](REWARD_INBOX_CONTRACT.md)，tapeMode 部分、goal active。

2026-10-09 当前 Tape 增量见 [交付合同](REWARD_INBOX_CONTRACT.md)：单行 LTR／RTL 接通独立横向退休，按新请求前已呈现词框和严格整数阈值判断，不等待动画结束。确认裁前缀补偿 words 原点和 main／pace 累计位移；无变化重绘／纯确认不额外退休，异步通知有身份与代次取消，完整会话不删。12 新增／相关 120 项、32 条新增完整实际动画源码轨迹及四张前后图通过。下方普通换行与早期未覆盖说明为历史阶段；Tape 换行、复杂控制与任意设备调度仍未证明，完整 goal active。

普通有界文本在后续换行完成后，从显示遍历中移除前一活动行之前的词及其额外错误字形；第一次换行不移除。平滑模式等待 125 毫秒动画结束，关闭平滑或减少动态效果时立即处理。移除只影响当前练习显示与可回删范围，完整提示、输入、计分和回放仍保留。CFG-02 保持部分兼容，完整重写 goal active。

## 原版规则与实现范围

固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41` 的 `frontend/src/ts/test/test-ui.ts` 中，完整 `removeTestElements`／`lineJump` 函数在第一次换行后才删除旧节点，平滑路径等待动画完成。完整 `input/handlers/before-delete.ts` 在 freedom 判断之前检查空输入字段的前一词节点是否存在；`insert-text.ts` 的完整 `handleDeleteOnError` 也要求前一节点存在，才执行 hard 模式的跨词恢复。

原生 `PromptLineScrollGeometry` 按当前渲染偏移测量各词的 TextKit 行顶，以上一活动词所在行确定移除下界；同一行的原生小数坐标统一向下取整。`PromptAutoScrollView` 在动画完成时通知会话，相同滚动终点仍合并较新的下界。重开、拆卸和移除视图取消旧通知；提示前缀实际缩短后，滚动坐标立即重置，避免留下空屏。

`TypingSession` 保存仅运行时存在的首个保留词序号，使用尝试 UUID、单调下界和当前字段检查拒绝过期或越过活动输入的通知。普通逐字／整词删除在 freedom 之前阻挡已移除的前一词；自动 hard 恢复也不返回该词。当前词的修正仍可进行。显示层移除旧目标字形和所属额外错误字形，保留稳定目标 ID，并重新生成剩余渲染偏移。

归档 32、设置 5、偏好 v3、五实体／32 列、六个历史 writer 和服务协议不变。下界不写进归档，不改写历史成绩；恢复练习不保证恢复此前已裁去的显示前缀。没有新增产品依赖，也没有将参考源码或资产复制到产品。

## 行为证据

先行三项产生八个有效失败断言，日志 `/tmp/typebar-word-retirement-red.log`，覆盖动画后通知、旧文字及额外字形仍在显示、偏移未归零和 freedom 回删。首次三项修正后通过，日志 `/tmp/typebar-word-retirement-first-focused.log`。随后同终点反例得到下界 1 而非 2，日志 `/tmp/typebar-word-retirement-same-target-red.log`；通知合并移到同终点提前返回之前，保留原动画时间。

最终新增十项，相关 118 项零失败零跳过，11.201 秒，日志 `/tmp/typebar-word-retirement-expanded-focused.log`。覆盖过期／倒退／未来／完成通知、重复练习、Unicode 与 no-space 删除边界、重开及拆卸取消、完整回放／计分／归档，以及真实生产滚动容器与原生删除命令。生产容器采用自有简单文字格式，不是完整应用窗口验收。

`Scripts/check-source-word-retirement.mjs` 前后校验固定提交及干净参考工作树，执行完整上述源码函数／删除模块：12 组均匀行高与平滑组合、60 次换行、32 种 before-delete 条件、8 种 hard 恢复条件。原生逐项对照，before-delete 条件分别走逐字及整词命令。DOM、行高、输入、导航和动画 promise 为自有边界替身；不声称运行浏览器或实际 Anime.js 排队器。既有曲线／帧率探针仍独立运行。

未显示的 NSWindow 中，实际生产容器输入 `amber`、`birch` 后，剩余渲染为 `birch`、`cedar`、`delta`，滚动原点为零；截图 `/tmp/typebar-word-retirement-qa.OjV603/ordinary-pruned.png` 已检查。再输入 `cedar` 后下界推进到该词，整词删除后不能回到已移除的 `birch`，完整原始提示和输入仍保留。没有启动 Typebar 图形程序。

## 仍开放的兼容边界

ASL／Choo 仍使用独立完整字形遍历，卷带没有普通换行移除跟随器；切换这些渲染可能重新显示前缀。普通全部行路径保留当前裁剪下界，但中途切换、空字段、代码缩进删除、混合字体／行高、换行标记和 Zen 特殊词盒尚未完整对照。代码非空缩进分支在原版也可绕过普通空字段检查，本增量不改写其独立规则。

原版重叠动画可能在用户退回后删除活动词，原生会拒绝隐藏当前输入字段的完成通知；这是明确未证明等价的顺序边界，不以最终终点测试关闭。完整原版动画队列、Slow Timer 词更新、节奏光标相对动画、真实输入／VoiceOver／显示器仍开放。逐次词变化测量和富文本生成仍有完整提示成本，十万词引擎耐久不证明十万词 UI 帧率有界。

同会话决策与风险复核检查过通知合并、尝试身份、取消生命周期、裁剪坐标、额外字形及数据保留；不是独立评审。三个新增人工场景保持待验收，不将结构审计或离屏组件图提升为设备验收。

## 完整验证记录

冻结版本完整串行门禁通过：原生 3,316 项零失败零跳过，713.704 秒；服务 465 项零失败零跳过，10.324 秒。十万词耐久实际执行 148.330 秒，15 项磁盘迁移冷读 6.404 秒；995 个人工场景仅结构审计通过，未开窗应用包、签名、资源和原创性边界通过。

35 份保留日志在 `/tmp/typebar-word-retirement-final-logs.3wADbb`，总日志 `/tmp/typebar-word-retirement-final-readiness.log`。五个产品源文件、新测试、源码探针和门禁脚本共八个 SHA-256 与冻结值完全一致，门禁后仅补验证文档。既有系统 Contacts XPC 提示、隔离坏库与故意只读保存错误不是 XCTest 失败。零 Typebar 图形启动、真实用户库写入与服务部署；完整功能等价未完成，goal active。
