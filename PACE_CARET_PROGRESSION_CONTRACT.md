# Pace 逐词推进和原生插值

当前 [零时长追赶定位](CARET_LINE_COMPOSITION_CONTRACT.md) 已接入原生截止回调；负时长不瞬移，绘制入口仍合并。前一目标从 UTF-16 逻辑目录查询，避免待应用错词修正时误用普通插值起点；逻辑推进和数据格式不变。新增九项、相关 112 项通过，36 组共享几何源码轨迹含待应用修正。追赶期间的引擎呈现、任意修正顺序和实机仍开放，完整 goal active。

当前普通原生层已接入 [独立截止点调度](CARET_LINE_COMPOSITION_CONTRACT.md)，生产逻辑模型不变，单个待执行原生计时器负责中间定位请求，绘制另受 FPS 约束。九项新增与相关 100 项通过；下文“无每字符任务／计时器”描述旧的仅模型／绘制阶段，不再表示当前没有截止点回调。OS 迟到多步全部顺序、特殊分支及设备仍开放，goal active。

Pace 不再把经过时间乘速度后夹到提示末字：当前会话使用独立逐词目录、UTF-16 逻辑步和错误词修正，普通原生光标层按绝对截止点线性插值。题目耗尽、会话结束或活动中重新初始化会隐藏 Pace。这是有界功能增量，不是完整 Monkeytype 功能或浏览器像素等价声明。

## 固定源码和行为映射

只读参考固定为 `91bd24bb8513785c7364cbea29296ff7adafac41`。生产代码是独立 Swift 实现，不导入原版代码、语料、主题或其他资产。源码仅在外部参考检出中读取，探针不打包进应用。

| 行为 | 原版证据 | 原生接入 |
| --- | --- | --- |
| 启动与定时 | [pace-caret](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/pace-caret.ts) start 立即 update，先递增目标，再按起点计算截止点 | 首次接受输入或开始组合后从字母 0 动画到 1；晚到刷新按绝对截止点补进，不累加刷新误差 |
| 词长度 | [test-words](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-words.ts) 区分 text 与 textWithCommit；pace-caret 每词额外一个导航步 | body 长度使用 UTF-16，提交长度包含实际 SPACE／LF；no-space 保留真实目录而非猜词界，也有虚拟导航步 |
| 错词与重交 | [word-navigation](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/helpers/word-navigation.ts) 导航前调用 handleSpace | 首次错交增加完整目标提交长度，重复错交不重复增加；改正确后减回一次。停键和自动删除的未提交输入不触发修正，强制错误不能靠相同文字变正确 |
| blind | pace-caret 忽略 blind 提交，且 blind 更新不消耗待修正量 | 保留已存在待修正量，解除 blind 后应用；blind 内新提交不记录 |
| 重设与结束 | pace-caret init 更换 settings，旧 timeout 以对象身份守卫；reset 清 timeout | 原生为会话值状态，无每字符任务；重设丢弃旧状态，不在已开始会话自动重新 start，重开从新目录启动；耗尽不钉住最后字符 |
| 设置事件 | pace-caret 仅 paceCaret 配置事件重新 init；custom speed 单独变化不改当前 interval | 活动 custom 仅改速度时下次重开取新值；改模式重新初始化并隐藏，不清空输入；样式改变不改逻辑步 |
| 几何 | [caret](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/caret.ts) 使用 DOM letter 和字后边缘 | 原生使用 TextKit 和现有字体／主题，线性插值位置与尺寸；末词／LF 字后锚点不跳到下一行，尊重减少动态效果 |

原版逻辑 UTF-16 和 DOM codepoint 几何并非同一单位。原生将代理对／组合书写簇内位置合并到原生字形，属于明确的几何适配，不声称与原版每个 DOM letter 完全等价。full-width 字后宽度使用原生字体的 SPACE 度量，不冒充 CSS inter-word margin；旧起点离开视口时从可见终点落位，不证明原版滚动行为一致。

## 状态 生命周期和兼容性

PaceCaretProgress 仅是当前 TypingSession 的暂态值，不编码、不加入 SwiftData、不改历史回放或分数。归档仍 24、设置仍 4，自定义小数及 v2 偏好回退边界沿用 [自定义 Pace 合同](CUSTOM_PACE_SPEED_CONTRACT.md)。与不启用 Pace 的实际结果比较，回放事件、字符统计、精确速度和准确率保持相同。没有执行真实旧库升级、旧二进制或混合客户端恢复。

普通目录只追加新词，未闭合末词与新 chunk 合并；no-space 使用实际追加字段。未知 no-space 目录关闭 Pace，不从显示字符串伪造目录。逻辑查找为前缀索引二分，晚到补进受目录长度约束；采用 12 / WPM 避免 WPM * 5 的中间溢出。巨大有限值被有界耗尽，不复刻原版退化为零延迟的 timer 循环；非有限值拒绝，是安全差异。

关闭、结束或无可见 frame 时不建立逐帧光标层；活动时复用配置帧率及系统／应用减少动态效果。提交正确性读取当前字段，不为普通提交扫描完整提示；强制错误仍读取现有错误标记路径。实际活动 TextKit 的 CPU、布局抖动和持续内存尚未实机测量，20,000 词目录夹具不能代替 Pace-on 长练习耐久。

本阶段最初以 Date 驱动 Pace；后续 [单调时钟合同](PACE_MONOTONIC_CLOCK_CONTRACT.md) 已替换为独立 SuspendingClock，事件／UI 日期不再推进节奏。下文 63 组／2802 项是本阶段历史证据，当前新增证据见新合同；实体睡眠／唤醒、整个测试的日期计时及浏览器时钟政策仍开放，不将 Pace 修复冒称完整时间系统等价。

回退单位是整次程序版本和新会话：关闭 Pace 不影响保存记录，暂态无需数据迁移。移除旧扁平投影前已检查无生产消费者，并将原有测试的断言移到实际新会话；没有共享旧状态、双写或破坏性清理。旧小数格式的回退仍需要备份新数据，不因此变得安全。

## 自动化证据

先行三项测试有三处有效行为失败，展示旧投影的首次位置、错词修正和末尾钉住问题；随后断言迁移到实际新会话，未保留仅测试旧 helper 的绿灯。Swift exclusivity 编译错误修正不计产品 RED。新增 21 项 PaceCaretProgressionTests，相关定向 105 项通过；另补同一结束测试的真实 timed completion 断言，进入最终门禁验证。

Scripts/check-source-pace-selection.mjs 用 Node 24.19.0 执行四个实际完整模块：pace-caret、collections/results、db 和 test/test-words。原有 46 组选择夹具加 17 组推进夹具，共 63 组通过。时钟／timeout 为受控适配，Query DSL、认证、标签 PB、Caret 为有界适配；没有运行 DOM、animejs、TanStack、真实浏览器或官方账号。涵盖即时目标、虚拟导航、错交／重交、blind、emoji／LF／no-space、晚到补进、耗尽、reset、旧 callback 身份与 custom-only 速度修改。

原生测试覆盖实际输入、退格重交、stop/delete-on-error、真实 no-space 工厂、强制错误、组合开始、模式切换、结果不变、结束隐藏、目录增长、巨大值、钟回退及原生线性／RTL／减少动态效果矩形。矩形单测不是截图或浏览器布局证明。先行、源码、定向日志分别在 `/tmp/typebar-pace-progression-red.log`、`/tmp/typebar-pace-progression-source.log`、`/tmp/typebar-pace-progression-final-focused.log`，不作为应用资源。

补充 timed completion 后最终冻结前定向 105 项零失败（0.314 秒），四模块 63 组源码夹具仍通过。完整串行门禁客户端 2802 项零失败、零跳过（681.620 秒），服务端 164 项零失败（1.772 秒）；831 条人工场景结构、固定参考／原创性／元数据审计及未打开应用包检查通过。十万词实际 passed 为 146.141 秒，旧 12000 次组合字形删除双投影为 0.025344 秒。这些耐久数据不证明活动 Pace 动画的实机性能。

完整门禁日志为 `/tmp/typebar-pace-progression-readiness.log`，客户端／服务日志分别为 `/tmp/typebar-pace-progression-gate-client.log`、`/tmp/typebar-pace-progression-gate-service.log`。包捕获日志没有最终审计行，以门禁成功退出和 `macOS app package check passed` 为包验证证据；不把局部捕获冒称完整日志。冻结前定向及源码日志为 `/tmp/typebar-pace-progression-prefreeze-focused.log`、`/tmp/typebar-pace-progression-source-final.log`。AddressBook／CoreData XPC 环境诊断不是 XCTest 断言失败，也不算系统服务验收。

门禁期间未编辑文件；门禁与日志捕获均结束后只补结果文档，再作提交前定向和源码检查，生产行为不改。参考检出仍固定且干净，Typebar 图形进程为零，真实背景成绩目录不存在。四条新增人工场景保持待验收，清单审计只验证 ID／状态／单实例规则，不代表人工通过。

提交前复核定向 105 项零失败（0.343 秒），四模块 63 组源夹具和 831 场景结构检查通过；日志为 `/tmp/typebar-pace-progression-postgate-focused.log` 和 `/tmp/typebar-pace-progression-postgate-source.log`。本次服务生产代码和依赖未改，Swift 6.2.4／macOS 14 最低目标沿用现有配置。

## 仍开放的原版兼容性

Tape、混合逐字 RTL、ASL／Choo／listening 等当前 fallback 有逻辑目标但没有本层完整连续插值，全部组合仍待接入。真实键盘／IME、VoiceOver、滚动和像素位置、取消生命周期、Pace-on 长练习、系统时钟／睡眠唤醒、旧库／二进制回退均未验。引语 ID、标签身份／认证及 PB 快照时序见 [结果选择合同](PACE_RESULT_SELECTION_CONTRACT.md)；官方 187 主题身份、一个挑战、内容／分布和 XP 精确公式等整体缺口不关闭。

行为优先和源码驱动约束逻辑；原生 UI 技能要求复用现有字体／主题层及减少动态效果，不建浏览器壳；迁移安全和会话内有界决策／风险复核限定数据与资源承诺，不是独立评审。完整纯原生重写 goal 保持 active，功能追踪表不升级为全等价。
