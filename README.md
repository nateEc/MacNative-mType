# Typebar

2026-10-02 应用范围音乐键位上下文增量（最终门禁已通过）：固定 [声音控制器](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/controllers/sound-controller.ts#L149-L355) 的 document keydown 和 [修饰状态](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/states/modifiers.ts) 后，新增由唯一应用代理持有的 MainActor 本地音乐键位监听器。启动回调注册一次，实际终止回调移除；不是按练习窗口反复创建，也不是系统全局监听，不申请辅助功能权限，不记录输入文字／回放／偏好。keyDown 同步保存物理键码与事件修饰状态，flagsChanged 同步更新，原样返回事件，不转发输入、不启动音频，不使用异步 Task 使上下文落后于同一输入。普通练习 keyDown 留作直接接入；移除练习输入失焦空 flags 对共享声音上下文的覆盖，避免错误清掉 Caps Lock。

特别区分按下和释放修饰键：浏览器 modifier keydown 也会替换当前 code 为非钢琴键，不能让 flagsChanged 只改变音高而沿用旧字母。用安装 SDK 26.2 的 IOKit.hidsystem／IOLLEvent.h 左右 Shift、Control、Option、Command 设备标志判断按下／释放；按下替换 code，释放只更新 flags。CapsLock 两个切换方向都作为非钢琴按下，无设备位的合成事件按已观察的侧键转换回退，真实位优先；左右并按后释放一侧不误清新的字母键。尚未宣称混合设备／丢事件／非标准 CapsLock 或 Fn 传输全对齐。

启动只同步当前 Caps Lock、不引入已按住的 Shift；应用重新激活时只刷新 Caps Lock，不覆盖已保存练习 Shift，停止前／后的激活无副作用。设置页试听显式 usesPracticeShift=false，保持测试页／命令面板默认 Shift 行为，而 Caps Lock 两处都有效；不把“捕获整个 app”误当“原版所有页面都跟踪 Shift”。完整原版 getActivePage 切换、左右状态复位和重置测试的 Shift 复位，其他页面与跨窗口作用域、IME／自动动作、无完成回调、浏览器 DSP／设备混音、样本随机变体及 16 号结束混响仍未完全对齐，goal 不关闭。

先行 6 项有效红阶段 12 个失败断言；两项重新激活补证 4 个失败断言；修饰按下补证筛选 3 项中两项共 10 个失败断言、合成回退那项在旧行为上已通过，不将它当反例。初次测试桩嵌套 Events 未标 MainActor 而编译失败，在根因定位到测试隔离边界后仅补注解再运行，不把编译错误当产品红证据。最终 MusicKeyboardMonitorTests 22 项，相关 106 项零失败（约 0.53 秒），含已有 21 项音乐、35 项声音、副本／回放／NoQuit／快速重开等选中回归；不据环境变量宣称窄过滤执行十万词。

只读 bundled Node v24.19.0 类型擦除／内存执行实际声音与 modifier 模块：其他 responder 的 Z 为 130.81 Hz，全局 Space 静音；test 页 Shift 试听为 523.25、切到 settings 为 261.63、Caps 开时仍 523.25；settings 仅保留 1 个 keydown、0 个 keyup，返回 test 为 2／1。另执行实际声音模块全局监听，左右 Shift／Control／Alt／Meta 和 CapsLock 九种 modifier keydown 均静音；没有新 keydown 时释放 Shift 后仍沿用 Q，频率 523.25→261.63。signals／effect／document、modifier／Caps 来源与 AudioContext 节点依赖为显式自有桩，后一个释放探针只改变 getModifierState 桩、不冒称实际 modifier keyup 被执行；不是上游 Vitest、浏览器或硬件，没有复制参考代码／资产。

本应用范围音乐键位增量完整门禁实际通过：客户端 1,828 项零失败（约 361.57 秒），服务端 131 项零失败（约 1.39 秒）；可选十万词耐力实际执行并通过（38.836 秒），仅作文本引擎证据，不作音频设备压力证据。705 个唯一人工项审计、固定参考／元数据／原创性检查与未打开的应用打包通过，门禁确认未启动 Typebar 进程。默认 AppKit 注册 API 仅类型检查，测试注入安装／移除与修饰快照边界，调用真实监听回调和真实应用代理启动／激活／终止方法，但没有启动 app 或向 NSApplication.sendEvent 分发；真实设置按钮、字段编辑器、多窗口和实际终止拒绝／批准未实机验证。[Apple 事件监视文档](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html) 与安装 NSEvent.h 支持本地观察、主线程同步回调和显式提前移除；原样放行不是实际系统全局权限测试，嵌套菜单／拖动 tracking loop 本地 monitor 不接收，监听顺序／自动失焦丢事件仍是平台接入边界。22 项用真实未分发 NSEvent 对象检查事件身份与上下文，设备状态全部隔离，不因用户 CapsLock 改变而污染测试。

最多三轮会话内决策／风险复核（不是独立评审）：用 generation 先于注册发布和先于移除退休，过滤已停／失败／迟到回调；注册期间同步 stop 会移除后来返回的 token，同步 start 不重复，移除期间新注册不会被旧 stop 清掉，停止后的弱回调不保留 owner。监听器是应用代理的显式生命周期资源，要求 stop；不承诺活动 owner 任意丢弃时自动 deinit 移除。关闭单个窗口或被拒绝的终止不执行 willTerminate 清理，终止保护代码未改动。新增三项人工项，共 705 个唯一项，状态均未提升为实机已验收；归档／成绩／SwiftData 结构与 32 音型值不变。未启动 Typebar 图形实例，没有播放音频或写真实数据，完整 goal active。

2026-10-02 原生按键音符与随机音阶增量（最终门禁已通过）：固定 [声音实现](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/controllers/sound-controller.ts#L149-L355) 与 [音型定义](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/constants/sounds.ts) 后，将官方 8–11 命令接到四种原生键位波形，12–13 接到五声／全音音阶。用 A4=440 的等温律公式计算并舍入到两位小数，不复制参考频率表；经既有 ANSI 物理键适配器和自写钢琴自然音／黑键行算法覆盖 37 个物理键，基准第 3 八度，Shift 或 CapsLock 只提高一个八度，非映射键静音。按键音 0.5 秒／0.15 秒指数衰减，音阶 2 秒／0.3 秒指数衰减；起始增益为音量十分之一。使用自有 48 kHz 单声道 PCM 与 NSSound，没有 WebView／网页依赖或参考音频。

音阶先以严格小于 0.5 的随机抽样决定是否走一层八度，4–6 间折返，再均匀抽取该音阶的音；两个音阶及各自试听／练习状态独立，测试重置不清零音阶。已启动音乐持有独立初始增益／包络：样本全局调音量和 clearAllSounds 不更新／停止音乐，后续音符才采用新音量，静音启动的旧音乐不会随样本恢复音量复活。每个音符独立持有声音实例，完成／失败释放，迟到／同步回调不释放新音；不缓存无限音高原型。设备不可用为最佳努力，不改变输入／成绩；设备永久初始化失败通知、无完成回调故障、浏览器等价滤波／逐采样输出及主线程渲染压力仍待补证。

新增六个持久化音型值，保留全部旧 26 值及四系统／22 原创短音；被官方音乐命令替换的六个旧短音以 sound.nativeClick.* 扩展命令保留，官方 1–26／off 仍共 27 个入口。新候选原生选项共 32 个，不把原生扩展数当官方数量。所有旧音型快照解码及新值完整字段 JSON 往返通过；没有偏好域／归档字段／SwiftData 结构迁移或真实数据写入。旧二进制不认识新增 enum 值，跨二进制／回滚到旧版的归档读取不宣称已兼容：启用新值前的导出或恢复旧音型是回退边界，不同时运行新旧 GUI。

行为优先先新增 6 项、以兼容入口暂存旧行为，实测 22 个有效失败断言；修复后扩展为 MusicalClickSoundTests 21 项，相关 84 项零失败（约 2.06 秒）。真实 TypingInputView 无窗口事件核对先记录物理 E 键、再输出 Colemak 的 f，音高仍 E4；真实 NSSound 解码四个半秒波形及一个两秒音阶并保持未播放。另覆盖 37 键与高低范围、四波形命令、Shift／CapsLock、音阶音集合／千步边界／两抽样与独立状态、静音及样本隔离、256 个独立音乐请求、完成／启动失败／迟到回调和旧设置不重分配。256 仅桩实例压力，不是设备混音或十万词音频耐力。

本音乐增量完整门禁实际通过：客户端 1,806 项零失败（约 361.24 秒），服务端 131 项零失败（约 1.54 秒）；可选十万词耐力项实际执行并通过（38.502 秒），仅证明文本引擎，不作音乐设备压力证据。702 个唯一人工项审计、固定参考／元数据／原创性边界检查和未打开的应用打包均通过，全程没有 Typebar 图形进程。只读原版探针使用 bundled Node v24.19.0 擦除类型并执行实际 previewClick／playClick／playNote／playScale：四个预览 261.63 Hz、增益 0.05、衰减 0.15、0.5 秒停；37 映射键的修饰升八度检查通过，Space 不创建声音；两音阶固定随机序列得 C5→C6→C5→C4→C5、衰减 0.3、2 秒停，Howler 调零／stop 后旧 gain 仍 0.05。AudioContext、节点／设备、modifier 和随机均为显式桩，不是上游 Vitest、浏览器或设备实测；未将参考源代码或资产写进原生项目。

最多三轮会话内决策／风险复核（不是独立评审）：生命周期分离与缓存范围为必要合同，保留旧 enum／命令作为增量过渡；一次 Swift 6.2.4 编译因扩展测试 ID 数组表达式过长而超时，拆分等价表达式后正常，不当产品行为反例。AppKit NSSound 接口依据安装 SDK 26.2／macOS 14 目标；指数衰减与波形相位依据 [W3C Web Audio 定义](https://www.w3.org/TR/webaudio/#dom-audioparam-settargetattime)。主练习 keyDown／modifier 与两个试听调用点代码复核及编译通过，未操作真实按钮／设置窗／命令面板；尚未全局捕获其他文本框／回放页键位或复核 IME／自动动作音乐上下文。样本随机变体、16 号结束混响、首池 seek／排队仍未实现或对齐，主题、Unicode／Funbox／远程服务等既有缺口不关闭。新增三项人工场景，共 702 个唯一项但未提升实机状态；goal active，未启动 Typebar 图形实例或播放设备音频。

2026-10-02 全局样本声音音量与测试重置增量（最终门禁已通过）：固定 [声音控制器](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/controllers/sound-controller.ts#L302-L433)、[重置入口](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-ui.ts)、锁定 [Howler 2.2.3](https://github.com/goldfire/howler.js/blob/v2.2.3/src/howler.core.js) 和 [音量范围](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/packages/schemas/src/configs.ts#L173-L174) 证明：样本声音由全局音量影响当前和未来实例，零音量不是停止；重置会停止 Howler 声音而不卸载资源。原生独立新增有限 0…1 的全局设置；修改时更新活动副本、不重启，未来请求采用已配置音量而非旧视图快照。全局零仍允许请求以零音量播放，未结束实例可随恢复音量继续；失败时按有效全局音量决定蜂鸣，零音量不蜂鸣。未接入全局配置的旧独立调用仍保留原来的非正请求不播放及上限裁切，这是原生旧 API 兼容，不当作原版全局语义。

AppSettings 默认接入共享控制器，测试可只注入设备边界；声量 didSet、真实命令／快照应用／恢复默认同步现有播放，初始化用 defer 包含新建、已保存、损坏偏好返回路径。控制器持有的活动声音先快照并清空所有权／倒计时引用，再逐个停止，不依赖 stop 是否同步完成；资源原型缓存与全局音量保留。普通 reset 的拒绝守卫之后、结果重复及通过请求 ID／配置／未开始守卫的在线内容替换均接入 clearAllSounds；被拒绝的 reset／过期内容没有越过停音调用，未在普通完成、暂停或调音量时擅自增加停音。三个真实私有 SwiftUI 接入点已代码复核／类型检查，但没有执行真实按钮／窗口，不把模型守卫回归称作私有 UI 端到端证据。

先行 8 项出现 22 个失败断言，其中 21 个是有效音量／停音反例；另 1 个把既有偏好重新编码的字节顺序当成数据变化，在修正前也失败，不计产品反例。单独补证解码的全部 AppSettingsSnapshot 字段一致后，保留完整字段比较，不承诺既有初始化不重写 JSON 字节。最终本轮新增 14 项，FeedbackSoundVoiceTests 共 35 项；相关 98 项零跳过／零失败（约 0.46 秒），35 项约 0.08 秒。覆盖当前／未来音量、静音恢复、无效范围、真正命令／默认／恢复／快照路径、原型缓存保留、停止后不复活、完成／失败／迟到回调、同步停止与调音量完成、停止快照之后的新请求；临时 UserDefaults 域隔离并清理，未操作真实偏好域／数据库。归档结构、成绩、回放事件与 SwiftData 字段均不变。

本全局声音增量完整门禁实际通过：客户端 1,785 项零失败（约 360.97 秒），服务端 131 项零失败（约 1.38 秒）；可选十万词耐力项实际执行并通过（38.712 秒），不是十万次声音压力或音频设备验收。699 个唯一人工验收项审计、固定参考／原创性／元数据边界检查和未打开的应用打包均通过；门禁确认未启动 Typebar 进程。相关过滤本身不含十万词，耐力证据仅取本次完整门禁实际结果。

固定只读源码用 bundled Node v24.19.0 类型擦除／内存执行实际 setVolume、clearAllSounds、onTestRestart 和锁定 Howler 的全局 volume／stop、组 stop 路径。三个自有已播放节点由零变为 0.6，非法 2 保持 0.6；testPage／resultPage 重置各使三节点 paused／ended 为真、时间归零，设备 pause 桩共六次。首个探针仅等待不足的 microtask 时序，不取其未停止状态作原版证据；后续明确等待实际 clearAllSounds Promise 才采信。UI／节点／播放状态和设备依赖均是显式自有桩，不是上游 Vitest、浏览器或真实音频设备；没有复制参考代码／音频／数据进入原生项目。

最多三轮有界会话内决策／风险复核：全局值与副本生命周期是 MainActor 内存状态，无新持久化／服务协议或部署，不冒称独立评审。特别区分原版 8–13 号音型：四种按键振荡器与两种随机音阶走独立 AudioContext，其已生成 gain 包络不会被 Howler 全局音量／stop 管理；现有 26 个自有音型是结构候选与原创替代，尚没有精确重写这些音乐分支、按键音高／Shift／CapsLock 和结束混响，本轮不把它们当成已对齐。首池 seek／闲置复用、加载／排队时序、逐 UTF-16 单元和实时自动输入声音、实际多窗口／设备混音／系统音量及无完成回调故障仍保留。新增两项全局音量／重置和一项明确音乐实现缺口，人工清单共 699 个唯一项，不提升实机状态；94 配置键 91／2／1 是结构映射分区，不代表全部行为实现，主题与部分 Funbox 等缺口不关闭。未启动 Typebar GUI，完整 goal active；行为优先、源码驱动与根因调试决定反例范围，决策／风险复核和简洁实现保留残余差异。

2026-10-02 独立声音实例与倒计时重启增量（最终门禁已通过）：依据固定 [音频控制器](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/controllers/sound-controller.ts)、锁定 Howler 2.2.3 的 [并发播放／闲置池](https://github.com/goldfire/howler.js/blob/v2.2.3/src/howler.core.js) 与本机 macOS 26.2 SDK NSSound.h 的 NSCopying、异步 play、复制重置 currentTime 和主线程完成代理接口，独立修复缓存 NSSound 每次 stop 再 play 截断点击／错误音的问题。资源原型只加载缓存，每次播放创建独立副本、设置自身音量；MainActor 持有活动副本直到完成或启动失败，完成回调用弱引用与当前实例核对，重复／迟到回调不删除替代实例。倒计时仍按原版显式 stop 重启自己的旧提示，不截断点击／错误音；静音和非正／NaN 音量不加载或停止，错误／倒计时不可用保留蜂鸣回退，点击失败仍不影响输入。只接受真正独立的副本，不把原型当可重启播放器。

行为先行的有效 7 项测试复现 20 个失败断言，修正后通过；最终新增 FeedbackSoundVoiceTests 共 21 项，相关 81 项零跳过／零失败（约 0.29 秒），新 21 项约 0.03 秒。直接继承 NSSound 的初始夹具因系统类簇及并发约束未可靠拦截播放，其编译／崩溃／错误断言均不计产品反例，改为只注入音频设备边界，仍走真实控制器。补充结果比较曾把 result() 每次新建 UUID 误判为状态变化，3 个夹具失败不计产品红测；现仅规范化工厂 UUID、比较全部其他 Codable 字段。真实代码自动 LF／提交／tab 生成三路点击，hard 恢复生成四路并保留错误关闭后点击回退和成绩；覆盖所有 26／4／4 音色来源、音量独立、加载重试、不可用／别名副本、同步／迟到完成、所有者释放、倒计时替换和失败、256 个模拟并发且全部释放。22 种自有 WAV 与 12 种系统音的真实 NSSound 复制均证明对象／音量独立，其中 22 种自有 WAV 还检验了起点重置；它们仅构造／复制，未播放，不是设备或十万词音频压力验收。

固定只读源码用 bundled Node v24.19.0 类型擦除／内存执行实际 getHowl、playClick、playError、playTimeWarning，显式自有音频桩观测三次点击／两次错误均 seek＋play、零 stop，两次倒计时各 stop＋seek＋play。另仅在内存执行锁定 Howler 的真实闲置池路径，显式 HTML Audio 与池状态桩证明 256 个活动实例／唯一 ID 不被默认 5 个闲置回收额度截断；初始缺少 Audio 桩的池探针异常不计结果。未运行浏览器、上游 Vitest 或真实音频设备，未复制参考源代码／音频／数据进入原生项目。

本独立声音增量完整门禁已通过：客户端 1,771 项零跳过／零失败（约 360.29 秒）、服务端 131 项零失败（约 1.45 秒）；十万词耐力项实际执行约 38.62 秒，不冒称十万词声音压力。原创性／固定参考行为／元数据及 696 个唯一人工场景清单审计通过，未打开的原生应用打包通过；未启动图形实例。人工清单数量不代表设备验收数量。

最多三轮有界会话内决策／风险复核仅关闭已证明的“控制器缓存实例 stop 截断”缺陷，不冒称独立评审或全部声音对齐。原版无 ID seek(0) 会重定位池中首实例，默认池保留闲置对象、全局音量更新和 clearAllSounds 的完整语义仍待精确原生对齐；本轮不抹去这些差异，也不施加任意活动声音上限换取通过。设备调度／混音／音量听感、没有完成回调的故障、逐 UTF-16 单元回放声音、实时自动输入播音和完整视觉路径仍待验证／实现。没有 SwiftData 字段、持久化／服务协议、归档或成绩变更，没有部署、真实库写入或 GUI 启动。人工清单新增两项共 696 个唯一场景，均不提升为实机通过；原有配置 94 键 91／2／1、主题与部分 Funbox 等缺口保留，完整 goal active。行为优先与源码驱动技能决定证据边界，根因调试与决策／风险复核保留真实残余风险，简洁实现仅改音频控制器和测试。

2026-10-02 回放动作声音与预生成时间线增量（最终门禁已通过）：固定 [回放派生](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/replay-ui.ts#L50-L112)、[播放处理](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/replay-ui.ts#L163-L232)、[逐键验证](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/helpers/validation.ts#L13-L31) 与 [最终字段读取](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/events/data.ts#L225-L227) 表明：回放不按 automatic 静音，下一词首次输入额外派生前词提交动作，其正误取最终字段；普通分隔键按字段内位置判定，不把整词错误音提前塞到空格键。原生独立修正这些声音派生，保留现有词／字符删除跨度及每条机械事件；自动 tab 和遇错 word／letter／hard 恢复均在播放时间线派生相应声音动作。Zen 明确传递结果配置，自己的字符和提交视为正确；不猜空提示就是 Zen。

最终字段复用既有自有输入历史投影，保存进度算法原样复用提取后的机械状态；未新增持久化数据或改原始成绩。声音时间线仅对有限偏移准备有序瞬时快照，结果视图初始化时预生成，并在播放 50ms tick 用二分起点和当前窗口取声音，不每帧重扫完整历史。暂停／拖动的现有播放路由保持不变；音色、音量、错误音关闭后回退和关闭全部反馈继续用原有原生路由，不复制上游音频。事件为空的旧插入不消耗尚未播放的提交，同时间戳的独立退格不合并；marker 缺失的旧删词仍保留逐删除声音，不凭时间戳伪造来源。

新增 `ReplayActionSoundTests` 最终 17 项；先行 9 项产生 11 个有效失败断言，涵盖自动缩进三次点击、自动 word 一次／letter 两次删除点击、硬恢复的最终字段提交错误音、正常跨词、正确位置分隔键、过早分隔键和最终修改对早期提交的追溯影响。首版相关 56 项中，新 9 项通过，4 个旧声音预期冻结了自动静音或把提交音合并到分隔键，按实际原版执行结果更新，保留其输入／动作／区间断言。扩展 Zen 夹具一次遗漏 rules 的编译错误不计产品反例；后续 8 项是复核证据，不冒称先行 red。最终相关 208 项零跳过／零失败（约 22.71 秒），新 17 项约 0.10 秒；包含 2,000 词时间线共 7,998 条声音及百个窄窗查询、连续／分段边界不重播、上下文、非有限偏移隔离、空插入、正式归档／portable result、精确拼写和原始曲线／字段／成绩不变。此 2,000 词声音检查不等于十万词声音压力或设备流畅验收。

本回放声音增量最终完整门禁已通过：客户端 1,750 项零跳过／零失败（约 360.36 秒），服务端 131 项零失败（约 1.43 秒）；门禁中实际十万词耐力项约 38.66 秒，不冒称十万词声音压力。原创性／固定参考行为／元数据及 694 个唯一人工场景清单审计通过，原生应用打包通过但未打开；没有启动 Typebar 图形实例。人工场景数量不代表设备验收数量，独立重叠声音仍未修复。

固定只读检出用 bundled Node v24.19.0 类型擦除／内存执行实际 handleDeleteOnError、goToPreviousWord、getInputForWord／getInputFromDom、isCharCorrect、deriveReplayActions、handleDisplayLogic 和 playSound。自有 ab LF／tab 给出 LF、submitCorrectWord、automatic tab 三次点击；word／letter 恢复给出 error＋一／两次点击；word_hard 与 letter_hard 因最终前字段被清空／去掉提交，给出两个 error 后两次 click。错词中正确位置空格仍 click，下一词才 error＋click；过早空格 error，后来改正的前字段让早期提交改为正确；Zen 的实际验证／派生确认自己输入正确且有提交。输入／事件、词、索引和精简 DOM／音频计数依赖显式桩，部分输入记录由自有场景准备；没有运行完整 onInsertText、浏览器、上游 Vitest、声音设备或真实键盘／IME，不把探针当全栈验收。

迁移与最多三轮有界会话内决策／风险复核：旧／新结果结构及两种删除字段不变，无 SwiftData 字段、协议或归档版本变化，不回算保存的旧统计；重新生成旧回放的声音语义会修正，旧播放器仍有原先静音／分组限制，不声称跨二进制已验收。预生成快照是结果值的瞬时派生、无全局缓存和副作用，实际原生播放端已接入结果模式及快照窗口查询；未部署、未写真实库、未启动图形实例，不复用参考源码／数据／资产，不冒称独立评审。RPL-01 去掉过时的播放中自动缩进静音预期，新增两个待设备场景，人工清单增至 694 个唯一项。播放端风险复核另外确认：TypingFeedbackSound 对缓存 NSSound 每次 stop 后再 play，会打断同时间戳的重叠请求，独立声音播放仍是已知待修复项，不把它仅记为设备未验收。本增量仅关闭已证明的这些回放声音派生分支；逐 UTF-16 单元的声音／停止日志、半代理／跨事件融合、无来源 no-space 词索引、Firefox 弃字段、完整视觉回放、实时自动声音、设备、主题和部分 Funbox 缺口仍保留；94 配置键 91／2／1 不升级，整体 goal active。使用行为优先测试、源码驱动、根因调试、简洁实现及决策／迁移／风险复核。

2026-10-02 代码反缩进命令与消费游标增量（最终门禁已通过）：固定 [代码删除分支](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/delete.ts#L20-L57)、[前词导航](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/helpers/word-navigation.ts#L86-L117) 与 [回放动作](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/replay-ui.ts#L50-L112) 及 [播放处理](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/replay-ui.ts#L175-L232) 表明：代码 tab 清理后，普通退格保留前词、整词命令清空前词（不是整条上一行）；两者都先记录 word 动作，再记录 character 目的动作，未标 automatic。原生独立按命令恢复前词，保留更早词和原有逐字回放；新增可选 `characterDeletionCount` 表达字符日志对应的多条机械删除，不误标成 word。两条手动动作各响一次，首词清 tab 后也保留目的空动作，其全局文本已经为空，不删除更早输入。固定 [删除守卫](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/before-delete.ts#L15-L73) 的最大信心仍阻止手动删除；on 信心在当前 tab 非空时按固定守卫允许此导航。

消费端复核用真实完成会话发现，弱点练习忽略自动 tab／错误恢复删除会产生游标错位，把一次错误归到多个字符。现在所有机械事件维护输入游标，只有非 automatic 输入计入人工尝试、错误与节奏；已有精确身份用于弱点错误判定，避免规范等价错拼被漏记。慢字符／人工 forced error 断言保留，旧夹具把 automatic x 完全当作没有输入的假设已修正为自动前缀推进游标、人工下一字出错，不把自动前缀计作人工样本。旧成绩快照不回算；重新生成的弱点报告可能纠正旧游标／身份错误，不能声称所有派生显示保持不变。

新增 `CodeUnindentDeletionTests` 最终 16 项。首轮 7 项有 22 个失败断言，其中两个完成／结果断言依赖错误的 5 词预算夹具（实际 4 词），不计产品反例；20 个为目的文本／动作／手动声音等有效先行失败。首次产品改动后相关 26 项有 6 个失败：上述两个预算夹具，以及四个旧预期分别冻结了只删 LF、两处省略首词目的日志、手动删除标 automatic，均按实际原版证据校正，不跳过回归。消费者又有 3 个独立有效先行失败（自动 tab、word、word_hard），规范等价弱点漏记另有 1 个，累计 24 个有效先行断言；后续迁移／边界扩展不是 red 证据。首版相关 212 项零跳过／零失败（约 29.32 秒），最终相关 238 项零跳过／零失败（约 29.56 秒），新 16 项约 0.07 秒。覆盖所有代码语言、confidence、错误残余 tab、禁用反缩进、空前字段／首字段、Unicode 前词恢复重打完成、不开窗 NSResponder、正式归档、上一版读者、新旧缺省字段、双类型／嵌套／超限跨度降级以及空目的动作的 seek／曲线／保存进度。人工场景增至 692 个唯一清单，仍不是设备验收。

本代码反缩进增量最终完整门禁已通过：客户端 1733 项零跳过／零失败（约 359.87 秒）、服务端 131 项零失败（约 1.38 秒），固定参考／原创性和兼容审计、692 个唯一人工场景清单、未开窗 macOS 应用包检查全部通过。显式十万词用例实际执行约 38.61 秒；相关过滤不含该用例，耐力证明来自最终全套运行。人工清单通过不是设备验收；最终代码验证之后只更新文档，不与编译交错编辑 Swift。

只读固定检出由 bundled Node v24.19.0 执行实际 onBeforeDelete、onDelete、goToPreviousWord 与 deriveReplayActions。自有 seed／ab LF／tab 目标中，word 命令回到 ab 字段并清空，普通命令保留 ab；多余残留 tab 则仅普通退格，不触发整段清理；on 可达、max 阻止、关闭选项不导航、首字段仍有两条事件。回放派生为 setLetterIndex＋backWord（首字段两条 setLetterIndex），源码显示两者各有点击。输入值／假前导空格、历史、索引、词、UI 和事件依赖显式桩；不是完整上游 Vitest、浏览器／设备或真实 IME 验收。backWord 视觉路径未重新应用目的字段 inputValue，原版视觉回放与 DOM 目的文本的一致性仍待独立验收；本增量不声称完整视觉回放等价。

迁移及最多三轮有界会话内决策／风险复核：保留此前 word 字段及机械事件语义，新 character 字段 nil 缺省且不编码；旧读者忽略它仍恢复文本，但该动作拆成多次点击，不冒称跨二进制或真实库迁移已验收。新旧字段不能同时标记一组，混合类型／自动标志／偏移、嵌套、非删除、负数／零／超限均逐组降级，不丢机械事件；首字段空目的日志经所有文本消费者检查不越界。portable result／正式归档保留动作类型和声音。无 SwiftData 字段或外层归档版本变更，不写真实库、不部署、不启动图形实例，不复用参考源码／数据／资产，不冒称独立评审。仅关闭本次已证实的代码目的文本、手动标志与动作声音缺口；原版视觉回放、自动事件声音、逐 UTF-16 单元／半代理、CRLF／词界融合、设备、主题及部分 Funbox 等缺口仍保留；94 配置键 91／2／1 状态不升级，整体 goal active。使用行为优先测试、源码驱动、根因调试、简洁实现及决策／迁移／风险复核。

2026-10-02 整词删除动作回放增量（最终门禁已通过）：固定 [删除日志](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/delete.ts#L11-L91)、[自动删除](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/insert-text.ts#L66-L131) 和 [回词导航](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/helpers/word-navigation.ts#L98-L138) 把一次普通整词删除记录为一条动作，而原生逐字符机械回放会产生多个删除点击。原生独立增加可选 `wordDeletionCount`：保留每条原有 insert／delete 及其文本语义，仅在实际整词动作的首条机械删除注明跨度。动作投影暴露真实分组，播放声音只响一次；字符退格即使同时间戳也不合并。word 自动删除保持一组，word_hard 在下一词首键失败时保持两组；no-space 已知词界及普通代码退格的 tab 组／换行分离。回放字形和错误音同时采用已有精确文本身份，不把规范等价拼写自动视为正确。

新增 `WordDeletionActionTests` 最终 16 项。先行 9 项有 10 个有效失败断言；首版相关 161 项零跳过／零失败（约 3.12 秒）。补充 7 项动作／迁移复核不是先行失败证据；复核相关 168 项中代码夹具有 4 个错误断言：两个多余 tab 的普通退格不应触发整段反缩进，纠正为一个多余 tab，不更改产品来迁就夹具。扩展相关 225 项零跳过／零失败（约 23.63 秒），包括新 16 项约 0.02 秒；随后源码探针发现代码整词反缩进的既有目的文本缺口，限定新测试只证明普通退格分组，不把错误现状写成原版等价断言。新增三个人工场景到 690 个唯一清单，均待设备验收。

本增量最终完整门禁已通过：客户端 1717 项零跳过／零失败（约 357.97 秒）、服务端 131 项零失败（约 1.38 秒），固定参考、原创性和兼容审计、690 个唯一人工场景清单以及未开窗 macOS 应用包检查全部通过。显式十万词用例实际执行约 38.41 秒；相关过滤不含此用例，只有最终全套证据才证明耐力执行。人工清单通过不是设备验收；最终源代码验证之后仅更新文档，不与编译交错编辑 Swift。

只读固定检出中用 bundled Node v24.19.0 的类型擦除／内存上下文执行实际 onDelete、goToPreviousWord 和 handleDeleteOnError：普通当前／前词清理各一条 word 事件；自动 word 一条、word_hard 两条 automatic word 事件；代码普通退格先记 tab 的 word 事件，再记前行去掉 LF 的 character 事件。代码整词删除则把前行清空，原生目前只去掉 LF，仍是未修复的目的文本缺口，代码自动标志／声音也未等价，不因分组而升级。DOM 假前导空格、输入历史、活动索引、词和 UI 依赖显式桩；不是完整上游 Vitest、浏览器或真实键盘／IME 证据。

迁移／有界会话内决策及风险复核：新字段缺省 nil，编码不输出 nil；旧事件不凭相同时间猜测动作。模拟旧解码器忽略新字段，仍逐条还原相同输入，但旧播放器依旧多次点击，不声称跨二进制已验收。新记录经 portable result／正式归档往返保留分组；负数、零、超限、混合自动标志／偏移、插入、嵌套和非法字段跨度逐组降级，不丢机械事件或声音。marker 对文本、seek、字形、性能曲线及保存进度没有影响；精确身份修正会改变重新生成的旧回放错误显示／声音，旧统计快照不回算。无 SwiftData 字段或外层归档版本变化，无真实库写入；未复制参考源码／数据／资产，不开启 GUI、不部署，不冒称独立评审。保留逐 UTF-16 单元／半代理、无来源词界融合、CRLF、代码整词反缩进、设备、主题及部分 Funbox 等缺口；94 配置键 91／2／1 不升级，整体 goal active。使用行为优先测试、源码驱动、根因调试、决策／迁移和风险复核。

2026-10-02 手动词回改边界增量（最终门禁已通过）：固定 [删除前守卫](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/before-delete.ts#L15-L73)、[删除事件](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/delete.ts#L11-L91) 与 [回开前词](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/helpers/word-navigation.ts#L98-L138) 以实际拼写保护正确已提交词。原生普通词回改改用已有精确身份，规范等价但不同拼写的错误词不再被锁住；有来源的安全 no-space 词界参与手动退格／整词删除，整词删除只清当前词或经守卫允许回开的前词，不再沿空格扫描清掉整个扁平历史。历史尝试错误不解锁已经正确重打的词。confidence on 禁止跨词回开、max 禁止手动删除，freedom 允许正确词回开；固定 [设置覆盖](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/config/metadata.tsx#L465-L558) 证明正常 freedom／confidence 互斥，保留既有配置规范化，不把人为冲突运行态当正常用户反例。

新增 `WordBoundaryDeletionTests` 最终 17 项；首轮 14 项有 45 个有效先行失败断言，无编译／非法组合夹具错误。首版相关 174 项零跳过／零失败（约 2.31 秒），有界复核补旧长度词界、实时切换和百词后回开，最终相关 243 项零跳过／零失败（约 3.25 秒），新 17 项约 0.04 秒；本过滤不含十万词，不据环境变量声称耐力已执行。最终完整门禁通过：客户端 1701 项零跳过／零失败（约 357.73 秒）、服务端 131 项零失败（约 1.38 秒）、固定参考／原创性及兼容审计、687 个唯一人工场景清单和未开窗应用包检查全部通过；显式十万词实际执行约 37.83 秒。涵盖预组合／分解／重排／Angstrom 错误词回开、正确词和纠正后的保护、no-space 当前／前词清理、confidence／freedom、空目标 Morse 屏障、旧长度元数据、真实 factory／重复／百词续读、回放／正式归档及不开窗原生 NSResponder 删除命令。两个人工场景增加到 687 个，仍待设备验收。

固定原版实际 onBeforeDelete、onDelete 和 goToPreviousWord 在只读检出的 Node v24.19.0 内存探针执行：é 对 e＋重音错误词允许回开且保留 é；正确 ab 的 no-space 回开被拒，ab／cx 的整词回开和 ab／c 的当前词清理都保留 ab；confidence on 拒绝错误前词回开，合法 freedom off-confidence 允许正确前词清理。DOM 值／假前导空格、事件历史、UI 与活动索引依赖显式提供，不是完整浏览器、上游 Vitest、物理键盘或设备证据。原版守卫在冲突 max＋freedom 状态的优先序也观察到，但正常设置互斥，未改变导入／实时设置政策。

迁移／有界会话内决策和风险复核：复用既有真实词界、自动删除机械动作与逐删除回放格式；无字段、配置、结果、回放、归档或 SwiftData 版本变化，不写真实库、不回算旧快照。不伪造已丢失的词界，不关闭无元数据融合、不同 UTF-16 长度的错误输入导航、逐单元视觉替换／停止／删除恢复、整词删除的原版事件粒度、半代理／CRLF、原版滚出 DOM 的前词可用性、IME／设备缺口。自动硬删除、代码反缩进和空目标屏障由相关回归保留；新增人工场景只是清单，不是设备验收。未启动 GUI、不部署、不复用参考代码／数据／资产，Morse／Under／Backwards 及 94 配置键 91／2／1 的部分状态不升级，整体 goal active。使用行为优先测试、源码驱动、根因调试、决策／迁移／风险复核，不冒称独立评审。

2026-10-02 输入文本精确身份增量（最终门禁已通过）：固定 [输入拆分与验证](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/insert-text.ts#L133-L374)、[显式视觉替换](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/utils/strings.ts#L289-L351)、[精确词判定](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/helpers/validation.ts#L13-L98) 与 [难度／完成](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/helpers/fail-or-finish.ts#L48-L141) 不把 Unicode 规范等价自动加入替换表。原生独立比较实际 Unicode 标量／UTF-16 拼写，去除 Swift Character／String／Set 的规范等价泄漏；输入、错误显示、描述统计、词历史、提交守卫、难度与组合完成预判共用精确身份。已有 UTF-16 尝试统计不重复实现，明确允许的标点、空格、俄语替换及源准备 NFC 规则保持不变，Zen 保留自己的输入。

新增 `InputTextIdentityTests` 最终 21 项。首轮夹具遗漏 rules 的编译错误不计产品反例；校正词停止保留分隔符后，13 项有 123 个先行失败，其中 12 个来自整字符 no-space 停止夹具，不能证明原版逐单元语义，已弃用而不计缺口证据；其余 111 个为有效先行断言。首版相关 68 项有 1 个词历史夹具失败：正确重打不抹掉历史尝试错误，已保留历史并增加正确字形断言，不改产品迁就夹具。扩展相关 206 项零跳过／零失败通过（约 1.42 秒），初始有界复核 18 项通过（约 0.04 秒）；相关过滤不含十万词，不能据环境变量声称耐力已运行。覆盖预组合／分解重音、组合标记顺序、Angstrom、普通／custom 最终词、master／expert、同宽 no-space 提交、停止／删除错误、明确替换、quick-end、Zen、预判、纠正、回放及正式归档。固定原版实际 normalizeData、isCharCorrect、shouldGoToNextWord、难度／完成函数以及 onInsertText 在只读检出中用 Node v24.19.0 内存运行：自有 é 对 e＋重音保留原始错误输入，master 失败、expert 提交失败、word 停止保留错误分隔符、letter 停止拒绝、两类删除记录自动事件。输入 DOM／事件缓存、导航、UI 和 before-insert 守卫依赖显式桩；不是完整上游 Vitest、浏览器或真实 IME／设备证据。

随后第三次有界复核运行原版实际 onInsertText：自有规范等价重排 a＋两种重音＋末组合标记的四个单元判定为 true／false／false／true，master 仍 active。新增 3 项终端边界产生 3 个真实先行失败；独立引擎沿用已有准确率单元比较，仅把 master 终端检查改为最后单元，保留整字符的错误诊断。累计有效先行失败 114 个。最终相关 238 项零跳过／零失败通过（约 2.52 秒），包括已有 master／batch 测试；逐单元停止／删除恢复仍不关闭。首轮完整门禁客户端 1681 项零失败（约 358.20 秒）、服务端 131 项（约 1.42 秒）、685 场景清单及不开窗包通过，十万词实际约 37.89 秒，但在随后 master 修正之前，不替代最终门禁，最终完整重跑已通过：客户端 1684 项零跳过／零失败（约 357.50 秒）、服务端 131 项零失败（约 1.39 秒）、固定参考／原创性及兼容审计、685 个唯一人工场景清单和未开窗应用包全部通过；最终十万词实际执行约 37.84 秒。人工清单通过不是设备验收，早期门禁和失败夹具不混为最终证据。

迁移／有界会话内决策及风险复核：无字段、协议、回放、归档或 SwiftData 版本变化，不写真实库、不回算保存的旧统计；重新生成的回放字形／词诊断采用精确身份，不能声称所有历史派生显示毫无变化。原生仍以完整书写簇接收输入，这里不关闭不同 UTF-16 长度的游标、逐单元视觉替换／停止恢复、半代理、跨词融合／CRLF、完整 no-space 计数／历史、真实 IME 和设备缺口。未启动 GUI、不部署、不复制参考代码／数据／资产，人工清单待设备验收；Morse／Under／Backwards 部分状态和 94 配置键 91／2／1 分区不升级，整体 goal active。使用行为优先测试、源码驱动、根因调试及迁移／决策／风险复核，不冒称独立评审。

2026-10-02 引语融合续词与初始控制信号增量（最终门禁已通过）：复现 no-space 引语丢失安全书写簇词界后卡在第 102 个已生成词的问题。独立引擎在无分段元数据时，不再用零词索引判断预读预算；仅当实际可见前缀耗尽才请求一个新目标，正常安全词界仍按原有逐词窗口处理，空目标屏障仍先阻止扩展。没有把未知词界伪造成偏移或逐词历史。初始和续批时失去元数据的限定连续输入均可完成原始词池，实际目标、重复、回放与归档保持一致。

按固定 [初始化信号](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L475-L542)、[生成时控制符检测](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L721-L730)、[后续补词](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L571-L659) 和 [Return 守卫](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/before-insert-text.ts#L38-L40)，拥有原始池的引语只使用“选中原始源控制符＋实际初始生成控制符”的信号；在最终提交裁切之前记录，后续消息变换新造 LF 不改变信号。仅一个消息末词即使显示时移除 LF，初始信号仍为真；raw 未来 LF／Tab 保持可用，未选中源不泄漏，重试清理并重新记录初始生成信号。非引语及已准备外部流保留既有动态行为，Zen 原有规则不改。这是固定参考的可观察时序，不暗中把原版后续 LF 的拒绝规则改成另一个产品行为。

新增 `QuoteBoundaryContinuationTests` 16 项。先行 11 项有 128 个失败断言，其中 no-space 与 toPush 不兼容的夹具不计合法窗口证据；按固定组合规则改为合法的 uppercase／doubled／rot13，并补裁切前信号后，12 项有 137 个有效先行失败，无编译夹具错误。实现后 49 项通过；扩展相关 201 项零跳过／零失败通过（约 32.72 秒），最终有界风险复核 16 项通过（约 0.62 秒）；相关过滤不含十万词测试，不能凭环境变量声称耐力已执行。最终完整门禁通过：客户端 1663 项（零跳过／零失败，约 354.66 秒）、服务端 131 项（零失败，约 1.40 秒）、固定参考／原创性与兼容审计、683 个唯一人工场景清单及未开窗 macOS 应用包全部通过；本次显式十万词实际执行约 37.61 秒。清单通过不是设备验收，先行失败与夹具错误不计最终绿灯。覆盖超过百词连续／分次完成、纠错重开、晚期无效源的输入时间及重试、正式成绩／归档、Jamo／区域指示符／ZWJ、后续消息 LF、初始最终 LF 裁切及不开窗原生 Return 路由。固定原版 Words、addWord、控制检测及 before-insert 实际片段在只读检出的 Node v24.19.0 内存探针运行：未来 tail LF 显示时初始信号仍 false 且 Return 被拒；最终 ab LF 裁切后信号仍 true。原版 nospace 提交判定／addWord 的自有 205 词驱动完成全部提交与生成，拼接目标一致。依赖显式提供；首个控制探针缺少局部 quote 绑定的 ReferenceError 不计产品红测，修正后才取证。没有完整 getNextWord／上游 Vitest／DOM／物理键盘或设备证据。

迁移／风险边界：仅未来练习运行态计算改变，新增布尔量属于值拥有的生成游标，不是持久字段；无设置、成绩、回放、分享、归档或 SwiftData 格式／版本变化，不重算旧快照和源偏移、不写真实库。不声称未分段状态的逐词计数／历史／突发速度、分次跨词界融合／半代理／IME 与完整 UTF-16 导航等价，全部 Funbox／标点／数字、完整英式词典、原版重选模态／异步 UI、真实设备仍开放。使用行为优先测试、源码驱动、根因调试和有界会话内决策／迁移／风险复核，不冒称独立评审；未启动 Typebar 窗口、不部署、不引入参考代码／数据／资产，Morse／Under／Backwards 部分状态及配置 91／2／1 分区不升级，goal active。本条只取代此前已列两个风险的上述机制缺口，不宣告完整引语等价。

2026-10-02 引语按需生成增量（最终门禁已通过）：独立 `QuoteWordStream` 保存自有原始词池。按固定 [初始预算](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L428-L491)、[逐次补词](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L571-L659) 和 [全源控制符](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L721-L730)，默认首批 100 词；showAll 展开全部，toPush 1–4 优先覆盖。实际向前提交才补一个词，重开旧词不重复抽样，最终非空词只移除一个字面提交标量。初始前词用变换后的 raw，后续用去提交后的 text；随机大小写重复练习从同一原始池重新抽样。进度以整池总量显示，不以当前缓冲量代替。Return／Tab 的能力检查实际选中词池和已生成提示，未显现控制符不误触快速重启，未选中的原文／备用文不泄漏到重试或快捷键。

验证阶段：新增 `QuoteStreamingTests` 29 项；最初 20 项有 43 个有效失败断言，首版相关 85 项通过。会话内有界风险审查增加重复抽样、末词进度与 Unicode 融合反例，发现并最小复现 1 个真实错误时钟，沿补词链传输入时间修正。相关 174 项阶段仅 1 个旧夹具仍要求全量初始 Under 引语，按固定首批规则更新而保留全量完成与计数／错误断言。未来换行另有 1 个真实先行失败，已接入全源能力及不开窗原生按键测试；其后 46 项阶段仅 2 个命令面板快捷键夹具断言失败：错误地选择 Tab 快速重启却要求 Esc 快速重启下的 Shift-Tab，按实际快捷键政策更正，不改产品迁就夹具。相关 185 项首次零失败通过（约 32.24 秒）；最终复核区分“允许换行”与“源含换行”，避免改变 Zen 卷带显示，调整后的相关 185 项零跳过／零失败通过（约 32.12 秒）；完整门禁待执行。该过滤不含十万词测试，不能由环境变量声称耐力已执行。首轮完整客户端 1646 项（约 331.99 秒）有 3 个旧语言目录夹具断言失败，均要求超过百词引语初始完整呈现；已按固定规则增加默认首批、showAll 全量及完整输入后原文／完成／零错误验证，保留 376 个可用语言和全部长度覆盖。首轮十万词实际执行通过（约 37.15 秒），但服务与打包尚未执行，该失败门禁不计通过；随后语言目录及新增引语复验 30 项零跳过／零失败通过（约 56.26 秒）；第二轮完整门禁通过：客户端 1646 项零失败（约 354.22 秒）、服务端 131 项（约 1.40 秒）、681 场景清单及不开窗应用包。之后复核发现全源控制符范围错误地合并了未选中原文；实际 getQuoteWordList 内存探针确认只检查选中池，新增 1 项产生 6 个真实失败后修正。此前完整绿灯不作最终修正证据；修正后的 37 项定向零跳过／零失败通过（约 0.18 秒），包含最终 29 项引语游标测试及原生 Return；第三轮最终完整门禁通过：客户端 1647 项（零跳过／零失败，约 354.12 秒）、服务端 131 项（零失败，约 1.42 秒）、固定参考／原创性与兼容审计、681 个唯一人工场景清单及未开窗 macOS 应用包全部通过；本轮显式十万词实际执行约 37.45 秒。清单通过不是设备验收，中间失败与修正前完整绿灯保留但不计最终修正证据。阶段失败不计最终通过。固定原版 getLimit、Words.push、getQuoteWordList 与英式 replace 在只读检出的内存探针运行，Node v24.19.0，依赖显式提供；没有完整上游 Vitest／DOM／异步 UI／设备证据。

迁移与边界：仅未来练习生成和活跃引语进度改变，无设置、成绩、回放、分享、归档、SwiftData 字段或版本变化；旧成绩快照不重新生成、原文及偏移不回写。已有英式有限 14 家庭不等于完整字典；全部标点／数字／Funbox 组合（含后续新造控制符与原版初始化信号范围）、原版初始化三次重选及错误模态／异步显示、Unicode／半代理／CRLF 导航、真实 IME／设备仍开放。Morse／Under／Backwards 部分状态及 94 配置键 91／2／1 分区不升级。使用行为优先测试、源码驱动、根因调试及有界决策／迁移／风险复核，不冒称独立评审。不写真实库、不启动 GUI、不部署、不引入参考代码／数据／资产；整体 goal active。本条仅取代此前已列引语初始预算、后续前词提交和延后空候选机制缺口，不宣称完整引语等价。

2026-10-02 英式逐词生成增量（最终门禁已通过）：依据固定 [逐词转换](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/british-english.ts#L5-L67)、[English 门控及备用引语绕过](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L381-L399)、[前词清理](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L815-L823) 和 [变换顺序](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L946-L977)，接入独立 `BritishEnglishPolicy`，由 `GeneratedWordChunk` 和段游标共用，先 lazy、后英式、再 Funbox、最后提交。普通引语、词数／计时、自定义 pipe／非 pipe、顺序续批、长原文续批和外部词源进入该生成阶段；非空备用引语不再替换，美式与非 English 源不启用，Wordle／Pig Latin 不因内容像英文而误启用。现有拼写选择器对 13 个实际 English 源身份可用，未创建新设置。

拼写家庭是独立编写的有限 14 个普通词形，覆盖自有词库中的常用拼写及 tire／tyre 上下文；没有导入、翻译或打包参考替换表、词库、引语或代码。未知词不猜测转换。ASCII 双引号改单引号、连字符空组件保留、ASCII word 边缘／内部字符、首字母与全大写规则保留；引语例外使用已经 Funbox 变换的前词，按限定标点去除和小写处理，单引号／下划线／换行不会被当成可删除标点。规则覆盖不等于完整词典等价；新增引语无备用源的通用机制，但完整替换表覆盖仍开放。

新增 `BritishWordGenerationTests` 28 项。初始 20 项夹具的边界 trim 与短原文调用问题已更正，修正后的先行阶段有 45 个有效失败断言；夹具错误不计产品缺口。首轮实现相关 48 项通过；扩大后的 140 项阶段有 1 个消息词末标点夹具失败和 1 个默认耐力跳过，不计完整通过。最小复现定位到夹具缺少句号；改成实际词末标点输入后单项通过，不改产品实现迁就预期。最终相关 142 项零失败通过（约 64.96 秒），显式十万词实际执行（约 37.16 秒）；最终完整门禁通过：客户端 1618 项（零跳过／零失败，约 307.34 秒）、服务端 131 项（零失败，约 1.45 秒）、固定参考／原创性与兼容审计、679 个唯一人工场景清单及未开窗 macOS 应用包全部通过；本次显式十万词实际执行约 37.22 秒。清单通过不是设备验收，失败／跳过阶段保留但不计最终通过。本条取代此前逐词机制完全缺失的限定结论，不把有限规则升级为完整词典等价。覆盖实际 factory 输入完成、改变词长后的 no-space／Under／Morse 目标、逐词前序、百词续接、超过一万字原文续批、源字段进度映射、重复、便携记录与正式归档。固定原版 replace 实际函数及其表只在只读参考检出的内存探针运行，Node v24.19.0；模式和 capitalization 依赖显式提供，未运行完整上游 Vitest／DOM／设备，不把探针当应用验收。

迁移／有界会话内决策及风险审查：只影响未来提示生成，不改设置、成绩、回放、分享、归档或 SwiftData 格式／版本，不回算旧成绩或源偏移；原文源仍不被写回成英式目标。完整词典、百词后引语异常／前词提交边界、全部原始换行与 Unicode／半代理导航、混排源门控、真实选择器／IME／设备仍需补证。Morse／Under／Backwards 部分状态及配置映射计数不升级；不写真实库、不启动 GUI、不部署，人工场景清单不是设备验收；整体 goal active。

2026-10-02 英式备用引语增量（最终门禁已通过）：固定 [备用源选择](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L570-L599)、[跳过再次拼写替换](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L381-L399)、[空候选错误](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L901-L916)、[生成失败终态](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L350-L367) 和 [LF 提交](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L990-L999) 确认：非空 `britishText` 直接拆 ASCII 词池，不套普通引语清理；缺失／空字符串回退普通文本。原生 `OfflineQuote` 增加非持久可选备用源，现有 `englishVariant` 接入真实 factory；新增原创 Colour study 美式／英式配对，可从原有目录选择。原文、长度／搜索／收藏／评分身份不切换。普通源处理、已准备外部源与自定义源保持独立。

新增 `BritishQuoteSourceTests` 17 项。模型仅加无行为字段后，首批 14 项有 47 个有效先行失败；选择接入后还有 1 个真实 CRLF 提交失败。已用末 Unicode 标量判断 LF，不让 Swift 将 CRLF 书写簇误判为非 LF 并追加空格。后续内存旧／新成绩夹具的类型名编译错误不计产品红测。最终相关 93 项零失败通过（约 0.63 秒），最终完整门禁通过：客户端 1590 项（零失败，约 305.55 秒）、服务端 131 项（零失败，约 1.39 秒）、固定参考／原创性与兼容审计、677 个唯一人工场景清单及未开窗 macOS 应用包全部通过；显式十万词耐力已实际执行，约 37.43 秒。清单通过不等于设备验收，失败阶段不计通过，本轮没有启动 Typebar。涵盖美式、缺失／空备用源、字面省略号与限定原始标量、CR／CRLF／LF 目标结构、非英语元数据选择、无二次替换、无效 ASCII 空字段、反序／大小写／Under／Morse、重复、回放／便携结果、正式归档及内存 SwiftData 新旧记录共存。

已在内存执行固定 `getQuoteWordList` 和 `appendCommitCharacter` 的实际函数，使用已安装 Node v24.19.0，依赖只为显式的配置／选择／loader／nospace 桩；独立文本证明美式／英式／空字符串分支、双 ASCII 空格产生空候选和 CRLF 提交差异。不是完整上游 Vitest、DOM、重试 UI 或设备证据。选中的无效短备用词池显示生成错误并禁用输入，不降级成普通源；该会话没有开始、结果或可保存成绩，重复仍保留错误。这里只关闭所列短源错误语义，不声称原版随机初始化三次重抽、长引语在百词后的错误时机或模态呈现已等价。

风险／迁移复核限定未来引语生成，不改结果、回放、设置、分享、归档或 SwiftData 格式／版本；旧英式结果按快照保留，不回算历史。引用源元数据与反馈 ID 保持原文身份；搜索只查原文／标题，不把备用文本另当引语。仍开放无备用源的通用英式词替换／前词例外、原始内部换行的全部字段导航、半代理／融合词界、长引语预取、网络备用字段、初始化恢复 UI、全部组合与设备。Morse／Under／Backwards 部分状态不提升；不写真实库、不部署或开 GUI。进行了有界会话内反例审查，不冒称独立审查；整体 goal active。


2026-10-02 最终门禁（Morse 空目标词）：客户端 1573 项（零失败，约 304.95 秒）、服务端 131 项（零失败）、固定参考／原创性与兼容审计、675 个唯一人工场景清单及未开窗 macOS 应用包全部通过。显式十万词耐力已实际执行，约 37.11 秒；不据此声称十万空词或全部 Unicode 已验证。新增 21 项、最终相关 153 项通过；首轮完整测试的 2 个失败及更正的旧字面分词夹具保留阶段性质，本条替代对应本轮最终“待执行”。不提升 Funbox 部分状态，不把人工清单检查当作设备验收；仅当前会话状态变化，无真实库、历史回算、GUI 或服务部署，goal active。

2026-10-02 Morse 空目标词增量（最终门禁已通过）：固定 `input/helpers/util.ts`、`validation.ts`、`handlers/before-insert-text.ts`、`handlers/insert-text.ts`、`helpers/word-navigation.ts` 与 `helpers/fail-or-finish.ts` 确认：逐词变换后的空目标没有可触发无空格提交的末字符，不能自动跳过或用后续词字形完成。使用已安装的 Node v24.19.0 在内存中执行只读固定 util／validation 的纯函数；ASCII 探针的 space／Funbox／Config 依赖明确提供，不是完整上游 Vitest、DOM 或设备证明。原生独立保留安全拼接批次中的空词身份，缓存首个空字段，错误输入留在该字段，不计后续词数／正确词信用，不自动完成或越过空字段预取；段进度改用会话内的逻辑词结束序号。

新增 `EmptyNoSpaceTargetTests` 21 项。首批 14 项 64 个失败中有 1 个 AFK 夹具预期错误，63 个为有效先行失败；夹具编译错误不计产品红测。持续输入夹具保留原 AFK 判定，19 项阶段与相关 90 项通过；呈现归属补测 2 项另有 7 个有效先行失败，137 项阶段通过；首轮完整客户端 1573 项有 2 个失败（约 305.35 秒），该轮不计通过且未进入服务端／打包。最小复现旧 `CustomLiteralDelimiterTests` 的 2 个空词元数据断言，按固定输入契约改成精确空词及结束位置断言，融合字形拒绝不变。最终相关 153 项（零失败／零跳过）通过，最终完整门禁已通过，前述失败阶段不计通过。覆盖首／中／末／连续／全空词、ASCII 二十 UTF-16 单位字段限制、四种自定义完成、pipe／非 pipe 段进度、百词续批、软／硬删除、letter／word-stop、master／expert、删除恢复、接受事件进度、重复、回放／便携结果及空词呈现归属。空词不伪造占位目标或提交键，普通融合书写簇仍拒绝不安全词界。

本条只取代已列安全 Morse 空目标词的输入与呈现模型缺口，不升级 Morse／Under／Backwards 的部分状态。拒绝输入的字段历史、原文／其他词池所有路径、任意 Unicode／半代理／融合词界、实际 DOM 行高阻挡、空字段原生光标布局／IME／实体键盘与设备仍开放。新增状态仅在当前会话内，结果／回放／设置／归档／库版本不变，不回算旧成绩或进度，不写真实库，不运行 GUI；旧二进制降级未实测。进行了有界会话内兼容性／迁移／风险反例审查，不冒称独立审查。goal active。


2026-10-02 原文有限练习增量：全部目标生成后，不再要求非空末词的单个空格／LF 提交；最后空行槽仍需 LF，中间块不提前结束，保存原文及偏移不裁切。新增 9 项；客户端 1552／服务端 131 项零失败零跳过、显式十万词、673 项人工清单与未开窗打包验证通过，未启动 Typebar。清单不是设备验收，完整重写仍未完成，goal active；证据与剩余边界见 [输入审计](OFFICIAL_INPUT_AUDIT.md)。

2026-10-02 本轮已验证：新增 22 项长文本输入历史进度证据；客户端 1543／服务端 131 项零失败零跳过、实际十万词耐力、671 项人工场景清单及未开窗打包检查通过。未启动 Typebar，不回填旧数据；清单不等于设备验收，完整重写仍未完成，goal active。源码依据与剩余功能见 [输入审计](OFFICIAL_INPUT_AUDIT.md)。

2026-10-02 长文本空行增量：明确保存的原文长文本现保留纯 LF 块、末页恢复与匹配空槽进度，Tab 不再拆成进度词；现有原文、字段和历史不回算。新增 13 项证据及边界见 [输入审计](OFFICIAL_INPUT_AUDIT.md)；客户端 1521／服务端 131 项零失败零跳过，显式十万词、669 项人工清单及未开窗打包检查通过。未启动 GUI；清单不等于设备验收，错误词进度及设备等仍待对齐，goal active。

2026-10-02 增量：普通非管道自定义文本已接入独立候选队列，保留换行空槽及实际词数预算，修复百词批次提交／立即续接；用户长文本原文入口另行保留。证据与尚未覆盖边界见 [输入审计](OFFICIAL_INPUT_AUDIT.md)。客户端 1508／服务端 131 项零失败、零跳过，显式十万词、667 项人工清单及未开窗打包检查通过；清单不等于设备验收。未启动图形程序，完整重写仍未完成，goal active。

一个从零实现的 macOS 打字应用。目标是对 Monkeytype 做功能兼容的纯重写，但不使用其代码、后端、资产或广告。完整范围、实现边界和进度见 [REWRITE_SPEC.md](REWRITE_SPEC.md)。原创性边界、允许的参考元数据及可执行护栏见 [ORIGINALITY_BOUNDARY.md](ORIGINALITY_BOUNDARY.md)。

远程功能的自建服务范围与 API 草案见 [SERVICE_SCOPE.md](SERVICE_SCOPE.md) 和 [SERVICE_CONTRACTS.md](SERVICE_CONTRACTS.md)。

## 运行

需要 Xcode 16 或更新版本：

```sh
swift run
```

生成可直接双击的本地应用包：

```sh
zsh Scripts/package-macos-app.sh
```

无启动地构建、验签并检查应用包的关键元数据：

```sh
zsh Scripts/check-macos-app-package.sh
```

若本机已有固定的 Monkeytype 参考检出，可在同一次未启动的临时打包检查中额外扫描 `.app` 内所有受保护资源类型，拒绝与参考资源字节相同的文件：

```zsh
zsh Scripts/check-macos-app-package.sh --reference /absolute/path/to/monkeytype-reference
```

对固定参考源码执行串行的重写验收总门禁：它会检查原创性与兼容矩阵、完整运行原生客户端和自建服务测试、再无启动地验签并扫描临时应用包。它在每个编译或测试步骤前拒绝已有的 Typebar、测试或 Swift 编译进程，且自身绝不启动 Typebar：

```zsh
zsh Scripts/check-native-rewrite-readiness.sh /absolute/path/to/monkeytype-reference
```

检查参考源码隔离与生产服务边界：

```zsh
zsh Scripts/check-originality-boundaries.sh --self-test
```

对已克隆的固定 Monkeytype 参考源码，再检查生产 Swift 与参考 JS／TS 的长文本重合，以及生产资源中的图像、字体、音频和文本资源的字节重合：

```zsh
zsh Scripts/check-originality-boundaries.sh --reference /absolute/path/to/monkeytype-reference
```

对已克隆的固定 Monkeytype 参考源码，核验页面与模态盘点只覆盖其标识级表面，并要求每个已映射表面关联至少一个可执行的原生测试符号：

```zsh
zsh Scripts/check-page-modal-surface-audit.sh /absolute/path/to/monkeytype-reference
```

核验固定参考的后端 route registry 已由自建服务功能分区与证据路径完整覆盖：

```zsh
zsh Scripts/check-reference-service-surface-audit.sh /absolute/path/to/monkeytype-reference
```

核验后端 controller 行为与 route registry 的映射使用同一服务分区，且直接用户行为不会被归为不适用或未实现：

```zsh
zsh Scripts/check-reference-service-behavior-alignment.sh /absolute/path/to/monkeytype-reference
```

核验配置和语言 fixture 可从固定参考重新生成，同时保持 Typebar 自有证据分组与原生选择契约：

```zsh
zsh Scripts/check-reference-metadata-audits.sh /absolute/path/to/monkeytype-reference
```

核验固定参考的全部命名键盘布局均有 Typebar 独立精确映射，并拒绝快照、库存或测试证据漂移：

```zsh
zsh Scripts/check-layout-compatibility-audit.sh /absolute/path/to/monkeytype-reference
```

核验固定参考的 58 个挑战名称：57 项映射到本机规则。`mobileWarrior` 要求在移动设备上完成一小时，macOS 无法满足这一设备条件，故仍列为未映射；导入其旧链接时会说明平台限制，不会将其伪装成可达成的本机挑战：

```zsh
zsh Scripts/check-challenge-compatibility-audit.sh /absolute/path/to/monkeytype-reference
```

核验固定参考的客户端、后端 controller 与包级规格测试均已分类，且每个直接用户行为都有 Typebar 原生证据：

```zsh
zsh Scripts/check-reference-behavior-audit.sh /absolute/path/to/monkeytype-reference
```

核验人工验收清单保留唯一场景 ID、可识别状态和单实例执行规则：

```zsh
ruby Scripts/check-manual-acceptance-audit.rb
ruby Scripts/check-manual-acceptance-audit.rb --self-test
```

运行自建服务的最小健康检查（服务能力仍在建设中）：

```sh
cd server
swift run TypebarServer serve --hostname 127.0.0.1 --port 8080
```

服务能力可从 `http://127.0.0.1:8080/v1/capabilities` 查询；该入口会如实标示未实现模块。
若要暂时停止一切服务端写入而继续提供状态和只读查询，可在启动前设置 `TYPEBAR_MAINTENANCE_MODE=true`；客户端会提示用户本机离线练习不受影响。共享排行榜默认要求账户累计已接受练习超过 2 小时；部署者可在启动前用 `TYPEBAR_LEADERBOARD_MIN_PRACTICE_SECONDS` 设为 0 至 31,536,000 的整数秒。该门槛只影响公开 WPM/XP 榜及个人名次，不删除成绩、XP 或本机历史；设置非法值会拒绝启动，避免悄悄改变竞赛规则。

### 发布服务公告

部署者设置 `TYPEBAR_MODERATION_TOKEN` 后，可在原生设置的“审核员工具”发布或删除公告，也可附加计划日期。所有客户端会在启动时公开读取公告：普通公告可仅在当前 Mac 关闭，置顶公告会保留到服务端删除。含计划日期的公告可在正文中使用 `{date}`、`{dateNoTime}` 和 `{dateDifference}`，由 macOS 以当前地区显示完整日期时间、日期或相对时间。公告不需要账户，不包含输入、提示、成绩、邮箱或令牌。

### 配置账户邮件

密码重置与邮箱验证由部署者显式配置的 HTTPS webhook 投递，不绑定特定邮件服务。设置 `TYPEBAR_PASSWORD_RESET_WEBHOOK_URL` 后，密码重置会继续向该地址 `POST` JSON 的 `email`、`token` 和 ISO 8601 `expiresAt`；邮箱验证在相同字段外额外带 `kind: "emailVerification"`，以兼容既有的重置收件端。可选的 `TYPEBAR_PASSWORD_RESET_WEBHOOK_TOKEN` 会以 Bearer 令牌放入请求头。webhook 必须为带 `kind` 的事件生成验证邮件，且切勿记录或转发一次性码。未配置 webhook 时，能力端点会标为计划中，重置或验证请求会返回明确的 `503`，不会伪称邮件已发出。

### 配置外部人机验证

可选的 Cloudflare Turnstile 防滥用层必须同时设置 `TYPEBAR_TURNSTILE_SITE_KEY`、`TYPEBAR_TURNSTILE_SECRET` 和 `TYPEBAR_TURNSTILE_ALLOWED_HOSTNAMES`；仅设置其中一部分会拒绝服务启动。完整配置后，密码注册、OAuth 新用户注册、密码重置请求、资料举报、引语投稿和引语举报都必须先完成系统授权窗口中的一次性验证。客户端和服务端从不持久化 proof 或 Turnstile token；挑战状态仅在单个服务进程的内存中存在，所以真实 HTTPS 部署验收与多副本前的共享原子 TTL 存储仍由部署者负责。

### 配置第三方登录

自建服务可按标准授权码流程接入 GitHub、Google 或 Discord。每个提供商都必须同时设置客户端 ID、客户端密钥和精确的回调地址：`TYPEBAR_GITHUB_OAUTH_CLIENT_ID`、`TYPEBAR_GITHUB_OAUTH_CLIENT_SECRET`、`TYPEBAR_GITHUB_OAUTH_REDIRECT_URL`，或相应的 `TYPEBAR_GOOGLE_OAUTH_*` / `TYPEBAR_DISCORD_OAUTH_*` 三项。回调地址必须是 HTTPS（本机 `localhost`、`127.0.0.1` 或 `::1` 可使用 HTTP），不能带查询参数、片段或用户信息。服务端会使用 PKCE、一次性且仅保存哈希的短期 state，并只接受已验证的提供商邮箱；Discord 仅请求 `identify email`。提供商访问令牌不会保存或写入日志。尚未配置的提供商会在能力端点显示为“计划中”。原生账户设置会通过 macOS 系统授权窗口调用这套流程，并以 `typebar://oauth/callback` 接收回调。Discord 头像仅在用户已关联 Discord 且主动开启公开资料开关时，以受格式校验的公开 ID 与头像哈希构成 CDN 请求；未开启时不会从公开资料接口返回 Discord 关联。

## 已验证的基础能力

多语混合的新建默认与固定版 Monkeytype 一致，仅为 English、Spanish、French、German；446 个单语 ID 可搜索并自选，至少保留两项。旧版 Typebar 明确保存的 153 项组合继续加载。下方较早语言条目所说“加入默认和自选多语”中的非四项语言，现在应理解为“可自选加入”，不表示仍属于新建默认。

- 原生 macOS 窗口及菜单栏入口；可选择开启 `⌃⇧Space` 全局唤起（需要用户主动授予辅助功能权限）
- 单一被动 macOS 网络路径监测器会在空闲页与完成页明确提示离线；练习、计分和本机保存保持可用，恢复联网时给出一次短暂反馈，不轮询服务器或把网络路径误作服务健康状态。已开启远端发布的完成成绩遇到可恢复错误时只保存账户/服务器作用域与本机成绩 UUID，稍后按原账户幂等补发；令牌、提示和回放不进入队列索引
- 可重复打包为本地 `Typebar.app`
- 可从原生界面配置并开始计时、字数、引语、自定义文本、禅模式；计时支持 5–3600 秒、字数支持 1–1000 词的自定义数值
- 再次打开应用会恢复上次有效的测试模式、活动限制、语言、内容规则、引语来源与选择、自定义正文，以及计时／字数／自定义模式各自记住的限制；该选择也随完整本机备份和自建同步归档迁移。损坏或未来版本的本机记录会安全回到默认计时测试，恢复默认设置也会清除该记录
- 开始后可明确放弃本次测试；放弃与难度失败均不会写入完成成绩
- 原创 English（美式或英式拼写）、Español、Deutsch、Afrikaans、العربية、עברית、فارسی、اردو、தமிழ்、हिन्दी、ગુજરાતી、বাংলা、ไทย、नेपाली、ಕನ್ನಡ、తెలుగు、മലയാളം、संस्कृतम्、සිංහල、ខ្មែរ、Ελληνικά、Greeklish、Nederlands、Filipino、Català、Bahasa Indonesia、Bahasa Melayu、Dansk、Norsk bokmål、Norsk nynorsk、Svenska、Magyar、Čeština、Slovenčina、Slovenščina、Hrvatski、Српски、Srpski (Latin)、Български、Română、Suomi、Eesti、Íslenska、Français、Italiano、Português、简体中文、繁體中文、Русский、Українська、Українська (Latin)、日本語（ひらがな）、日本語（カタカナ）、日本語（ローマ字）、한국어、Türkçe、Polski 与 Git 离线词库及引语；Git 专项以本机公开命令界面和通用概念独立编排，不读取参考词值。Arabic、Hebrew、Persian 和 Urdu 用 macOS 输入源、RTL 提示与原生双向文本排版呈现，暂不进入双向多语混排。Tamil、Hindi、Gujarati、Bangla、Nepali、Kannada、Telugu、Malayalam、Sanskrit、Sinhala 和 Khmer 使用 macOS 组合输入与 LTR 原生文本排版，并可加入默认和自选多语混排；Thai 也可混排，但按参考实际生成器的空格提交语义练习，不将自然书写习惯误作无空格交互。Arabic 有默认开启、可关闭的快速输入，用于将原创词流中的短元音等组合符号归一为更易输入的提示；它不影响其他语言。乌克兰语 Latin、日语罗马字与 Greeklish 仅提供 Typebar 自创的 ASCII 离线内容；Srpski (Latin) 也只使用原创离线拉丁内容。四种书写形式都不会被随机远端原文替换；日语假名模式也不以随机百科文本替换提示；计时、字数和禅模式还可用中英混合词流，语言选择随测试配置、预设和成绩保存
- 新增原创 မြန်မာ 离线词库及引语，使用 macOS Burmese 输入源、组合输入和 LTR 文本排版，能加入默认和自选多语混排；知识短文与系统朗读分别使用参考定义的 `my` 与 `my-MM`，且不应用简化重音输入。
- 新增原创 ລາວ 离线词库及引语，使用 macOS Lao 输入源和 LTR 文本排版，能加入默认和自选多语混排；知识短文与系统朗读均精确使用参考定义的 `lo`，保留用户显式选择的简化输入。
- 新增原创 አማርኛ 离线词库及引语，使用 macOS Amharic 输入源和 LTR 文本排版，能加入默认和自选多语混排；知识短文与系统朗读分别精确使用参考定义的 `am` 与 `am-ET`，保留用户显式选择的简化输入。
- 新增原创 Հայերեն 离线词库及引语，使用 macOS Armenian 输入源和 LTR 文本排版，能加入默认和自选多语混排；参考未定义 BCP-47，故知识短文与系统朗读分别按其缺省规则使用 `en` 与 `en-US`，且不应用简化重音输入。
- 新增原创 ქართული 离线词库及引语，使用 macOS Georgian 输入源和 LTR 文本排版，能加入默认和自选多语混排；参考未定义 BCP-47，故知识短文与系统朗读分别按其缺省规则使用 `en` 与 `en-US`，且不应用简化重音输入。
- 新增原创 Azərbaycanca 离线词库及引语，使用 macOS Azerbaijani 输入源和 LTR 空格词界，可加入默认和自选多语混排；知识短文按官方 `az-AZ` 的首段使用 `az`，系统朗读严格使用 `az-AZ`，且官方未禁用简化输入。
- 新增原创 Беларуская 离线词库及引语，使用 macOS Belarusian 输入源和 LTR 空格词界，可加入默认和自选多语混排；知识短文按官方 `be-BY` 的首段使用 `be`，系统朗读严格使用 `be-BY`，并依照 `noLazyMode` 禁用简化输入。
- 新增原创 Lietuvių 离线词库及引语，使用 macOS Lithuanian 输入源和 LTR 空格词界，可加入默认和自选多语混排；参考未定义 BCP-47，故知识短文与系统朗读分别按其缺省规则使用 `en` 与 `en-US`，并保留简化输入选项。
- 新增原创 Latviešu 离线词库及引语，使用 macOS Latvian 输入源和 LTR 空格词界，可加入默认和自选多语混排；知识短文与系统朗读均严格使用官方 `lv`，且保留简化输入选项。
- 新增原创 Монгол离线词库及引语，使用 macOS Mongolian 输入源和 LTR 空格词界，可加入默认和自选多语混排；参考仅定义 `noLazyMode`、未定义 BCP-47，故知识短文与系统朗读分别按其缺省规则使用 `en` 与 `en-US`，并禁用简化输入选项。
- 新增原创 Gaeilge 离线词库及引语，使用 macOS Irish 输入源和 LTR 空格词界，可加入默认和自选多语混排；知识短文按官方 `ga-IE` 的首段使用 `ga`，系统朗读严格使用 `ga-IE`，且官方未禁用简化输入。
- 新增原创 Galego 离线词库及引语，使用 macOS Galician 输入源和 LTR 空格词界，可加入默认和自选多语混排；知识短文按官方 `gl-ES` 的首段使用 `gl`，系统朗读严格使用 `gl-ES`，并保留官方 `orderedByFrequency` 对应的 Zipf 高频词选项。
- 新增原创 मराठी 离线词库及引语，使用 macOS Marathi 输入源和 LTR 空格词界，可加入默认和自选多语混排；参考仅定义 `noLazyMode` 与 `orderedByFrequency`、未定义 BCP-47，故知识短文与系统朗读分别按其缺省规则使用 `en` 与 `en-US`，保留 Zipf 高频词并禁用简化输入选项。
- 新增原创 Shqip 离线词库及引语，使用 macOS Albanian 输入源和 LTR 空格词界，可加入默认和自选多语混排；参考只定义语言名称，故知识短文与系统朗读严格按缺省规则使用 `en` 与 `en-US`，并保留简化输入选项。
- 新增原创 Ichibemba 离线词库及引语，使用 macOS Bemba 输入源和 LTR 空格词界，可加入默认和自选多语混排；知识短文与系统朗读严格使用官方 `bem`，参考将 `orderedByFrequency` 标为 `false`，因此启用 Zipf 时会提示词表未按频率排序但不会关闭修饰器。
- 新增原创 Bosanski 离线词库及引语，使用 macOS Bosnian 输入源和 LTR 空格词界，可加入默认和自选多语混排；参考只定义语言名称与 `orderedByFrequency: true`、未定义 BCP-47，故知识短文与系统朗读严格按缺省规则使用 `en` 与 `en-US`，并保留 Zipf 高频词和简化输入选项。
- 新增原创 Esperanto、Esperanto · X-sistemo 与 Esperanto · H-sistemo 离线词库及引语，三者都是独立的 LTR 空格词界练习并可混排；参考标准书写与 H-sistemo 确认支持 Zipf，X-sistemo 未声明排序，故启用 Zipf 时仅显示可能不支持的提示。三者均未定义 BCP-47，因此知识短文与朗读分别严格回退至 `en` 与 `en-US`；标准书写保留简化输入，X/H 两种 ASCII 转写按 `noLazyMode` 禁用它。
- 新增原创 Latina 离线词库及引语，使用 LTR 空格词界，可加入默认和自选多语混排；参考只定义语言名称，故知识短文与系统朗读严格按缺省规则使用 `en` 与 `en-US`，保留简化输入；参考未声明词频排序，因此启用 Zipf 时会提示可能不支持但不会关闭修饰器。
- 新增原创 Friulian 离线词库及引语，使用 LTR 空格词界，可加入默认和自选多语混排；知识短文与系统朗读均严格使用参考定义的 `fur`，并保留简化输入；参考未声明词频排序，因此启用 Zipf 时会提示可能不支持但不会关闭修饰器。
- 新增原创 Malagasy 离线词库及引语，使用 LTR 空格词界，可加入默认和自选多语混排；参考只定义 `noLazyMode`、未定义 BCP-47，故知识短文与系统朗读分别按缺省规则使用 `en` 与 `en-US`，并禁用简化输入；参考未声明词频排序，因此启用 Zipf 时会提示可能不支持但不会关闭修饰器。
- 新增原创 Cymraeg（Welsh）离线词库及引语，使用 LTR 空格词界，可加入默认和自选多语混排；参考只定义语言名称，故知识短文与系统朗读严格按缺省规则使用 `en` 与 `en-US`，保留简化输入；参考未声明词频排序，因此启用 Zipf 时会提示可能不支持但不会关闭修饰器。
- 新增原创 Hausa 离线词库及引语，使用 LTR 空格词界，可加入默认和自选多语混排；知识短文与系统朗读均严格使用参考定义的 `ha`，并保留简化输入；参考未声明词频排序，因此启用 Zipf 时会提示可能不支持但不会关闭修饰器。
- 新增原创 Татарча（Tatar）离线词库及引语，使用 LTR 空格词界与西里尔输入，可加入默认和自选多语混排；知识短文与系统朗读均严格使用参考定义的 `tt`，并保留简化输入和确认可用的 Zipf 高频词。
- 新增原创 Oʻzbekcha（Uzbek）离线词库及引语，使用参考明确的 LTR 空格词界，可加入默认和自选多语混排；知识短文按 BCP 首段使用 `uz`，系统朗读精确使用 `uz-UZ`，并保留简化输入；参考未声明词频排序，因此启用 Zipf 时会提示可能不支持但不会关闭修饰器。
- 新增 Swiss German 原生练习：严格复用 Typebar 自有 German 词流及四档引语，并把可见 `ß` 全部替换为 `ss`；这是对固定源码专用分支的等价实现，不导入官方词表或引语。知识短文按 BCP 首段使用 `de`，系统朗读精确使用 `de-CH`，保留简化输入；参考未声明词频排序，因此 Zipf 保留并提示可能不支持。Swiss German 可进入多语混排与成绩排行榜，但按源码不提供社区引语投稿或社区来源。
- 新增原创 کوردی ناوەندی 离线词库及引语，使用 macOS Central Kurdish 输入源、RTL 原生排版及连写字形；知识短文与系统朗读均严格使用 `ckb`。它不进入默认或自选多语混排，且参考未定义 `noLazyMode`，故保留简化输入选项。
- 代码练习提供与官方当前目录对应的 70 个语言/方言选择，每项使用 Typebar 原创离线片段，并支持换行、自动缩进、可选反缩进和回放；最新增加 Dockerfile，不导入官方代码语料
- 当前语言目录：376 个可单独练习的语言或书写方式、70 个代码选择和 2 个混合入口。
- 固定参考版本的 446 个官方语言配置 ID 已有可重新生成的机器总账：446 个均对应 Typebar 独立选择，没有兼容代指或未映射 ID；这种覆盖只表示选择、元数据与可见行为边界完整，所有练习内容仍由 Typebar 独立编写和生成，不复制官方词值、代码、资产或实现
- Vietnamese 1k／5k、Pinyin 1k／10k、Hausa 1k、Bemba 1k／10k、Catalan 1k 与 Frisian 1k 以九个独立 ID 提供原创按需索引词流，保持实际规模、长度、大小写、标点、多级内部空格、非 ASCII 与交叠结构；各档与对应固定词表精确零交集
- Irish 1k、Filipino 1k、Hungarian 1k／2k、Welsh 1k、Lithuanian 1k／3k、Latvian 1k 与 Maltese 1k 以九个独立 ID 提供原创按需索引词流，保持实际规模、长度、组合标记、大小写、标点、内部空格、非 ASCII 与交叠结构；各档与对应固定词表精确零交集
- Danish 1k／10k、Swedish 1k、Finnish 1k／10k、Estonian 1k／5k／10k 与 Icelandic 1k 以九个独立 ID 提供原创按需索引词流，保持实际规模、长度、大小写、标点、非 ASCII、数字与交叠结构；受限授权的参考词值不会进入项目
- Czech 1k／10k、Slovak 1k／10k、Slovenian 1k／5k、Croatian 1k 与 Dutch 1k／10k 以九个独立 ID 提供原创按需索引词流，保持实际规模、长度、大小写、标点、空格、非 ASCII、数字与交叠结构；普通出题不物化整表
- Turkish 1k／5k、Kazakh 1k、Kyrgyz 1k、Tatar 1k／5k／9k 与 Uzbek 1k／70k 以九个独立 ID 提供原创按需索引词流，保持实际规模、长度、大小写、标点、内部空格、非 ASCII 与交叠结构；70k 普通出题只生成请求项
- Tamil 1k、Telugu 1k、Bangla 10k、Hindi 1k 与 Gujarati 1k 以五个独立 ID 提供原创按需索引词流，保持实际规模、标量／字素长度、组合标记及标点／空格结构，并使用各自原生输入、百科与朗读路径
- Thai 1k／5k／10k／20k／50k／60k 以六个独立 ID 提供原创按需索引词流，保持各档规模、Unicode 长度、组合标记及标点／空格／数字结构，不复制参考词值
- Norsk bokmål 1k／5k／10k／150k／600k 以五个独立 ID 提供原创按需索引词流，保持各档规模、长度、大小写、标点、数字与非 ASCII 结构；600k 普通出题只生成请求项
- Norsk nynorsk 1k／5k／10k／100k／400k 以五个独立 ID 提供原创按需索引词流，保持各档规模、长度、大小写、标点、空格、数字与非 ASCII 结构；400k 普通出题只生成请求项
- 简体中文 1k／5k／10k／50k 以四个独立 ID 提供原创按需 CJK 索引词流，保持固定规模、长度和 Unicode 聚合结构；无空格普通出题只生成请求项
- 繁體中文 1k／5k／10k／50k 以四个独立 ID 提供原创按需繁体 CJK 索引词流，保持实际规模、长度、Unicode 数字、标点交叠与词频语义；无空格普通出题只解析本次提示
- नेपाली 1k 以独立 ID 提供 1,000 项原创按需天城文索引词流，保持组合标记、字符与标量长度结构，并使用 macOS 组合输入、`ne` 百科和 `ne-NP` 朗读
- Azərbaycanca 1k 以独立 ID 提供 989 项原创按需索引词流，保持 2–7 字符与 668 个非 ASCII 条目的聚合结构，并接入 `az` 百科及 `az-AZ` 朗读
- Malagasy 1k 与 Bahasa Melayu 1k 分别以 975／1,000 项原创按需索引词流提供独立入口，保持各自长度、大写、标点、非 ASCII 与内部空格聚合结构
- Монгол 10k 以 9,219 项原创按需西里尔索引词流提供独立入口，保持 1–18 字符、897 个大写项与全非 ASCII 字母结构
- Українська 与其 Latin 书写分别新增 1k／10k／50k 三档独立入口，以六套原创按需索引词流保持各档实际规模、长度、大小写、标点、数字、非 ASCII 与交叠结构
- Bahasa Indonesia 1k／10k 与 کوردی ناوەندی 2k／4k 以四个独立 ID 提供原创按需索引词流，分别保持异常 `hu-HU` 元数据、正常 `id-ID` 元数据及 RTL 连写和内部空格结构
- Swiss German 1k／2k 与 Afrikaans 1k／10k 以四个独立 ID 提供原创按需索引词流，保持实际规模、长度、大小写、标点、空格、数字、非 ASCII 与交叠结构；Swiss German 分档沿用 `ss` 可见转换并拒绝社区引语投稿
- Italiano 1k／7k／60k／280k 以四个独立 ID 提供原创按需索引词流，保持 1,159／7,154／60,442／279,833 的实际规模及逐档长度、大小写、标点、符号与非 ASCII 结构；280k 普通出题只读取请求项
- Qırımtatarca 与 Къырымтатарджа 各自的 1k／5k／10k／15k 以八个独立 ID 提供原创按需索引词流，保持逐档规模、长度、脚本、大小写、标点与非 ASCII 交叠结构；两套书写分别继承自有引语且不加入多语混排
- Occitan 与 Taqbaylit 各自的 1k／2k／5k／10k 以八个独立 ID 提供原创按需索引词流，保持逐档规模、长度、非 ASCII 及 Kabyle 标点交叠结构；两族分别保持 `oc-FR` 与 `kab`、未知与不支持 Zipf 的元数据边界
- עברית 1k／5k／10k、فارسی 1k／5k／20k 与 اردو 1k／5k 以八个独立 ID 提供原创按需索引词流，保持 RTL、连写、实际规模、长度以及多词、标点、组合标记与零宽格式字符结构；三族分别继承自有引语且不加入多语混排
- 韩语 1k／5k 以两个独立 ID 提供原创、按需生成的纯 Hangul 词流，保持固定规模、长度、空格词界、连写、朗读和数据面语义，不复制参考词值
- Creature Index 1k · Typebar 使用规则生成的 1,025 个原创虚构生物条目，保留多词、符号、数字、长度和非频率排序结构，不包含宝可梦名称、设定或资产
- Arena Strategy Terms · Typebar 使用 442 个原创竞技场术语重建题名大小写、多词 section、符号、数字与默认标点行为，不包含英雄、装备、技能名称或游戏资产
- Русский · Краткие формы提供 200 条基础与 880 条扩展原创短形式；两个规模均独立可选，保持包含关系、符号、数字、大小写与长度边界，不导入参考词值
- தமிழ் · பழைய தொகுப்பு以独立入口提供 460 条原创 joining-script 练习项，保持固定标量长度和单条多词结构，不导入旧词表值
- English 1k／5k／10k／25k／450k 作为五个独立入口使用原创确定性索引词流；普通出题只生成实际请求的词，词表筛选与弱项分析才扫描所选规模，同时保持固定实际规模、长度、大小写、符号和词频排序能力，不导入参考词值
- Español 1k／10k／650k 作为三个独立入口使用原创确定性索引词流，保持 998／9,990／646,579 的实际规模及长度、大小写、符号、多词和非 ASCII 结构；普通出题不物化整表，也不导入参考词值
- Français 1k／2k／10k／600k 作为四个独立入口使用原创确定性索引词流，保持 1,394／2,041／10,251／633,941 的实际规模及长度、大小写、标点、多词和非 ASCII 结构；四档不会重复加入默认混排，600k 普通出题只读取请求项
- العربية 10k 与 العربية المصرية 1k 使用两套原创阿拉伯字母索引词流，保持 9,281／1,141 个唯一项及固定的前导、内部和双空格结构；两项独立接入 RTL、连写、`ar-SA`／`ar-EG`、四档引语和服务端数据面
- Deutsch 1k／10k／250k 作为三个独立入口使用原创确定性索引词流，保持 988／9,994／239,243 的实际规模及长度、名词大写、标点、多词和非 ASCII 结构；250k 普通出题不会物化整表
- Română 1k／5k／10k／25k／50k／100k／200k 七档均为独立入口，原创确定性索引词流保持对应实际规模及长度、标点和非 ASCII 结构；200k 普通出题同样只读取请求项
- Polski 2k／5k／10k／20k／40k／200k 六档均为独立入口，原创确定性索引词流保持对应实际规模及长度、大小写、标点和非 ASCII 结构；200k 普通出题只读取请求项
- Беларуская 1k／5k／10k／25k／50k／100k 六档均为独立入口，原创确定性西里尔索引词流保持对应实际规模及长度、大小写、标点和非 ASCII 结构；100k 普通出题只读取请求项
- Русский 1k／5k／10k／25k／50k／375k 六档均为独立入口，原创确定性西里尔索引词流保持对应实际规模及长度、大小写、标点、多词和非 ASCII 结构；375k 普通出题只读取请求项
- Português 1k／3k／5k／320k／550k 五档均为独立入口，原创确定性索引词流保持对应实际规模及长度、大小写、标点、多词、数字、符号和非 ASCII 结构；两档大型词流普通出题只读取请求项
- 引语模式可按短、中、长、超长筛选，收藏原创离线引语；完成页会保留本轮引语身份与来源标题，提供本机收藏/评分，或对已审核社区引语进行账户评价和私有举报；可选择仅在输入中重开时重复当前引语，随机选择则始终避开当前内容；收藏与策略会随本机归档保存
- 计时、字数和禅模式可按需加入数字与标点，且选项随预设和备份保存
- 自定义文本可保存、选择复用和删除；“筛选词表…”可只从 Typebar 自创离线词表按词长、字符或 ICU 正则生成内容；“生成文本…”可从用户提供的片段随机组合练习词。两者均可替换或追加后立即开始，且不下载第三方词表
- normal / expert / master 难度，以及严格空格、停止错误、删除错误、盲打、自由回退与三档信心模式；信心模式可阻止回退修复上一错误词，最大档禁用退格
- 自有趣味修饰器支持“无空格”与“下划线分隔”两种互斥的词间边界练习；“全大写”“逐词首字母大写”“交替大小写”彼此互斥，并可组合“ROT13”“逐词反写”“字符双写”和“遇错清除当前词”。后者仅对空格分词文本生效，误键会清除当前未提交词，并保持回放可复现。另有“记忆模式”：开始前显示提示，首个有效输入后隐藏提示但继续按原文计分
- “简化重音输入”修饰器可将当前测试提示中的重音、变音、常见连字与 ß 转成普通拉丁输入；不会改写离线内容或用户原文
- 可选择当前词、当前词加 1/2/3 个预读词四档可见范围；它只影响提示显示，不改变输入、成绩或回放
- 原生 AppKit 键盘输入（文字提交、退格、Esc / ⌘R 重开与 IME 组合输入协议）
- 快速重开键可设为关闭、Esc、Tab 或 Enter；⌘R 始终可用
- 可选原创键盘提示：一百五十三种内置布局（含 Whix2、Haruka、Kuntum、Kuntem、Kuntem-JQ、Scythe、Inqwerted、Rain、Night、Night STIC、Nila、Noctum、Cascade、Vylet、Romak、Octa8、Nerps、Gallium、Gallium Angle、Gallium v2、STNDC、UCIEA、Whorf、Whorf 6、Whorfmax、Pine v4、Three、Asset、Dwarf、Flaw、Focal、Zenith、Dhorf、Gust、Recurva、Pine、Real、Sertain、CTGAP、Graphite、Capewell Dvorak、Colman、Heart、Klauser、Oneproduct、Middlemak-NH、Foalmak、Quartz、Arensito、ARTS、Boo/Mangle、APT/Angle、Middlemak、Semimak/JQ/JQC、Canary/Matrix、TypeHack、ISRT/Angle、Engram/Engrammer、MTGAP/Full、Ina、Soul、Niro、Hands Down/Alt/Neu/Neu Inverted、French Bépo AFNOR、ANSI Alpha、Swedish Colemak/Dvorak、French Dvorak、French AZERTY AFNOR、French Bépo、Programmer Dvorak/Prime、German Dvorak/Improved、Spanish Dvorak、MTGAP ASRT、Halmak、QGMLWB、QGMLWY、QWPR、Colemak Angle/Wide/DHv、Norman、Programmer Workman、Turkish E、Japanese Hiragana、相互独立的 Colemak-DH ANSI/ISO/Matrix/Wide ANSI/Wide ISO 与 Colemak-DHk ANSI/ISO、Typebar 自写的希腊字母、匈牙利语 QWERTZ、保加利亚语与塞尔维亚语西里尔图，以及 Tamil99、Brazilian ABNT2、Dvorak Left/Right-Handed、Mongolian Cyrillic、Armenian HM QWERTY、Hindi InScript、Thai Kedmanee/Pattachote、Polish (Programmers)、Urdu Phonetic 和 Arabic macOS 的 Option 字符层、Swedish QWERTY、Macedonian、Pashto、Estonian、Persian Standard/Farsi、Arabic 101/102 与 Hebrew）、跟随 macOS 当前输入源的动态物理键位图，以及最多二十种用户自写的 Unicode 四行键盘图；七种原生几何样式、关闭/静态/按键反馈/下一键模式、精简/数字行/完整按键集、0.5–3.5 倍大小及小写/大写/空白/动态图例均可持久化。视觉键盘图不改变输入，输入默认始终交给 macOS 当前输入法，只有明确开启内置布局模拟时才接管物理键。Layout Fluid 会按阶段同时切换内置键盘图与模拟布局（每轮最多选择十五种）；多字符快捷键会完整输出，但下一键提示优先选择能精确输出目标字符的单字符键；动态图例随 Shift、Caps Lock 以及支持的 Option/Shift+Option 层更新，其余死键与 Option 输入仍由 macOS 处理
- 原生命令面板完整公开固定键盘配置：18 个模式／几何／图例／按键集离散选项、0.5–3.5 倍且步长 0.1 的大小编辑器，以及 `overrideSync + 239` 个视觉布局命令。新设置默认采用 `overrideSync` 并持续跟随输入布局模拟；旧归档缺少来源字段时保留此前内置布局行为。指定视觉布局不会改变物理输入映射。布局命令按固定行为退出挑战并重开，其他键盘外观命令即时生效
- 当前内置键盘图为二十五种：新增 Danish QWERTY，独立模拟 `å`、`æ`、`ø`、`§` 与其普通/Shift 实体键位；该项取代上条的“二十四种”计数。死键和 Option/AltGr 层继续保持 macOS 原生输入路径，不导入 Monkeytype 布局资产
- 当前内置键盘图为二十六种：新增 Norwegian QWERTY，公开现有 Nordic 键位对应的 `å`、`ø`、`æ` 实体映射，保留 Nordic 作为已有设置的兼容选项；该项取代上条的“二十五种”计数。死键和 Option/AltGr 层仍保持 macOS 原生输入路径，不导入 Monkeytype 布局资产
- 当前内置键盘图为二十七种：新增 ANSI Colemak-DH，独立模拟与标准 Colemak 不同的 `B/G`、`D/V`、`H/M` 位置；该项取代上条的“二十六种”计数。ISO、wide 与其他 Colemak-DH 变体仍由系统输入或自定义布局处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为二十八种：新增 Turkish F，独立模拟 `ğ/ı/i/İ/ü/ö/ç/ş`、数字行与 ISO `< >` 的 F 键位；该项取代上条的“二十七种”计数。AltGr 与组合式死键仍由 macOS 处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为二十九种：新增 Bulgarian Phonetic Traditional，独立模拟 `ч/я/ъ/ш/щ/ю/ь/ѝ`、数字行与 ISO 物理键上的 `ю`；该项取代上条的“二十八种”计数。AltGr 仍由 macOS 处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为三十种：新增 Belarusian，独立模拟 `Ў/ў`、`І/і`、`Ё/ё`、数字符号与 ISO `< >`；该项取代上条的“二十九种”计数。Option/AltGr 仍由 macOS 处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为三十一种：新增 Macedonian，独立模拟 `Љ/Њ/Ѕ/Ѓ/Ж/Ќ/Џ`、ISO `ѐ/Ѐ` 和数字引号层；该项取代上条的“三十种”计数。Option/AltGr 仍由 macOS 处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为三十二种：新增 Pashto，独立模拟波斯-阿拉伯字母、东阿拉伯数字、组合音标、ZWJ/ZWNJ 与区域标点的普通/Shift 键位；不输出字符的 ISO 键、AltGr、方向控制与其他系统层继续由 macOS 处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为三十三种：新增 Estonian，独立模拟 `õ/ä/ö/ü/š/ž`、ISO `< >` 与区域标点的普通/Shift 键位；AltGr 与组合式死键继续由 macOS 处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为三十四种：新增 Persian (Standard)，独立模拟波斯字母、东阿拉伯数字、`﷼`、组合音标、ZWJ/ZWNJ、ISO 与区域标点的普通/Shift 键位；AltGr 和方向控制继续由 macOS 处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为三十五种：新增 Arabic (101)，独立模拟阿拉伯字母、组合音标、`لإ/لأ/لا/لآ` 完整文本输出、ISO 与区域标点的普通/Shift 键位；AltGr、ZWJ/ZWNJ 与方向控制继续由 macOS 处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为三十六种：新增 Hebrew，独立模拟希伯来字母、Shift 拉丁/标点层与 ISO 键的普通/Shift 实体键位；AltGr、Caps Lock 元音点和方向控制继续由 macOS 处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为三十七种：新增 Arabic (102)，独立模拟 `ذ`、ISO tatweel、组合音标、连字与区域标点的实际普通/Shift 键位；AltGr、ZWJ/ZWNJ 与方向控制继续由 macOS 处理，不导入 Monkeytype 布局资产
- 当前内置键盘图为三十八种：新增 Arabic (macOS)，依据 macOS TIS/`UCKeyTranslate` 的公开输入行为独立实现阿拉伯数字、组合音标、区域标点及 Option/Shift+Option 层；无输出的 Shift 键会被正确消费，不会落回另一输入源。不读取或导入 Monkeytype 布局 JSON
- 当前内置键盘图为三十九种：新增 Persian (Farsi)，依据 Microsoft Persian KLID `00000429` 的公开键位表独立实现 Farsi Yeh、Keheh、Gaf、ISO `پ` 与 `ریال` 多字符快捷键；Control 层继续由 macOS 处理，不读取或导入 Monkeytype 布局 JSON
- 当前内置键盘图为四十种：新增 Urdu Phonetic (CRULP)，依据 CLE/CRULP v1.1 规范与 SIL Keyman 的开放映射交叉实现 Urdu 字母、数字、组合音标、宗教符号及 Option/Right Alt 层；明确无输出的 Shift+F 会被正确消费，不导入第三方代码、字体或键盘资产
- 当前内置键盘图为四十一种：新增 Thai Kedmanee，依据 Microsoft KLID `0000041E` 键位表与 NECTEC 的 TIS 820 资料独立实现泰文字母、元音、声调、数字与标点的普通/Shift 实体键位，并以 macOS `com.apple.keylayout.Thai` 系统映射交叉核对；Option 与组合输入继续由 macOS 处理，不读取或导入 Monkeytype 布局 JSON
- 当前内置键盘图为四十二种：新增 Thai Pattachote，依据 Microsoft KLID `0001041E` 的公开布局标识及键盘驱动表独立实现普通/Shift 键位，并以 NECTEC 布局资料和 macOS `com.apple.keylayout.Thai-PattaChote` 系统映射交叉核对主体字母层；采用完整标准数字行，Option 与组合输入继续由 macOS 处理，不读取或导入 Monkeytype 布局 JSON
- 当前内置键盘图为四十三种：新增 Hindi – InScript (macOS)，依据 macOS `com.apple.keylayout.Devanagari` 的系统翻译行为独立实现数字、元音、辅音、组合符与 `ज्ञ/त्र/क्ष/श्र` 多码点输出；无输出普通/Shift 键会被明确消费，Option 与复杂组合输入继续由 macOS 处理。BIS 与 Microsoft 资料用于交叉确认 InScript 标准家族，不读取或导入 Monkeytype 布局 JSON
- 当前内置键盘图为四十四种：新增 Armenian – HM QWERTY，依据 macOS `com.apple.keylayout.Armenian-HMQWERTY` 的系统翻译行为独立实现 Base、Shift、Option 与 Shift+Option 四层，包括仅在 Option 层提供的 Armenian 字母和标点；不读取或导入 Monkeytype 布局 JSON
- 当前内置键盘图为四十五种：新增 Mongolian Cyrillic，依据 macOS `com.apple.keylayout.Mongolian-Cyrillic` 的系统翻译行为独立实现 Base、Shift、Option 与 Shift+Option 四层；主体字母层与 Unicode CLDR 的 Mongolian Cyrillic 标准布局交叉核对，不读取或导入 Monkeytype 布局 JSON
- 当前内置键盘图为四十七种：新增 Dvorak – Left-Handed 与 Dvorak – Right-Handed，依据 macOS `com.apple.keylayout.Dvorak-Left` / `Dvorak-Right` 独立实现四个修饰层，并与 Apple 对左右手布局的定义及 Unicode CLDR 标识交叉核对；不读取或导入 Monkeytype 布局 JSON
- 当前内置键盘图为四十八种：新增 Brazilian – ABNT2，依据 macOS `com.apple.keylayout.Brazilian-ABNT2` 独立实现四个修饰层，并显式支持 ISO 键 keyCode 10 与右 Shift 附近的 ABNT2 专用键 keyCode 94；Unicode CLDR 用于交叉核对 103 键 ABNT2 几何和主体层，不读取或导入 Monkeytype 布局 JSON
- 当前内置键盘图为四十九种：新增 Tamil99 (macOS)，依据 macOS `com.apple.keylayout.Tamil99` 独立实现四个修饰层，完整保留 Tamil 组合符、`ஸ்ரீ` 多码点输出和明确空输出的 Shift/Option 层；Microsoft Tamil 99 标识与 Unicode CLDR Tamil 键盘资料用于交叉核对，不读取或导入 Monkeytype 布局 JSON
- 当前内置键盘图为五十种：新增 Colemak-DH ISO，依据 Colemak-DH 官方公开说明与 CC0 macOS 基础层独立实现 ISO Angle Mod 的额外 `Z` 键、左侧 `X C D V`、中央反引号及右侧 `K H , . /`；该时点的 Matrix 与 wide 等其他变体由 macOS 输入源或自定义布局处理，下一条已补齐 Matrix，不读取或导入 Monkeytype 布局 JSON、代码或资产
- 当前内置键盘图为五十一种：新增 Colemak-DH Matrix，依据 Colemak-DH 官方 CC0 macOS 基础层独立实现正交底行 `Z X C D V K H , . /`，与 ANSI 的中央 `Z` 重定位及 ISO 的额外实体键保持独立；wide 等其他变体继续由 macOS 输入源或自定义布局处理，不读取或导入 Monkeytype 布局 JSON、代码或资产
- 当前内置键盘图为五十三种：新增 Colemak-DHk ANSI 与 ISO，依据 ColemakMods 官方 CC0 macOS 键位定义独立实现 `K` 留在主行、`M H` 移至底行的 DHk 语义；ANSI 底行为 `X C D V Z M H , . /`，ISO 额外保留左侧 `Z` 实体键及中央反引号。两者具有独立提示、模拟、反查与持久化标识，不读取或导入 Monkeytype 布局 JSON、代码或资产
- 当前内置键盘图为五十五种：新增 Colemak-DH Wide ANSI 与 ISO，依据 ColemakMods 官方 CC0 定义独立实现向右移动的数字、右手字母和标点列；ANSI 底行为 `X C D V Z / K H , .`，ISO 额外保留左侧 `Z`，底行为 `Z X C D V \\ # K H , .`。两者具有独立提示、模拟、反查与持久化标识，不读取或导入 Monkeytype 布局 JSON、代码或资产
- 当前内置键盘图为五十六种：新增 Japanese Hiragana，使用 Typebar 自有 Swift 数据重新表达固定参考可观察的 47 个 ANSI 键位行为，覆盖普通假名、小假名、日文括号与标点 Shift 输出；不复制、打包或运行参考 JSON、代码、字体或其他资产
- 当前内置键盘图为五十九种：新增 ANSI Colemak Angle、ANSI Colemak Wide 与 ANSI Norman。三项均以 Typebar 自有 Swift 映射完整覆盖 47 个 ANSI Base/Shift 位置，并分别保留 Angle 底行、Wide 数字/标点位移和 Norman 字母排列；不复制、打包或运行参考布局资产
- 当前内置键盘图为六十二种：新增 ANSI Colemak-DHv、Programmer Workman 与 Turkish E。前两项完整覆盖 47 个 ANSI Base/Shift 位置，Turkish E 完整覆盖含额外 ISO 键的 48 个位置；三项均接入提示、模拟、反查、设置归档和 Layout Fluid，不复制、打包或运行参考布局资产
- 当前内置键盘图为六十七种：新增 MTGAP ASRT、Halmak、QGMLWB、QGMLWY 与 QWPR。五项均完整覆盖 47 个 ANSI Base/Shift 位置，其中 Halmak 保留非标准数字及标点 Shift 层；全部接入提示、模拟、反查、设置归档和 Layout Fluid，不复制、打包或运行参考布局资产
- 当前内置键盘图为七十二种：新增 Programmer Dvorak、Programmer Dvorak Prime、German Dvorak、German Dvorak Improved 与 Spanish Dvorak。两项 ANSI 和三项 ISO 布局分别完整覆盖 47/48 个 Base/Shift 位置，并保留各自符号及区域字符层；全部接入提示、模拟、反查、设置归档和 Layout Fluid，不复制、打包或运行参考布局资产
- 上一阶段内置键盘图增至七十七种：新增 Swedish Colemak、Swedish Dvorak、French Dvorak、French AZERTY (AFNOR) 与 French Bépo。五项均完整覆盖 48 个 ISO 位置；AFNOR/Bépo 另覆盖 Option/Shift+Option，AFNOR 包含 NBSP/窄 NBSP 空格层；全部接入提示、模拟、反查、设置归档和 Layout Fluid，不复制、打包或运行参考布局资产
- 上一阶段内置键盘图增至七十九种：新增 French Bépo (AFNOR) 与 ANSI Alpha。Bépo AFNOR 完整覆盖 48 个 ISO 四层位置与普通空格，Alpha 完整覆盖 47 个 ANSI Base/Shift 位置；两项均接入提示、模拟、反查、设置归档和 Layout Fluid，不复制、打包或运行参考布局资产
- 上一阶段内置键盘图增至八十三种：新增 ANSI Hands Down、Alt、Neu 与 Neu Inverted。四项均完整覆盖 47 个 ANSI Base/Shift 位置；Neu 两项保留非标准符号层。`handsdown_promethium` 因独立 `R` 拇指键继续回退，不伪装为标准 ANSI；不复制、打包或运行参考布局资产
- 上一阶段内置键盘图增至八十八种：新增 MTGAP、MTGAP Full、Ina、Soul 与 Niro。五项均完整覆盖 47 个 ANSI Base/Shift 位置，前三项保留非标准符号层，MTGAP Full 在精简提示中仍显示数字行；不复制、打包或运行参考布局资产
- 上一阶段内置键盘图增至九十三种：新增 TypeHack、ISRT、ISRT Angle、Engram 与 Engrammer。五项均完整覆盖 47 个 ANSI Base/Shift 位置，TypeHack 与 Engram 保留非标准符号层，Engram 两项在精简提示中仍显示数字行；不复制、打包或运行参考布局资产
- 上一阶段内置键盘图增至九十八种：新增 Semimak、Semimak JQ、Semimak JQC、Canary 与 Canary Matrix。五项均完整覆盖 47 个 ANSI Base/Shift 位置，并保留三种 Semimak 的 J/Q/C 差异和两种 Canary 的独立排列；不复制、打包或运行参考布局资产
- 上一阶段内置键盘图增至一百零三种：新增 Boo、Boo Mangle、APT、APT Angle 与 Middlemak。五项均完整覆盖 47 个 ANSI Base/Shift 位置；Boo 两项保留非标准符号层，Boo Mangle 在精简提示中仍显示数字行，APT Angle 保留独立底行；不复制、打包或运行参考布局资产
- 上一阶段内置键盘图增至一百五十三种：新增 Whix2、Haruka、Kuntum、Kuntem 与 Kuntem-JQ。Haruka 与三个 Kuntum/Kuntem 变体完整覆盖 47 个 ANSI Base/Shift 位置；Whix2 精确保留 40 个赋值位置和 7 个空位，不复制、打包或运行参考布局资产
- 上一阶段内置键盘图增至一百五十八种：新增 BEAKL Zi、Snorkle、MALTRON、PRSTEN 与 RSTHD。五项完整覆盖 47 个 ANSI Base/Shift 位置；其中四项原生显示双拇指行，普通 Mac 的唯一物理 Space 按固定参考可观察语义映射到第五行首项，第二项仅作为布局提示，不复制、打包或运行参考布局资产
- 上一阶段内置键盘图增至一百六十三种：新增 Hands Down Promethium、Statica 3×5、Vestnik、Diktor 与 Diktor Voronov Mod。Promethium 原生显示 `R + 空格` 拇指行并由物理 Space 输入 `r`；五项的 AltGr 未重定义键保持布局 Base/Shift，Statica/Vestnik 另保留特殊 Cyrillic 层，Diktor 两项保留重排数字符号层，不复制、打包或运行参考布局资产
- 当前内置键盘图为一百九十三种：新增 Sturdy Ortho、HiYou、Xenia、Xenia Alt 与 Burmese。保留 HiYou ISO 单层符号键、Burmese 独立组合符和数字行、其余三项 ANSI 排列、完整 Base/Shift 与 AltGr 基础层回退，不复制、打包或运行参考布局资产
- 当前内置键盘图为一百九十八种：新增 Gallium v2 Matrix、Gallium NL、Maya、Gallaya Angle ANSI 与 Gallaya Angle ISO。Gallium v2 Matrix 按固定参考的实际声明保留 ANSI 物理类型，Gallaya ISO 保留额外 ISO 键和地区 Shift 符号；五项均覆盖完整 Base/Shift、AltGr 基础层回退、提示、模拟、反查、归档和 Layout Fluid，不复制、打包或运行参考布局资产
- 当前内置键盘图为二百零三种：新增 Gallaya Matrix、Minimak 4-key、Minimak 8-key、Minimak 12-key 与 Graphite Angle。五项均按固定参考的实际声明保留 ANSI 物理类型，完整覆盖 Base/Shift 与 AltGr 基础层回退；三个 Minimak 阶段保持各自渐进键位和英式 `£` Shift 符号，并全部接入提示、模拟、反查、归档和 Layout Fluid，不复制、打包或运行参考布局资产
- 当前内置键盘图为二百零四种：新增 Optimot。它完整覆盖 48 个 ISO 物理位置和 Base/Shift/Option/Shift+Option 四层；字母区的 `⌫` 位走原生向后删除动作，不会作为文本进入提示、计分或回放。布局同时接入提示、模拟、反查、归档和 Layout Fluid，不复制、打包或运行参考布局资产
- 当前内置键盘图为二百零九种：新增 Graphite Angle VC、Graphite Angle KP、Graphite Matrix、UGJRMV 与 ORNATE。五项均覆盖完整 ANSI Base/Shift 和 AltGr 基础层回退，保留三个 Graphite 底行差异、UGJRMV 特殊字母/符号及 ORNATE 非对称 Shift 配对，并接入提示、模拟、反查、归档和 Layout Fluid，不复制、打包或运行参考布局资产
- 原生设置窗口：难度、输入规则与字体大小会保存到本机
- 可选 26 种 Typebar 自有键击音、4 种 macOS 错误提示音及 0–100% 音量；默认关闭，不携带网页音频资产
- 原生设置窗口支持中英文关键词搜索，可过滤测试、显示、主题、账户和恢复默认设置分组
- 字数模式可启用“最后一词快速结束”：最后一词达到目标长度即可收尾；遇错停下或遇错删除时自动不生效
- 计时、字数及两种自定义循环模式均可选择无限练习；计时器/词数正向累计，Typebar 自有提示按需循环，Bail Out 或双击 Shift+Enter 会显示但不保存结果
- 三套原创内置主题（纸白、午夜、林地）可切换并随本机设置与备份保存
- 可选择跟随 macOS 深浅色，在原创纸白和午夜主题间自动切换
- 可选择每次新测试时在原创纸白、午夜与林地主题间随机切换；跟随系统时自动暂停随机切换
- 练习字体可切换 macOS 系统等宽、圆角、衬线或默认设计，也可浏览、搜索当前 Mac 已安装字体，或导入用户拥有的 TTF、OTF、WOFF、WOFF2；字体名称随设置归档，本地文件仅保存在这台 Mac
- 可创建、应用和删除本地自定义主题（背景、面板、强调色及明暗偏好），并随 Typebar 归档迁移；还可由用户主动粘贴 `monkeytype.com` 的公开自定义主题链接，导入其十色配置。链接只在本机解码 `customTheme` 查询值，绝不访问链接主机或参考服务。只有同时通过本机 HTTP(S) 图片白名单、适配与滤镜校验的背景设置才会一并应用；链接不会执行网页代码或带入原项目资源
- 原生账户设置可连接自建服务进行注册、密码或 GitHub/Google/Discord 登录、会话恢复、密码重置、邮箱验证、资料刷新、公开资料编辑、第三方方式关联/移除、为第三方账户添加或移除密码方式、撤销所有设备会话和退出；访问令牌按规范化服务地址分别保存在 macOS 钥匙串，切换服务器不会跨域发送旧令牌。公开资料可包含简介、键盘说明、GitHub、X / Twitter 用户名与 HTTPS 网站，并可关闭活动日历和连续练习摘要；两者默认按 UTC 分日，账户可在 −11 至 +12 小时内按半小时档固定一次公开日界，该选择独立于本机统计日界且不修改成绩时间。邮箱、令牌、本机日界和本机练习内容不会公开。移除第三方方式、添加密码、撤销会话与删除账户均须先完成一次性重新验证：密码账户验证当前密码，纯第三方账户在 macOS 系统授权窗口确认已关联身份；凭据只保存哈希、五分钟后失效且使用即作废。重置码仅能使用一次、20 分钟后过期，完成重置会注销该账户所有设备；验证邮件在注册或改邮箱后自动发送，也可手动重发，验证码只能使用一次并在 24 小时后过期
- 已关联 Discord 的用户可主动在公开资料、WPM 榜和 XP 榜展示 Discord 头像；服务端默认不返回关联，也会拒绝异常 ID 或头像哈希，原生客户端加载失败时回退系统人物图标
- 原生账户设置会显示由服务端已接受成绩解锁的十枚 Typebar 原创公开徽章，覆盖完成次数、准确率、速度、累计时长、语言与模式广度；用户可选择一枚在公开资料、WPM 榜和 XP 榜显示。默认不会公开其余已获得徽章；只有用户明确打开“公开显示全部已获得徽章”后，资料卡才额外显示它们，榜单仍只显示所选一枚。未选择、未解锁、封禁或删除相应服务端成绩时不会返回徽章。首次达到每枚徽章条件时，服务端会向当前账户投递一次不含提示或回放的私有奖励通知；重复上传同一成绩或后续同类成绩不会重复投递。参考中依赖开发者、捐赠或社区身份人工授予的徽章不会被伪造
- 原生账户设置可创建、重命名、禁用和删除最多五个 Typebar 开发者密钥；明文仅在创建时可见，服务端只保存哈希。密钥只允许自动化客户端通过 `X-Typebar-Access-Key` 读取或上传自己的成绩元数据，不能读取资料、同步数据或修改账户；设置页可查看近期服务端成绩，并以常规登录会话为每条成绩编辑最多五个原创标签
- 原生账户设置可在重新确认身份后重置服务端公开个人最佳而保留成绩、XP、徽章和排行榜；服务端以重置后的新接收成绩建立新 PB，本机历史与本机 PB 不受影响。也可另行永久清除当前账户的全部服务端成绩和相应 XP；本机练习历史、设置及其他账户数据不会受影响
- 原生账户设置可在不可撤销确认与重新验证后完整重置当前账户数据：服务端先幂等清除成绩、XP、PB、资料、密钥、同步档案和通知，再清理当前 Mac 的历史、预设、保存文本、设置、背景与字体；身份、会话、好友、屏蔽、投稿和统计日边界保留。服务端成功但本机失败时会明确提示安全重试；建议操作前先导出
- 自建服务可发布带可选计划日期的公开纯文本公告；正文支持当前地区的完整日期时间、日期和相对时间占位符；普通公告仅在当前 Mac 本机关闭，置顶公告持续显示至部署者删除，发布和删除只接受部署审核密钥
- 可保存、应用和删除完整测试预设
- 原创离线挑战会在完成页逐项验收最低或精确 WPM、精确 Raw、准确率、打字稳定度、最小时长、AFK 比例、错误数、精确 funbox 集合，以及完成时捕获的模式、语言、难度、标点、数字、实时速度、节奏光标和卷带设置；所有挑战默认限制 AFK 不超过 10%，也可收紧。旧成绩若缺少某挑战要求的显示快照会明确不能验收，而不会用之后变化的偏好设置猜测结果。挑战脚本、文案与内容均为 Typebar 自有，不复制参考项目资产
- 可用工具栏“命令”、⇧⌘K、与参考一致的 ⇧⌘P，或随快速重开设置变化的 Esc/Tab 搜索并执行重开、模式切换、15/30/60/120 秒、10/25/50/100 词、任意安全非负整数的自定义时长/字数、标点/数字开关、引语长度/收藏/搜索、全部 448 个本机语言与代码入口、难度、英式/美式拼写、引语重开策略、成绩保存，以及自由回退、严格空格、反向 Shift、遇错停下/删除、信心模式、快速结束、错字/组合输入显示、隐藏额外字符、简化重音输入和代码反缩进的全部固定枚举选项；大型有限测试按需扩展 Typebar 自有提示，不一次性生成巨型字符串。另可选择固定参考的 `default + 239` 个输入布局模拟命令，以及 3 档音量、关闭/26 种键击音、关闭/4 种错误音和关闭/1/3/5/10 秒倒计时提示；声音命令即时更新且不重开，输入布局关闭时回到 macOS 当前输入源；需重开的测试配置会退出当前挑战，含 Tab 的提示会把动态入口保护为 ⇧Tab
- 从命令面板选择具体键击音、错误音或倒计时秒数时会立即试听一次；关闭命令保持静默，所有声音仍来自 Typebar 自有合成或 macOS 系统资源
- 原生倒计时以测试开始时间的整秒网格驱动提示；运行循环短暂停顿后会补齐遗漏秒格，避免跳过结束前 1/3/5/10 秒的提示，但不会重复声音、延长测试或改变以真实墙钟时间计算的成绩
- 少于 130 秒的时间测试及少于 250 词的字数测试会本机监视计时交付延迟；首次超过 125ms 时只临时降低本次动效帧率，单次超过 500ms 或累计六次超过 250ms 时会停止本轮，以免保存不可信的成绩。长/无限测试、引语、禅和自定义文本不受该规则影响，重开即恢复用户的帧率偏好
- 命令面板还可即时选择 4 档平滑光标、主/节奏光标各 8 种原生样式，以及开启或关闭“重复本轮”后沿用上一轮节奏；这些呈现命令不会清空输入，其中节奏光标样式变更会退出当前挑战以保持条件可信。重复节奏仅作用于同词组的“重复本轮”链，保留其中最快的正常完成速度；中止、AFK 无效结果和普通重开都不会覆盖或自动启用它。另有固定 `paceCaret` 的关闭、同类 PB、活动标签 PB、上一轮、最近 10 次平均、过去 24 小时最佳与自定义速度 7 个入口；自定义值按当前速度单位输入并换算为规范 WPM，确认模式后会退出挑战并重开
- 命令面板提供 48 个固定显示选项，可即时切换实时进度、速度/准确率/Burst 样式、指标颜色与透明度、提示高亮、已输入效果、卷带与平滑滚动、完整提示行、速度单位、结果小数位和图表零基线；它们复用现有原生设置且不重开，实时速度、提示高亮和完整提示行变更会与固定参考同样清除当前挑战；卷带会进入完成时的挑战显示快照并按条件验收。WPH 仍可从设置选择，但按固定命令元数据不出现在命令面板
- 命令面板以固定 `changeTheme…` / `setCustomThemeId…` ID 列出内置与本机自定义主题；搜索结果活动项、鼠标指向或键盘移动到主题时会即时预览，移到非主题、无结果或关闭面板即恢复原显示，只有执行才保存选择。面板保持搜索输入焦点，可用 ↑/↓、Tab/⇧Tab 或 Ctrl-J/N/K/P 循环选择，Return 执行，Esc 清除全局搜索、返回分类或关闭。另只显示“收藏当前主题”或“取消收藏当前主题”中的有效一项；随机主题和跟随 macOS 深浅色时均作用于屏幕实际显示的内置主题，自定义主题继续从设置中的收藏控件管理
- 命令面板可即时选择四种 macOS 原生字体设计、此 Mac 实际安装的固定字体候选、输入字体家族/PostScript 名称，或打开完整本机字体搜索；未导入时显示本地字体文件入口，导入后可移除；改选其他字体时仅停用本地文件，并可从命令面板重新启用。名称进入设置归档，本地字体文件只留在这台 Mac，Typebar 不复制或打包参考网页字体
- 命令面板还可即时选择快速重开的关闭/Esc/Tab/Enter、盲打、完成后自动展开单词历史，以及单列表或手动分组浏览；十项行为命令直接更新既有持久设置，不清空输入或退出挑战
- 命令面板可关闭或自定义最低整体速度与最低准确率，并可关闭或用固定/弹性模式设置最低单词 Burst；速度按当前显示单位输入且不受旧 300 WPM 上限影响，取消输入不会改变当前挑战，确认后按新阈值重开
- 最低整体速度与准确率按测试开始后的真实整秒检查：准确率立即使用未圆整实时比例比较，整体速度在完成四个词后才比较；两者都只在严格低于设定值时停止本轮，且会显示具体失败原因。若极短轮在首个秒格前完成，不会由完成逻辑追溯为失败
- 固定 48 项 funbox 均可按原始名称或完整命令 ID 搜索切换，也可一次清除；`numbers`/`network` 别名、Memory 模式约束、无限测试限制和锁定重开均保留。`weakspot` 在当前 app 生命周期内以真实相邻输入间隔和错误罚时驱动每词 20 候选选择，不保存该瞬时评分且不参与 PB；持久化弱项分析和多语分别保留独立原生入口
- 命令面板可设置合规的 HTTP(S) 背景图片 URL、导入仅存于这台 Mac 的本地图片、移除两类自定义背景，并即时选择覆盖／完整显示／填满和四项滤镜；输入与布局修改不会重开练习，本地图片继续优先于 URL
- 命令面板提供固定的练习页、排行榜、关于、设置、账户、公开资料搜索和全屏七个导航入口；公开资料可匿名按自建服务的 2–40 字符展示名契约搜索，好友请求与举报仍只在登录后开放。全屏只切换承载当前命令 sheet 的 Typebar 主窗口
- 命令面板另以固定顶层 ID 提供编辑自定义文本、分享测试配置、下一个随机主题和退出登录；随机主题与登出只在动作当前有效时显示，执行复用既有原生编辑区、配置链接、瞬时主题池和按服务隔离的钥匙串会话。旧内部 `share` ID 仍可路由但不再重复列出；广告、Service Worker 缓存、隐藏调试项和 Monkeytype 品牌社群链接不进入 Typebar
- 命令面板提供固定 `importSettingsJSON`／`exportSettingsJSON`：原生等宽编辑器导出 v2 完整偏好快照、当前测试配置、自定义主题、自定义键盘、Layout Fluid 序列，以及计时、字数和自定义模式的五项独立限制记忆。导入会先检查版本、完整解码并规范布局后才应用，仍可读取 v1（缺失的模式限制从活动配置与既有默认值迁移）；空白、畸形或未知版本保持现有设置不变。设置 JSON 不包含成绩、提示、自定义练习正文、回放、保存文本、凭据或本地背景／字体文件；这些数据仍使用完整本机归档迁移
- 完成页另有自己的原生命令面板，可用页面“命令”或 ⇧⌘P 打开；下一轮、重复本轮、结果图导出始终可用，复制已练习词、单词历史和错词/慢词练习只在本轮确有对应数据时出现；“自选弱项练习”还可组合错词、前词上下文与慢词，空组合不能开始
- macOS“关于 Typebar”窗口从 bundle 显示版本/构建，解释本机数据与联网边界、核心指标和兼容性研究方法，并提供源码与问题反馈入口；不复制 Monkeytype 品牌页、广告或贡献者数据
- 应用菜单、关于窗口或命令面板可打开原生版本历史；仅在用户查看时分页读取 Typebar 自己的正式 GitHub Releases，以纯文本显示说明并过滤草稿、预发布和外部链接
- 可通过工具栏“分享”复制或导入自有 `typebar://test` 测试配置链接；也可离线导入网页端 `testSettings` 链接的模式、长度、自定义文本、标点/数字、语言、难度和固定 funbox。网页链接的主机只是序列化载体，Typebar 不会访问它；外部引语 ID 不对应 Typebar 自有引语内容时会安全选择本地引语。两类链接均不包含账户、成绩或本机设置
- 可从原生界面导入／导出版本化本地归档（设置、当前测试选择、结果、预设、自定义文本；当前为 v3，导入去重合并并兼容 v1/v2 及旧 v3 归档）
- 登录自建服务后，可从原生同步面板上传本机归档或拉取并合并远端归档；并发版本冲突会保留本机设置，把双方不同的预设、文本、主题和自定义键盘布局安全另存后重试上传。同步页会按规范化服务地址和账户显示这台 Mac 最近 50 条冲突副本记录，可独立清空；记录不含文本正文、成绩、归档载荷或凭据
- 自建服务可保存基本校验后的成绩，并提供按模式/语言筛选的全局与好友 WPM（全部时间、今天、昨天、本周）及 ISO 本周/上周 XP 排行榜；常规登录会话可在同步页查看自己在当前榜单范围的实际名次，即使该条目不在前 25/100 名。当天完成且可见的成绩会在结果页直接显示同模式、同语言的今日全局名次，点击后以相同筛选打开排行榜
- 完成成绩发送失败时，结果页保留本机成绩并提供“重新发送成绩”；同一成绩发送中不会重复提交，旧请求也不会覆盖后来完成的新成绩状态
- 可从榜单打开自建服务的公开资料卡（展示名、加入时间、完成/开始次数、服务端累计练习时长、最佳 WPM、可选简介/键盘说明/社交链接、带本地化星期/月定位、范围完成总数和五档动态强度图例的活动日历，以及当前/最长连续练习摘要；不含邮箱）
- 自建账户可随时从全局及好友 WPM/XP 榜隐藏；已保存成绩、XP、同步和本机历史仍保留
- 已登录后可按公开展示名搜索用户，在原生好友面板查看好友请求、接受请求、取消请求或解除好友；也可从榜单资料卡发送请求
- 主工具栏显示服务端当前账户的未读通知数；原生通知中心显示好友、私信与徽章奖励及当前数量/100 条上限，可刷新、逐条标为已读、逐条删除或经确认清空，操作后徽标即时更新；超限时仅淘汰该账户最旧通知，删除通知不会删除好友关系、私信或已解锁徽章
- 可启用最多五个本机活动标签；之后开始的完成成绩会自动写入这些标签，完整预设、归档、当前统计、当前设置历史筛选与活动标签个人最佳节奏引导均会保留相同语义；完成页会基于本机可比历史显示每个标签的首次、新增或既有 PB，并可开关已有标签 PB 的图表水平线
- 命令面板会列出当前活动标签和本机历史中的已有标签，可清除、逐项切换或新建；大小写/重音重复、超长名称和超过五个活动标签会被统一规则拒绝，进行中的练习仍保留启动时标签
- 实时 WPM、Raw WPM、单词 Burst、准确率和错误统计
- 练习区可选显示近 10 次同设置本机平均，或符合资格的同设置本机个人最佳；两者均不要求登录
- 测试完成后的原生结果页：WPM、准确率、Raw、错误、用时，以及按最终输入映射统计的“匹配/错位/额外/跳过”字符；标题区保留本轮模式、计时/字数或实际引语长度、语言及已启用的关键选项，引语成绩另显示完成时捕获的 Typebar 自有标题或社区署名，同一信息会保存到历史详情，本机新 PB 皇冠反馈、重开和历史入口保持可用
- 完成成绩会先显式确认写入本机；失败时结果页显示具体错误并可原地重试，保存成功前不会宣称本机 PB、编辑标签、进入历史或发布到自建服务
- 结果速度图可在图例中直接切换纵轴从零开始或按本轮数据自适应，并沿用既有持久化设置；该入口不改变成绩或回放
- 结果速度图可选择最近采样秒，显示该秒的可见速度/错误指标，并联动突出本机回放中同一时间窗真正涉及的单词；停顿秒不伪造关联，移出图表即清除
- 原生输入桥会在本机统计已闭合物理按键的按住时长、连续按下间隔与多键重叠时长；完成页和历史详情显示相应摘要，未释放的末键、未闭合重叠和自动重复不会伪造样本。发布不超过 122 秒的成绩时，客户端会先读取自建服务的公开能力；只有服务明确声明支持，才附带最多 12,000 个匿名毫秒样本和重叠总时长。载荷不含提示、输入字符、键码或回放，服务端校验后不持久化；旧服务、能力查询失败、长测试及无样本结果继续只提交汇总
- 结果页区分“重复本轮”（相同配置与提示）和“再来一次”（按当前选择生成新内容）；重测不会继承输入、计时或回放
- 完成页显示今天累计的本机练习时长和完成次数；未保存的成绩在本次运行中也会计入，避免遗漏练习模式
- 结果页可从本机回放复制实际输入，也可复制本轮实际发现的错词与按阈值筛选的慢词；缺少回放时明确拒绝生成，绝不从提示或统计推断文本
- 结果页可复制文字、复制 Typebar 原创结果卡 PNG，或通过 macOS 保存面板导出 PNG；卡片使用当前主题并显示准确度刻度，引语结果同时带最小来源标题
- 练习历史可将当前筛选后的本机成绩导出为 CSV；文件使用 UTC 名称和标准 CSV 转义，包含成绩、配置、标签、完成前重开次数、本机派生指标与四项字符分类，但不含提示、实际输入或回放
- 练习历史摘要随当前筛选即时统计开始次数、完成数与完成率、每次完成重开比、有效键入时长、估算词数，以及 WPM、Raw、准确率、稳定度的最高、平均和最近 10 次；速度类数值遵循当前显示单位
- 每日练习图随当前历史筛选的完整日期范围和本机统计日界更新，可切换完成次数、有效分钟、每日平均/最高速度、平均准确率、平均稳定度和每次完成重开比；仅绘制有成绩的实际日期并保留日期间隔，不会合成空日平均值，点按或拖动某天可同时查看全部七项指标
- 本机历史可按日期、速度、Raw、准确率或稳定度升降排序，每次渐进显示 10 条；CSV 导出全部匹配项并遵循当前排序
- 速度分布直方图随 WPM/CPM/WPS/CPS/WPH 单位换算并采用对应档宽，从零保留空档；异常大导入值安全汇入有界溢出档
- 速度与准确率历史趋势可拖动选择最近成绩，两图同步标记并显示完整本机摘要，可继续打开成绩详情或清除选择
- 历史统计与图表上方显示紧凑的当前筛选摘要，默认只显示“全部成绩”，复杂条件可横向滚动并由 VoiceOver 逐项读取
- 每日活动的练习分钟指标显示按真实练习日期拟合的原生虚线趋势，不把空白日误计为零分钟
- 历史列表行直接显示模式参数、四元字符统计和结果标签，长摘要保持单行并可悬停查看全文
- 账户设置可分页导出当前账户的全部服务端成绩 CSV，而不是只导出近期列表；快照变化会中止并提示重试，文件不含提示、输入回放、邮箱、令牌、本机历史或其他账户数据
- 结果页会在至少五个词有有效词速时，生成本机最慢四分位目标词的有限加权练习；无法计时的词不参与
- 结果页“导出”可按可调 WPM 阈值复制本轮慢词；默认阈值是有效单词 Burst 的平均值，严格低于阈值的已输入目标按原顺序复制，重复目标保留，无法计时项排除
- 结果页可从本机输入回放重建最多 120 秒的 WPM、Raw、Burst 与错误轨迹；三条可选轨迹及普通/活动标签 PB 基线均可独立开关，Burst 可切换默认平滑或原始尖峰，并保存显示偏好
- 输入回放在播放、暂停和拖动时同步显示该时刻的速度，遵循当前 WPM/CPM/WPS/CPS/WPH 单位；长回放不受结果图 120 秒密度上限影响
- 输入回放可直接点按目标文本中已经到达的字符定位并暂停；定位按词与词内位置重建，前一词的多余输入不会错开后一词，未到达字符保持不可点，滑杆继续提供连续定位和辅助功能后备
- 输入回放的实际输入轨迹会逐字区分正确、错误与额外字符；错误使用语义错误色，额外字符同时加删除线，退格会按时间轴撤回对应字形，进入下一词后重新对齐目标
- 输入回放播放时遵循当前按键音、错误音、音色与音量设置；错误字符和仍含错误的单词提交会播放错误音，错误音关闭但按键音开启时再回退为按键音。拖动、点选字符、重置与代码自动缩进保持静音
- 以空格分词的完成结果可一键用本次实际输错的目标词重开练习，不会把未完成的后续词误判为错词
- 错词练习可选择仅练去重错词，或按每次实际尝试保留“前词 + 错词”上下文；两者都只来自本轮本机输入
- 以空格分词的完成结果会显示本次实际尝试词的目标/输入对照与正误状态
- 可选按本轮实际输入速度为结果单词历史显示 Typebar 原创五分位 Burst 热力图；没有可测间隔的词保持中性
- SwiftData 本地成绩存储；容器打不开时保留原文件并显示可定位、可复制诊断的恢复页，不静默创建空库
- 原生历史列表，显示、标记、添加标签并可删除本地成绩
- 本地历史汇总、WPM 趋势图、按完整筛选历史绘制的每日完成/练习分钟柱状图、可在最近 12 个月（52 周）与有本机记录的自然年份之间切换、带本地化星期/月标记、当前范围完成总数和五档动态强度图例的活动日历与个人最佳标记；色阶从当前可见日的已知完成数（含零）派生，并裁剪极端值，避免一次异常导入压平日常活跃度。可按同类计时/字数设置查看本机个人最佳表。可首次设定并锁定本机统计日分界（−11 至 +12 小时，每 30 分钟），连续天数和两类活动图同步采用该分界；切换活动范围不修改成绩
- 新增原创 العربية المصرية 离线词流及四档引语，使用 macOS Arabic 输入源、RTL 提示和原生连写字形，暂不进入双向多语混排；固定参考配置的 `bcp47: ar-EG` 映射为 `ar` 知识短文与 `ar-EG` 系统朗读。参考未设置 `noLazyMode`，因此保留用户显式选择的简化输入，但不继承 Typebar 针对标准 Arabic 的自动快捷开关；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 العربية المغربية 离线词流及四档引语，使用 macOS Arabic 输入源、RTL 提示和原生连写字形，暂不进入双向多语混排；固定参考配置的 `bcp47: ar-MA` 映射为 `ar` 知识短文与 `ar-MA` 系统朗读。参考未设置 `noLazyMode`，因此保留用户显式选择的简化输入，但不继承标准 Arabic 的自动快捷开关；其 `orderedByFrequency: false` 会在启用 Zipf 时显示不支持提示而保留修饰器，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 پښتو 离线词流及四档引语，使用 macOS Pashto 输入源、RTL 提示和原生连写字形，暂不进入双向多语混排；固定参考配置的 `bcp47: ps` 映射为 `ps` 知识短文与 `ps` 系统朗读。参考设置 `noLazyMode: true`，因此非自定义练习禁用简化输入，而自定义文本仍保留该能力；未声明词频排序，启用 Zipf 时显示可能不支持提示而保留修饰器，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 سنڌي 离线词流及四档引语，使用 macOS Sindhi 输入源、RTL 提示和原生连写字形，暂不进入双向多语混排；固定参考配置的 `bcp47: sd` 映射为 `sd` 知识短文与 `sd` 系统朗读。参考未设置 `noLazyMode`，因此保留用户显式选择的简化输入，但不继承标准 Arabic 的自动快捷开关；其 `orderedByFrequency: false` 会在启用 Zipf 时显示不支持提示而保留修饰器，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Occitan 离线词流及四档引语，使用 macOS Occitan 输入源和 LTR 空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: oc-FR` 按首段映射为 `oc` 知识短文，并精确映射为 `oc-FR` 系统朗读。参考未设置 `noLazyMode` 或词频排序，因此保留用户显式选择的简化输入；启用 Zipf 时显示可能不支持提示而保留修饰器，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Oromo 离线词流及四档引语，使用 macOS Oromo 输入源和 LTR 空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: om` 映射为 `om` 知识短文与 `om` 系统朗读。参考未设置 `noLazyMode`，因此保留用户显式选择的简化输入；其 `orderedByFrequency: true` 保留 Zipf 高频词，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Македонски离线词流及四档引语，使用 macOS Macedonian 输入源和 LTR 空格词界，可加入默认和自选多语混排；固定参考配置没有 BCP-47，因此知识短文和系统朗读严格回退为 `en` 与 `en-US`。参考设置 `noLazyMode: true`，普通练习禁用简化输入而自定义文本保留例外；词频排序未定义，Zipf 显示可能不支持提示而保留修饰器，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Қазақша 离线词流及四档引语，使用 macOS Kazakh 输入源和 LTR 空格词界，可加入默认和自选多语混排；固定参考配置没有 BCP-47，因此知识短文和系统朗读严格回退为 `en` 与 `en-US`。参考设置 `noLazyMode: true`，普通练习禁用简化输入而自定义文本保留例外；词频排序未定义，Zipf 显示可能不支持提示而保留修饰器，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Tiếng Việt 离线词流及四档引语，使用 macOS Vietnamese 输入源和 LTR 空格词界，可加入默认和自选多语混排；固定参考配置没有 BCP-47，因此知识短文和系统朗读严格回退为 `en` 与 `en-US`。参考未设置 `noLazyMode`，因此保留用户显式选择的简化输入；词频排序未定义，Zipf 显示可能不支持提示而保留修饰器，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Jyutping 离线词流及四档引语，保留 ASCII 与声调数字的空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: zh-Hant` 按首段映射为 `zh` 知识短文，并精确映射为 `zh-Hant` 系统朗读。参考未设置 `noLazyMode`，因此保留用户显式选择的简化输入；词频排序未定义，Zipf 显示可能不支持提示而保留修饰器，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Pinyin 离线词流及四档引语，保留 ASCII 转写的空格词界，可加入默认和自选多语混排；固定参考配置未提供 BCP-47，因此知识短文和系统朗读严格回退为 `en` 与 `en-US`。参考未设置 `noLazyMode`，因此保留用户显式选择的简化输入；词频排序未定义，Zipf 显示可能不支持提示而保留修饰器，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Western Armenian 离线词流及四档引语，使用独立的西部亚美尼亚语正字法和 LTR 空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: hyw` 同时映射为 `hyw` 知识短文与系统朗读。参考未设置 `noLazyMode` 或词频排序，因此保留用户显式选择的简化输入，并在 Zipf 启用时显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Bashkir 离线词流及四档引语，使用 macOS 原生 LTR 西里尔排版和空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: ba` 映射为 `ba` 知识短文与系统朗读。参考未设置 `noLazyMode`，因此保留用户显式选择的简化输入；其 `orderedByFrequency: true` 保留 Zipf 高频词，它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Euskera 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: eu` 映射为 `eu` 知识短文与系统朗读。参考未设置 `noLazyMode` 或词频排序，因此保留用户显式选择的简化输入，并在 Zipf 启用时显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Frisian 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: fy-FY` 按首段映射为 `fy` 知识短文，并精确映射为 `fy-FY` 系统朗读。参考未设置 `noLazyMode` 或词频排序，因此保留用户显式选择的简化输入，并在 Zipf 启用时显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 isiZulu 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考配置未提供 BCP-47，因此知识短文和系统朗读严格回退为 `en` 与 `en-US`。参考未设置 `noLazyMode` 或词频排序，因此保留用户显式选择的简化输入，并在 Zipf 启用时显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 ʻŌlelo Hawaiʻi 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考基础与 1k 配置的 `bcp47: haw` 映射为 `haw` 知识短文与系统朗读。参考未设置 `noLazyMode`，其 `orderedByFrequency: true` 保留 Zipf 高频词；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Taqbaylit 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: kab` 映射为 `kab` 知识短文与系统朗读。参考未设置 `noLazyMode`，其 `orderedByFrequency: false` 会在启用 Zipf 时显示不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Maltese 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: mt` 映射为 `mt` 知识短文与系统朗读。参考未设置 `noLazyMode` 或频率排序，启用 Zipf 时会显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 toki pona 基础、ku suli 与 ku lili 三个独立离线选择及四档引语。ku suli 在 Typebar 自有基础集合上增加 15 个独立整理的核心词，ku lili 使用与 ku suli 互斥的 20 个扩展词；三者均使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排。固定参考配置未提供 BCP-47，知识短文与系统朗读按 `en`／`en-US` 缺省路径处理；`noLazyMode: true` 会在普通练习禁用简化输入但保留自定义文本例外，Zipf 显示可能不支持提示。三者均接入预设、归档、社区投稿、成绩和排行榜，不导入官方 ku 词表。
- 新增原创 isiXhosa 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；主参考配置的 `bcp47: xh` 映射为 `xh` 知识短文与系统朗读。参考未设置 `noLazyMode` 或频率排序，启用 Zipf 时会显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Tibetan 离线词流及四档引语，使用 macOS 原生 LTR 连写字形与空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: bo-TI` 映射为 `bo` 知识短文与 `bo-TI` 系统朗读。其 `joiningScript: true` 使用原生塑形、较紧行距并避免圆点逐字替换；`noLazyMode: true` 会在普通练习禁用简化输入但保留自定义文本例外，Zipf 显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Kyrgyz 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: ky-KY` 映射为 `ky` 知识短文与 `ky-KY` 系统朗读。参考未设置 `noLazyMode` 或频率排序，启用 Zipf 时会显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Yiddish 离线词流及四档引语，使用 macOS 原生 RTL/连写排版和空格词界；固定参考配置的 `bcp47: yi` 映射为 `yi` 知识短文与系统朗读。其 `joiningScript: true` 使用原生塑形、较紧行距并避免圆点逐字替换；参考未设置 `noLazyMode` 或频率排序，保留显式简化输入与 Zipf 未知提示。它可在自选多语中搜索和勾选；隔离窗口已显示双向词流，但 Yiddish 实际输入尚未完成交互验收。预设、归档、社区投稿、成绩和排行榜已有自动化覆盖。
- 新增原创 Udmurt 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考配置未提供 BCP-47，知识短文与系统朗读按 `en`／`en-US` 缺省路径处理。参考未设置 `noLazyMode` 或频率排序，启用 Zipf 时会显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Yoruba 离线词流及四档引语，使用 macOS 原生 LTR 排版、空格词界与声调字符，可加入默认和自选多语混排；固定参考配置未提供 BCP-47，知识短文与系统朗读按 `en`／`en-US` 缺省路径处理。参考未设置 `noLazyMode` 或频率排序，启用 Zipf 时会显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Swahili 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考配置未提供 BCP-47，知识短文与系统朗读按 `en`／`en-US` 缺省路径处理。其 `noLazyMode: true` 会在普通练习禁用简化输入，但保留自定义文本例外；Zipf 显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Kinyarwanda 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考配置的 `bcp47: rw-RW` 映射为 `rw` 知识短文与 `rw-RW` 系统朗读。其 `noLazyMode: true` 会在普通练习禁用简化输入，但保留自定义文本例外；`orderedByFrequency: true` 启用 Zipf 高频词；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Shona 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定参考配置未提供 BCP-47，知识短文与系统朗读按 `en`／`en-US` 缺省路径处理。参考未设置 `noLazyMode` 或频率排序，保留简化输入，启用 Zipf 时会显示可能不支持提示而保留修饰器；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Belarusian Łacinka 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排；固定配置的 `noLazyMode: false` 保留简化输入，未提供 BCP-47 或词频排序，知识短文与朗读按 `en`／`en-US` 缺省路径处理，Zipf 显示可能不支持提示；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Qırımtatarca 与 Къырымтатарджа 离线词流及各自四档引语，作为两个独立书写选择使用 macOS 原生 LTR 排版和空格词界，均可加入默认和自选多语混排。固定参考的十个相关词表档位均定义 `noLazyMode: true` 与 `bcp47: crh-CRH`，故普通练习禁用简化输入而自定义文本保留例外；知识短文使用 `crh`，系统朗读精确使用 `crh-CRH`，Zipf 显示可能不支持提示。两者均已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 tlhIngan Hol 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排。固定参考基础与 1k 配置均定义 `bcp47: tlh`，未定义 RTL、连写、`noLazyMode` 或词频排序；大小写和词内 `'` 保留为输入语义而非装饰标点。知识短文与系统朗读均使用 `tlh`，保留简化输入，Zipf 显示可能不支持提示；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Quenya 离线词流及四档引语，使用 macOS 原生 LTR 排版和空格词界，可加入默认和自选多语混排。固定参考配置未定义 BCP-47、RTL、连写、`noLazyMode` 或词频排序，知识短文与系统朗读严格按 `en`／`en-US` 缺省路径处理；保留显式简化输入，Zipf 显示可能不支持提示；它已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Viossa 与 Viossa · Njutro 离线词流及各自四档引语，作为独立的 LTR 空格分词练习加入默认和自选多语混排。两项均未提供 BCP-47，知识短文与系统朗读严格按 `en`／`en-US` 缺省路径处理，且 `orderedByFrequency: false` 会显示 Zipf 不支持提示；Njutro 额外按 `noLazyMode: true` 在普通练习禁用简化输入、自定义文本保留例外。两个词流都是 Typebar 明示的原创练习 idiolect，不导入参考词表或引语，均已接入预设、归档、社区投稿、成绩和排行榜。
- 新增原创 Te reo Māori 离线词流及四档引语，保留长元音 macron 并作为 LTR 空格分词练习加入默认和自选多语混排。固定参考仅提供 `maori_1k`，未定义 BCP-47、RTL、连写、`noLazyMode` 或词频排序，故知识短文与系统朗读严格按 `en`／`en-US` 缺省路径处理，保留简化输入并显示 Zipf 可能不支持提示；它已接入预设、归档、社区投稿、成绩和排行榜，且不导入参考词表或引语。
- 新增原创 Lojban · gismu 与 Lojban · cmavo 离线词流及各自四档引语，作为独立的 LTR 空格分词练习加入默认和自选多语混排。前者只练习五字母词根，后者独立保留 `.` 与 `'` 的语言内输入语义。两个固定参考配置均有 `noLazyMode: true`，故普通练习禁用简化输入而自定义文本保留例外；均未定义 BCP-47、RTL、连写或词频排序，知识短文与系统朗读严格按 `en`／`en-US` 缺省路径处理，Zipf 显示可能不支持提示。两个词流不导入参考词表或引语，均已接入预设、归档、社区投稿、成绩和排行榜。
- 新增 Unicode Ol Chiki 的 `ᱥᱟᱱᱛᱟᱲᱤ`（Santali）离线词流及四档 Typebar 自有练习文本，作为 LTR 空格分词选择加入默认和自选多语混排。固定参考只定义 `bcp47: sat-IN`，因此知识短文使用 `sat`、系统朗读使用 `sat-IN`，保留显式简化输入并在 Zipf 启用时显示未知支持提示；它已接入预设、归档、社区投稿、撤回、成绩和排行榜，且不导入参考词表或引语。
- 新增 Bulgarian Latin、Nepali Romanized、Persian Romanized、Sanskrit Roman 与 Urdu Roman 五种独立的 LTR 空格分词练习；每种都有 Typebar 自写词流和四档文本，不导入参考内容，也不宣称运行时可逆转写。它们按固定元数据分别处理简化输入、Zipf、百科和系统朗读，并全部进入默认／自选多语混排、预设、归档、社区投稿、撤回、成绩和排行榜。
- 新增 Hinglish、Tanglish 与 Urdish 三种独立的拉丁字母代码混合练习；每项均使用 Typebar 自写词流和四档文本，不导入参考或网络语料，也不把自然拼写变体伪装成统一标准。固定配置均未提供 BCP-47、`noLazyMode` 或词频排序，因此三者使用 LTR 空格词界、`en`／`en-US` 在线与朗读回退、可选简化输入和 Zipf 未知提示，并接入多语混排、预设、归档、社区投稿、撤回、成绩和排行榜。
- 新增 Ἑλληνιστικὴ Κοινή、Pig Latin 与 Lorem Ipsum · Typebar。Koine Greek 使用 Typebar 自写的多调希腊语词流和四档文本，并按 `el`／`el-GR` 处理知识短文与朗读；Pig Latin 只确定性转换 Typebar 自有英语内容；Lorem Ipsum 只使用 Typebar 自写伪拉丁内容。三者均使用 LTR 空格词界并接入多语混排与完整服务数据面，后两项按固定 `noLazyMode` 配置禁用普通练习简化输入。
- 当前内置键盘图为二百四十四种：新增独立的 Hungarian (ISO)、JCUKEN (ANSI) 与 Bulgarian (BDS)，保留它们各自的 ISO/ANSI 物理行、符号层与数字行显示策略。固定官方布局矩阵已达到 239 项精确原生、0 项相关替代、0 项回退；这不代表整个重写范围已经完成，也不复制、打包或运行参考布局资产
- 811 个客户端测试（在固定参考验收中 1 项跳过），覆盖引擎、内容、存储、偏好设置、预设、统计、归档、CSV 导出、账户响应、挑战条件、命令目录、官方布局矩阵、随机词流避重、长测试新批次续词与原生多行提示跟随滚动
- 计时模式的 Layout Fluid 按测试开始后的整秒时钟切换键盘提示和显式模拟布局，并在每段切换前显示 3/2/1 秒下一布局提示；字数模式仍按完成词数分段。该行为仅影响当前轮次，不改写已保存键盘设置或任何成绩数据
- 117 个自建服务自动化测试，覆盖账号、完整账户数据重置、密码重置与邮箱验证、一次性重新验证与会话撤销、OAuth 授权码/PKCE/一次性状态、第三方与密码身份关联保护、Discord 头像公开隐私、十枚服务端公开徽章的边界、选择、撤销与幂等奖励通知、公开资料 UTC 连续练习/活动隐私/开始次数与搜索、公开个人最佳重置纪元、通知容量与隔离、开发者密钥与私有远端成绩及标签管理、排行榜隐身、好友关系、同步、成绩、匿名按键时序、WPM/XP 排行榜、结果回执今日名次、审核引语/资料举报、社区评分、服务公告、请求限速与维护模式

## 后续范围（尚未完成）

- 更多原创语言与物理键盘映射
- 真实 macOS 设备与第三方账户验收
