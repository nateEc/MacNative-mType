# 官方输入路径审计

2026-10-02 音乐 Shift 页面／窗口作用域增量（最终门禁已通过）：固定 [modifier effect](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/states/modifiers.ts) 只在 test 页注册左右 Shift／Alt 的 keydown/up，切页先清逻辑状态；[PageName](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/pages/page.ts#L8-L20) 与测试页的弹层不是同一概念。本增量用独立弱窗口／视图 owner 注册表显式标记主练习与结果窗口；历史、弱项、同步账户／榜单／资料和好友展示期间为非测试页，设置／关于／版本窗口未标记，命令／挑战／配置等测试页 sheet 继承 sheetParent 宿主。标记 false 的 sheet 可显式阻断继承。不是按窗口标题猜测，不借用长测试关闭保护注册表，不改关闭／退出授权。

监听器继续全 app 更新最后键码／Caps，并识别所有物理修饰键按下／释放；仅选中的练习作用域能更新逻辑 Shift。切到非测试页、返回或换到另一练习窗口只 resetPracticeShift，不停样本／音乐，不清音阶、主音量或最后键码；物理侧键记录保留，非测试页按住 Shift 不能在回来后的普通 Q 上复活逻辑状态。相同页面的 sheet／key 通知不清 Shift；没有监听 resign-key，暂离 app 本身不是切页。注册／拆除和 willClose 发布同步通知，didBecomeKey 与每次键事件同步校正选中作用域，鼠标切页后无需等下次按键才清状态；安装回调重入时返回前再校正。stop 先退休 generation 并移除自身通知，再卸载监听。注册表弱持有窗口，视图 owner UUID 独立移除；作用域用独立 UUID，不把可复用对象地址当活动页身份，全部 owner 退出后的重新注册有新身份，未强迫测试分配器复用地址。同步 NSView 挂接／拆除避免旧异步注册；元数据视图不命中鼠标，SwiftUI 禁用其 hit testing／辅助功能呈现，没有新增交互元素。

行为证据：先行 3 项真实执行产生 6 个失败断言，另注册内切页 1 项产生 1 个预期失败断言；首次相关 94 项通过，所有补证后相关 104 项零失败（约 0.37 秒）。新增 13 项：监听总 33 项、作用域注册／非交互视图 7 项，已有音乐 22 项保留。用真实未分发 NSEvent、NotificationCenter selector 回调及无窗口 NSView 进行隔离检查；安装／移除、当前键窗口与父关系用显式自有替身，不创建 NSWindow，不启动 app，不调用真实 sendEvent，不播放音频或写真实数据。只读 Node v24.19.0 类型擦除／内存执行实际 modifier 模块，signal/effect/Caps/document 为明确自有桩：左 Shift→settings→off-page 右 Shift→test→普通 Q→右 Shift 按下／释放，逻辑 Shift 为 true/false/false/false/false/true/false，Caps 全程 true；仅该实际 modifier 模块的监听数 test 为 1/1、settings 为 0/0，不冒称同时执行了声音控制器全局监听、浏览器或上游 Vitest，没有参考代码／资产入仓。最多三轮会话内决策／风险复核，非独立评审；实机 SwiftUI 窗口／sheet 生命周期、系统通知顺序／多窗口听感、菜单 tracking loop／自动失焦丢事件、IME、多设备和全 Alt 行为仍未验收。本增量不等于原版所有修饰状态路径已完成，样本随机变体、16 号混响、浏览器 DSP 等仍缺口。新增三个人工项总 711 个，均待验收；历史作用域／复位缺口由本增量部分补齐，不据此关 goal。归档／成绩／SwiftData 和持久化音型未改，goal active。

本页面／窗口作用域增量完整门禁通过：客户端 1,847 项零失败（360.745 秒）、服务端 131 项零失败（1.534 秒），711 项人工场景、固定参考／元数据／原创性审计及未打开的应用打包全部通过。完整门禁内明确的 testOptionalHundredThousandWordEndurance 实际执行并通过（38.746 秒），在临时日志自动清理前核对，不只是环境变量或预览生成；它仍只证明文本引擎，不证明设备声音压力。所有测试串行，编译／测试期间未编辑源码，本轮没有启动 Typebar 图形实例、播放音频、写真实数据库或改动持久化结构。完整 goal 保持 active，不能把本增量当作原版全功能完成或多窗口实机验收。

2026-10-02 练习重置音乐 Shift 增量（最终门禁已通过）：依据固定 [modifier 模块](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/states/modifiers.ts) 与 [测试 reset](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L297)，把可重置的左右逻辑 Shift 与监听器的物理侧键转换记录分离。beginPracticeAttempt 清逻辑 Shift 并停止旧样本，不清 CapsLock、最后键码、音乐实例、试听／练习音阶状态、样本原型缓存或主音量；普通 keyDown、Caps 切换、未知修饰和其他修饰键释放均不从原始 aggregate Shift 复活旧状态。物理记录保留，所以无设备位合成事件的释放回退仍可正确识别。普通 clearAllSounds 仅停样本，不承担练习重置。正常重开、结果重复与允许的在线内容替换三处在既有守卫后接入；被锁定／拒绝／过期分支不改动，三处私有 SwiftUI 入口仅代码复核／编译，未运行真实按钮或网络替换 UI。

行为优先红阶段：仅添加新入口的旧停样本行为占位及三项测试，真实执行 3 项产生 6 个预期失败断言；实现后先 89 项通过，补证后相关 92 项零失败（约 0.44 秒），包括 MusicKeyboardMonitorTests 27 项与 MusicalClickSoundTests 22 项。修正一项旧测试的事件序列，显式发 Shift 释放；旧序列误把独立 Caps 事件当作 Shift keyup，新增测试保留该反例而非放宽频率断言。后补三项覆盖启动持有 Shift 的普通键、Caps 不合成 Shift 释放、音阶／在播音乐／主音量／原型缓存保留；它们是复核证据，不冒称先行红证据。

只读 Node v24.19.0 类型擦除并内存执行实际 modifier 模块，用显式自有 signal/effect/Caps 桩：左 Shift 按下→reset→带 shiftKey 的普通 Q→右 Shift 按下→右 Shift 释放的逻辑 Shift 实际为 true/false/false/true/false，Caps 全程 true。未复制参考代码／资产；不是浏览器、上游 Vitest 或硬件测试。本会话有界决策／风险复核验证最强反例为重开后仍物理按住左侧再释放右侧，保留物理历史而不导入聚合标志；不是独立评审。新加三个人工场景均待验收，总 708 个唯一项，不抬升为实机通过。原版完整页面切换、非测试页左右 Shift 监听作用域、跨窗口／IME／丢事件、实际声音设备与浏览器 DSP、样本随机变体和 16 号混响仍待完成；旧历史记录的重置缺口由本增量部分补齐，不据此关闭 goal。归档／成绩／SwiftData 与持久化音型结构未改变；本轮不启动 Typebar 图形实例、不播放音频、不写真实数据。

本练习重置增量完整门禁通过：客户端 1,834 项零失败（362.349 秒）、服务端 131 项零失败（1.449 秒），708 项人工场景、固定参考／元数据／原创性审计与未打开应用打包通过。完整门禁带 TYPEBAR_ENDURANCE_TESTS=1；门禁退出会清理详细日志，故另用 --skip-build 单独补跑明确的十万词测试，1 项实际执行通过（39.092 秒）并保留独立日志，不仅凭环境变量或生成预览宣称耐力通过。两轮串行、没有编译期间修改源码，没有启动图形实例；十万词只证明文本引擎，不证明声音设备压力。goal 保持 active，不将本增量当完整重写验收。

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


2026-10-02 最终门禁（原文有限末提交）：客户端 1552 项（零失败／零跳过，约 300.37 秒）、服务端 131 项（零失败／零跳过）、固定参考／原创性及兼容审计、673 个唯一人工场景清单与未开窗 macOS 应用包验证全部通过；完整门禁显式启用十万词耐力。新增 9 项，先行 28 个有效失败及后续 3 个末空目标失败；旧末 LF 夹具更正后最终聚焦 44 项通过，首轮相关 285 项的 3 个旧夹具失败保留阶段性质，不计该批全部通过。仅关闭列出的原文有限末词单提交裁切／空目标保护，TST-04／Funbox 保持部分状态；原文 CR／CRLF、连续尾空格、完整 Funbox／Unicode／拒绝历史／IME／设备仍开放。未启动 GUI、不写真实库、不回填原文／偏移／成绩、不改变版本或部署；清单不是设备验收，goal active。

2026-10-02 原文有限目标末提交增量（实施与阶段证据，最终结果见上文）：固定 [初始化裁切](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L540-L542)、[续批裁切](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L654-L657) 与 [非空词保护](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-words.ts#L79-L89) 表明：仅全部生成后移除非空末词的 ASCII 空格／LF 提交，不移除空词唯一 LF。原文有限工厂与最终续块现于文本变换之后独立裁切练习目标，并同步已有无空格目标元数据；中间块仍需真实提交，原文游标、字符偏移与持久数据不裁切。

新增 `FiniteFinalCommitTests` 9 项：有效首轮 8 项／28 个失败断言，原始脚本夹具违反既有清理／摘要校验的一项 contentMismatch 不计产品反例；纠正夹具后仍有同样 28 个有效失败，0 意外错误。8 项修复后通过；有界会话内风险复核再产生 1 项／3 个无空格最后空目标失败，已修复，首轮相关 285 项有 1 个旧末 LF 夹具的 3 个失败断言（新增 9 项全部通过，实际十万词约 35.98 秒通过），不能称该批全部通过。按固定源纠正其渲染目标与实际会话进度断言，并增加零错误、原始块不变守卫；最终聚焦 44 项零失败／零跳过通过（约 0.91 秒）。完整门禁结果见上文。覆盖三难度、关闭 Quick End、内部与最终 LF、空槽保留、错词进度、原文跨 10,000 字符块与独立分块、noSpaces／uppercase、重复和正式结果／回放／归档；脚本验证保持原有规范化与摘要，不据此声称原始 LF 脚本会被保留。

本条只关闭已列非空末词单提交裁切与空目标保护，不关闭完整原文 CR／CRLF、连续尾空格、零目标／跨换行／变换重排 Funbox、全部 Unicode 导航、拒绝输入历史、IME／实体键盘／设备。政策级空目标元数据用例不等于全部 Funbox 或设备验证。仅未来原文有限练习的渲染目标改变，保存原文、旧成绩／回放、游标和版本不回填；旧二进制行为兼容未实测。不写真实库、不部署、未启动 Typebar；兼容与风险技能限定变更边界，不冒称独立评审，TST-04／Funbox 仍为部分状态，goal active。

2026-10-02 最终门禁（长文本输入历史进度）：客户端 1543 项（零失败／零跳过，约 301.32 秒）、服务端 131 项（零失败／零跳过）、固定参考／原创性及兼容审计、671 个唯一人工场景清单、未开窗 macOS 应用包验证全部通过。相关 276 项包含新增 22 项及实际十万词耐力用例（约 36.39 秒），完整门禁同样显式启用耐力。有效先行证据为首批 21 个断言失败及后续 1 个旗帜删除失败；编译和空白终态／映射夹具错误另记，不计产品反例。只关闭列出的输入历史进度证据，不升级 TST-04／Funbox 部分状态；原文控制符、非空末词 LF、拒绝事件、完整 Unicode／组合／IME／设备继续开放。未启动 GUI、不写真实库、不回填历史、不改变持久格式或部署；671 清单不是设备验收，goal active。本条替代下文本轮的最终“待执行”，早期阶段与旧匹配工具证据保留其边界。

固定源码依据：[进度仅检查最后字段显示长度](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L987-L1028)、[导航前捕获输入快照](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/insert-text.ts#L273-L298)、[最后错误空格的 trimEnd 特例](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/events/helpers.ts#L123-L151)、[已尝试字段与退回后的空值](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/events/stats.ts#L519-L548)。这些是固定源阅读与自有原生反例，不是执行上游测试／浏览器 DOM 的证据；进度处注释与导航前快照对 ASCII 提交的表述不同，本轮以实际事件写入与读取路径为准。只重用自有 ECMAScript 空白标量谓词，不把引语准备套到保存原文，也不复制原版实现或夹具。

2026-10-02 长文本输入历史进度增量（实施与阶段证据，最终结果见上文）：实际桌面的中止／失败／AFK 路径不再使用匹配前缀；独立投影既有原生接受输入与删除事件，按已尝试字段数推进原文偏移，仅扣除最后一个 UTF-16 长度不足显示目标的字段。错词无需文字相等，ASCII 提交可留在快照中，必需 LF／下划线后缀属于显示长度；严格或 word-stop 保留的分隔符不伪造导航。删除后的空未来字段保留历史身份；组合标记与跨事件旗帜重组按实际删除标量撤销。无空格路径复用现有原词目标及边界，仅有已列 ASCII 用例证据。

证据：新增 `LongTextInputHistoryProgressTests` 22 项。先以无行为变化的会话重载接线建立实际调用路径反例：18 项／21 个有效先行失败；首轮编译夹具错误排除。18 项修复后通过，风险复核另有 1 个真实旗帜删除失败；原始空白夹具的终态／输入映射错误不计产品反例，修剪边界改为明确的政策级测试，不冒称 NBSP／BOM 原样输入。最终 21 项聚焦通过后补充 10,001 LF 连续跨块守卫；相关 276 项零失败／零跳过通过（约 68.33 秒），包含全部新增 22 项；日志确认 `CustomSequentialStreamingTests.testOptionalHundredThousandWordEndurance` 已实际运行并通过（约 36.39 秒），不只依据环境变量。完整门禁结果见上文。内存 SwiftData／正式归档覆盖错词新偏移、旧记录不变、结果／回放及去重／删除保护。

本条只替代下文列出路径的“错误词历史、严格／停止／删除进度仍开放”结论，不关闭全部组合。原文 CR／CRLF、非空末词 LF 裁切、拒绝输入的空字段、零目标／跨换行 Funbox、所有 Unicode 导航／IME／实体键盘和设备仍开放；结果终态与字形映射不因本轮更改，不能把政策测试当作实际 DOM 或设备证据。旧 `typed:` 匹配工具保留独立契约，不作为桌面进度等价证据。仅未来练习结束时计算，不改导航／计分／回放格式、持久字段或版本，不回算旧原文／成绩／进度，不写真实库或部署；旧二进制降级未实测。有界会话内风险／迁移复核，不冒称独立评审；TST-04／Funbox 保持部分状态，goal active，未启动 GUI。

2026-10-02 最终门禁（长文本 LF 空槽）：客户端 1521 项（零跳过／零失败，约 303.50 秒，显式十万词已执行）、服务端 131 项（零跳过／零失败）、固定参考／原创性及兼容审计、669 个唯一人工场景清单和未开窗应用包检查全部通过。新增 13 项，首轮 11 项有 28 个有效先行失败；相关 85 项的旧 LF 夹具失败已按固定源纠正，最终聚焦 14 项零失败／零跳过。只关闭列出的准入、完整 LF 块与 normal 匹配前缀进度证据；错误词历史、严格／停止／删除后导航、原文 CR／CRLF、完整控制符／Funbox／Unicode／IME／设备仍开放。未启动 GUI、不写真实库、不迁移或回算旧原文／成绩／偏移；人工清单通过不是设备验收，TST-04／Funbox 部分状态不升级，goal active。本条替代下文对应本轮长文本空槽的最终“待执行”。

2026-10-02 长文本 LF 空槽增量（最终门禁待执行）：明确保存的长文本不再拒绝纯换行，完整词块使用实际 ASCII 空格／LF 边界并保留原文；Tab 不作为分块或进度分隔符。LF 空槽可以跨 10,000 字符块继续，剩余纯 LF 不被加载入口误判完成后归零，进度标签计入空槽。按固定 [长文本进度与必需 LF](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L987-L1028)，中止时未输入的 LF 不获进度，普通 ASCII 空格提交仍可隐含。独立字符偏移实现不复用原版词数组存储；没有字段、归档版本、旧偏移回算或真实库写入。

新增 `LongBlankTextProgressTests` 13 项；首轮 11 项有 28 个有效失败，无编译夹具错误；另两项恢复／Tab 边界守卫在修复后补充。聚焦 13 项通过，相关 85 项仅有 1 个旧夹具的未输入 LF 预期失败，按固定源修正并增加已输入 LF 的断言；最终聚焦和全门禁待执行。证据包括 29,999 个 LF 块重构、10,001 槽连续完成与重试、101 槽中止／恢复、普通词与 Tab、资源上限、内存 SwiftData、正式归档合并与删除保护；导入及恢复按钮的接线仅有源码／构建证据，不冒称设备操作。

边界：不把本轮当作完整长文本进度等价。原版按输入历史长度计算错误词进度，本项目仍只推进匹配前缀，错误词／强制误键进度待对齐；本轮长文本引擎证据限 normal，严格／停止／删除规则后的导航和进度仍待完整核验；原始 CR／CRLF、全部控制符、完整 Funbox／Unicode 融合／IME／设备仍开放。不能以普通模式的 CR 清理测试替代原文长文本验证。只改变未来练习计算和候选准入，不迁移或改写旧原文、结果、偏移；旧二进制可能拒绝新准入的纯 LF 长文本，跨二进制降级未实测。会话内有界风险／迁移复核，不冒称独立评审；TST-04／Funbox 部分状态不升级，goal active，未启动 GUI。

2026-10-02 最终门禁（普通非管道候选队列）：客户端 1508 项（零跳过／零失败，约 299.56 秒，显式十万词已执行）、服务端 131 项（零跳过／零失败）、固定参考与原创性／兼容审计、667 个唯一人工场景清单及未开窗应用包验证全部通过。相关 114 项通过；扩展 64 项的参考路径跳过及首轮完整 4 个夹具失败仍作为阶段记录，不混作最终证据。新增 13 项、53 个有效先行产品失败，仅关闭已列普通候选准备／预算／续批；纯空行长文本、完整控制符／Funbox／Unicode／IME／设备等仍开放。未启动 GUI、不写真实库、不改历史或部署；667 项清单通过不等于设备操作完成，TST-04／Funbox 部分状态不升级，goal active。本条替代下文对应候选队列的最终“待执行／待重跑”。

验证阶段记录：相关 114 项零跳过／零失败（含显式十万词）；首轮完整客户端 1508 项有 4 个旧夹具断言失败，约 299.34 秒，因而服务与打包未执行，不能称该门禁通过。失败分别是有限 finish 预览把 101 词一次全部呈现、1／10 词挑战强制要求续批，以及普通自定义误要求保留重复空格；更新以固定源预算／准备规则为依据，并增加实际完成、零错误和剩余一词断言。中间 46 项以及显式长程的扩展 64 项均零失败，但各有 1 个因未传 TYPEBAR_REFERENCE_ROOT 而跳过的参考脚本测试，不能作为零跳过证据；完整门禁显式长程并传入固定参考路径，待重跑。

2026-10-02 普通非管道候选队列增量（最终门禁待执行）：按固定 [候选准备](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/modals/CustomTextModal.tsx#L174-L185)、[百词与剩余预算](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L675-L715) 和 [提交及最终裁切](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L983-L1023)，普通自定义四种完成方式与三种排序共用已有独立字面候选游标：保留 LF 空槽，NFC／映射空格／重复 ASCII 空格和 CR／CRLF 准备一致，Tab 留在候选内。完成依实际生成队列，不以忽略空槽的通用词数提前结束；未完成批末保留提交，输入后立即续批。短篇非连续长文本入口显式传原始 chunk，与连续长文本、已验证脚本分流，不将普通源清理套到原文进度。

新增 `CustomCandidateQueueTests` 13 项：首轮 10 项产生 50 个有效失败；随后两批独立输入探针再产生 3 个真实续批失败，修复后 13 项通过。可选闭包编译错误不计产品反例；早期相关测试越界崩溃不是有效通过，既有夹具的批首空格、双空格与额外 99 词预取预期经固定源码纠正，未跳过测试或取消计数／错误／结果／回放断言。覆盖 101 空槽、混合源、70 种代码语言、限时／无限 205 槽、严格最终 LF、重复与正式结果往返。续批保留稳定分隔符进度缓存；遇可能融合的书写簇仍回退扫描。最终相关与全门禁结果见后续总结，单次十万词通过不等于所有性能或设备证明。

本条替代此前“普通非管道候选准备／空槽预算仍开放”的限定结论，仅对上述路径成立。没有字段、协议或归档版本变化，不写真实库、回算历史或改旧结果；旧二进制兼容未实测。通用非自定义出题、Funbox 的 toPush／零目标／跨换行、纯空行长文本进度、全部控制符输入、英式备用引语、Unicode 融合／IME／设备仍开放；TST-04 和 Funbox 部分状态不升级，goal active。使用行为优先测试和会话内有界风险／迁移复核，不冒称独立评审；未启动 GUI，人工清单通过不是设备验收。

2026-10-02 本轮最终门禁（普通自定义源准入）：客户端 1495 项（0 跳过、0 失败，约 303.85 秒，显式十万词耐力已执行）、服务端 131 项（0 失败）、固定参考／原创性与其他兼容审计、665 个唯一人工场景清单及未开窗应用包检查全部通过。新增 12 项及最终相关 111 项零跳过／零失败；先行 64 个失败包含 1 个真实分享拒绝异常，修正后的 AFK 夹具失败单独保留而不计产品反例。本条仅替代本轮下文的验证“待执行”，不升级 TST-04／Funbox 部分状态，不把清单通过当作设备操作完成。没有真实库迁移、旧历史回算、GUI 启动、服务部署或资产导入；非管道候选准备／空槽预算、纯空行长文本进度、控制符实际输入、完整 Unicode／Funbox／IME／设备等仍开放，goal active。

2026-10-02 自定义源准入增量（TST-04，最终门禁待执行）：固定 [提交与候选清理](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/modals/CustomTextModal.tsx#L82-L185) 只在清理后候选数组为空时拒绝，LF-only 以及未映射的控制／空白字符仍为候选；[保存入口](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/modals/SaveCustomTextModal.tsx#L37-L49) 同样不裁去 LF。原生普通准入与分段摘要改用已有独立的字面候选准备，不再统一裁 whitespace；保留普通 10,000 字符、标题及管道空候选限制，不改原始文本、持久字段或任何版本。所有调用方共享修正，包括编辑按钮、普通保存、工厂、分享、活动选择和归档合并。

新增 `CustomSourceAdmissionTests` 12 项：先行 64 个失败（其中 1 个为分享入口抛出 invalidConfiguration），无夹具编译错误；第一次修正后仅 1 个 AFK 夹具预期失败，改为在 120 秒内持续输入，不改产品 AFK 判定、不计新产品反例。最终相关 111 项（0 跳过、0 失败）通过；该过滤未包含十万词测试，不能据环境变量声称耐力已执行，完整门禁待执行。覆盖三难度下单 LF 的 finish、普通保存／内存 SwiftData、隔离选择重载、全部四类分享配置、正式归档与去重／删除保护，以及 pipe words／两种 sections 的 101 槽、pipe 计时／无限 205 槽和重复／回放／便携结果。两个新增人工场景令清单为 665，仍未开 GUI／待设备验收。

边界复核：这里只关闭普通源准入及已列出题证据；非管道 words／random／顺序候选池仍按泛化 whitespace 拆分、空槽预算与完成仍未等价，非管道 finish 的 CR／CRLF 与混合源准备、纯空行长文本的分块／进度、内部控制符实际输入、零目标／跨换行 Funbox、英式备用引语、Unicode／IME／设备继续开放。未复制源码、数据或资产，不写真实库、不回算旧历史、不部署。会话内有界风险与兼容性复核，不冒称独立评审；旧二进制可能拒绝新准入的纯 LF 值，未验证跨二进制降级；TST-04 和 Funbox 部分状态不提升，整体 goal active。

2026-10-02 本轮最终门禁（严格前导分隔符／空槽显示与结果历史）：客户端 1483 项（0 跳过、0 失败，约 301.84 秒，显式十万词耐力已执行）、服务端 131 项（0 失败）、固定源码／原创性审计、663 个唯一人工场景清单及未开窗应用包检查通过。累计 17 项新增、86 个有效先行失败；历史修正后的最终相关 59 项零跳过／零失败。本轮下文“最终待执行／待重跑”由此取代，此前夹具编译错误、首版历史修正的 24 个失败及早期门禁均保留阶段性质，不混作最终证据。未启动 GUI、不写真实库、不回算旧历史或部署；663 项清单通过不等于全部设备验收。非管道空槽预算、纯换行源准入、最低 burst 全部统计、内部控制符、英式备用引语、零目标／跨换行 Funbox、Unicode／IME／设备等缺口保留，整体 goal active。

严格空槽结果词历史增量（最终门禁待重跑）：固定 `test-ui.ts:1333–1374` 与 `test/events/stats.ts:519–548` 使用 DOM 输入与带提交的词目标，正确保留 LF 不属于错误额外输入。原生仅适配已有去提交字符的比较表示，完成／中止后按真实目标游标保留判定；第二次错误 LF 和 quick-end 错误仍须为错误。新增 1 项 24 个有效先行失败，累计 17 项／86 个；原 1482／131 全门禁通过在随后历史修正前，不能替代最终证据。首次历史修正相关 59 项仍有原 24 个失败，不计通过；字段夹具编译错误不计。最终相关 59 项（0 跳过、0 失败）通过，全门禁待重跑，无数据迁移或真实库写入，goal active。

严格空槽显示边界更正：首版完整 1481 客户端、131 服务端、663 清单及未开窗包通过，但随后固定 `test-words.ts:55–69` 与 `test-ui.ts:795–843` 证明 display 含 LF、不含普通提交空格。新反例 1 项 4 个有效失败，投影收紧为仅 LF，停止输入中的空格仍为额外字符。累计 16 项、62 个有效先行失败，最终聚焦／完整门禁重跑待执行；此前相关 271 项与快速路径 69 项保留阶段性质。纯换行源准入、非管道空槽预算和其他未列边界仍不关闭。

2026-10-02 严格首分隔符补证（最终门禁待执行）：固定 `validation.ts:58–85` 的导航 guard 与 `fail-or-finish.ts:48–114` 的难度／最终词规则独立。严格或非 normal 下首个正确 LF 留在空槽、无导航；第二次 LF 的词内位置已经越界，normal 严格可错误提交、expert／master 应失败。原生输入与回放保持这一边界，非空首 separator 仍参与词内位置计数，不能把后续字形自动当成新词。`insert-text.ts:342–374` 的实际导航 guard 同时用于最低 burst，避免沿用较早词的速度去失败保留输入。

新增 `RetainedLeadingSeparatorTests` 15 项，有效先行红测 58 个；1 个字段语义夹具误用及类型／私有字段编译错误不算产品红测。阶段相关 244 项（0 跳过、0 失败，显式十万词）通过，显示投影加入后的最终回归／全门禁待执行。固定 `test-ui.ts:795–843` 将保留的第一正确 LF 渲染正确、越界 LF 渲染 extra；独立原生投影保持其词归属且不推动引擎游标。最终空槽正确／quick-end、UTF-16、六种错误规则的正确保留、删除、无空格单字与正式归档都有合成证据，不冒称设备操作完成。

无数据格式变更、真实历史回算、真实库操作或图形实例；旧回放缺失字段仍按已有兼容 reader 读取。非管道空槽预算、普通空槽完整最低 burst、内部控制符、零目标／跨换行 Funbox、任意 Unicode／组合／IME 与设备等仍待核验，goal active。

2026-10-02 当前最终门禁（管道实际尾词）：客户端 1466 项（0 跳过、0 失败，显式十万词耐力已执行）、服务端 131 项、固定参考／原创性、661 场景清单及未开窗应用包全部通过；新增 9 项、最终相关 147 项零失败／零跳过。本轮下文“待执行”由此取代，首次相关 2 个旧预期失败不算通过或新产品红测。只关闭已列队列完成和普通末空槽消费；没有 GUI／真实库／部署补证，非管道预算、严格导航、burst、控制符、Funbox／IME／设备边界仍开放。

2026-10-02 管道实际尾词补证（完整门禁待执行）：固定 `words-generator.ts:695–715,1001–1017` 的预生成数量与 `insert-text.ts:342–374` 的实际队列尾词不能被配置词数替代。已有管道分段流有限 words 使用耗尽后真实尾词的正确／quick-end／提交规则，初始最多 100 词，续批剩余预算不变。`test-words.ts:79–90` 在空尾词上不去提交，独立游标保留 LF-only 词的最后 LF，覆盖 finish／sections／words。此前“独立词预算提前完成”的结论由本条撤回。

新增 `PipeGeneratedQueueCompletionTests` 9 项通过，先行有效失败断言 30 个；1 个续批时机夹具错误和字段名编译错误不计产品证据。真实工厂空尾词／全空首段／内空槽／100–101 词接续／首批 100 上限／quick-end／词级停止／无限／重试／正式归档均有直接检查。相关首次 147 项的 2 个旧夹具失败和 1 默认耐力跳过保留记录；六个旧用例的提前完成预期按源码更正，最终相关与门禁待执行。进度分母仍是保存配置，未修改输入指标公式、数据格式或旧记录，没有真实库操作或 GUI。

边界复核只覆盖所列队列和普通空槽消费，不证明非管道空槽词预算、strictSpace／expert 导航、最低 burst、内部 TAB／LF 移位、零目标或全部 Funbox／IME／设备完整等价；goal active。

2026-10-02 当前最终门禁（普通空槽输入）：最终客户端 1457 项（0 跳过、0 失败，约 300.63 秒，显式十万词耐力已执行）、服务端 131 项、固定参考／原创性、659 场景清单和未启动 GUI 的应用包通过。新增 9 项、修正后相关 123 项均零失败／零跳过；原有 Unicode quick-end 回归已复验，下文本轮“最终重跑待执行”由此取代，首轮 1 个失败不计绿灯。这里只证明已列 normal 空槽、纠错／退格、完成／词历史和显示模型；严格导航、词预算／burst、系统 IME、物理日志、其他组合与设备仍开放，无真实库操作或部署，goal active。

本轮首轮完整客户端 1457 项出现 1 项 quick-end 续批回归，不计通过：续批结构空格不是 LF-only 空槽，错误输入规则现按目标起点／连续提交符判别实际空槽。已有 UTF-16 quick-end 断言保留，聚焦和最终门禁重跑待执行；不以先前 103 项相关绿灯宣称没有回归。

2026-10-02 正常引语空槽输入增量：固定 `words-generator.ts:570–599`、`input/helpers/validation.ts:41–85`、`helpers/fail-or-finish.ts:84–114`、`handlers/before-delete.ts:55–74` 对应独立 LF-only 目标、实际当前输入框、终词条件和正确前词保护。原生目标／词历史保留空槽，与已保留的输入空槽对齐；空槽中的字母作为当前框额外输入，不进入下一词。默认退格对实际提交空槽判断，不借用下一个非空词；额外字形按当时目标游标归属。9 项新增：先行 8 项 45 个有效失败断言，呈现补测 1 项 2 个有效失败断言；相关 103 项（0 跳过、0 失败）通过，完整门禁待执行。

正常模式、正确后前进、词级停止纠错、终词 typo／强制错误／quick-end、多空行、Unicode、批／逐键输入和记录／回放／正式归档有引擎证据，不冒称严格空格或 expert 空槽导航、有限词预算／最低 burst、无空格组合、系统 IME、完整键日志或真实设备已等价。瞬时输入／呈现派生改变，计分公式和持久格式不变；没有 GUI、真实库迁移、回填、上传或部署，goal active。

2026-10-02 最终门禁（隐藏词界进度）：最终客户端 1408 项（0 跳过、0 失败，十万词约 34.39 秒，2,800 词跨块约 20.69 秒）、服务端 131 项、固定参考／原创性、651 场景清单和未开窗应用包通过。优化只复用既有书写簇缓存及二分进度；不将程序化耗时等同于人类输入、系统候选栏或 GUI 持续内存验收，goal active。

2026-10-02 隐藏词界长文补证：2,800 词非管道全文的下划线目标现按实际生成序号续接，首批与后续字符块不能各自裁掉末词 `_`；进入下一块的原始提交空格不变为额外目标。慢测试由确认属于本轮的 xctest 采样定位于准确率活动词界查找内重复 `String.count`，超过四分钟后中止，不计通过。复用已有书写簇缓存和二分提交进度后，完整输入／回放／隔离记录约 20.65 秒通过；另有组合书写簇、emoji、退格、末词恢复与准确率回归，相关 212 项（1 默认耐力跳过、0 失败）通过。只验证引擎，不声明 IME 全阶段、半代理、真人键盘或长 GUI 体验等价；无图形实例、真实库操作、回填或发布，整体 goal active。

2026-10-02 最终门禁（亚秒归档／显式耐力）：客户端 1390 项（0 跳过、0 失败，十万词再次实际运行约 34.49 秒）、服务端 131 项、固定参考／原创性、649 场景清单和未开窗应用包通过。仍不等于实体输入日志、真人长测或 GUI 内存已验证；当前增量不变更原生输入分发，goal active。

2026-10-02 耐力与恢复时间窗补证：只读固定参考 `packages/challenges/src/index.ts:236–251` 核对十万词自定义重复挑战预算；测试使用自有 `typebar` 目标，不复制参考专用词或实现。显式 `TYPEBAR_ENDURANCE_TESTS=1`，按每词虚拟 0.5 秒持续 100,000 词，99,999 词仍活动，终词一次完成，799,999 单位／回放事件、49,999.5 秒及词历史完整。正式归档的先行小用例复现日期截断造成回放尾键丢失；新增兼容精度元数据后精确恢复时间窗，新增 11 项及相关 84 项均通过（0 跳过）。这只证明引擎、编码与恢复，不证明真人耐力、GUI 响应性、物理键日志或设备内存；本轮无 GUI，既有人工状态保持，整体 goal active。

2026-10-02 最终字面分隔补证：累计新增 16 项与相关 210 项（1 默认耐力项跳过、0 失败）通过；最终源码完整客户端 1379 项（1 跳过、0 失败）、服务端 131 项、固定参考／原创性及未打开 GUI 的原生打包通过。下方本轮“待执行／重跑中”由此取代，未使用早期 1377 项绿灯替代最终验证。字面候选／首词接线不证明融合提交、零目标、段进度／未来批次、非分段长文或全量输入已等价，实际设备和历史迁移状态不提升。

2026-10-02 同轮首词选择边界：依固定 `words-generator.ts:859–890`，随机段游标也按字面空格找首词，不能因空格附组合标记漏掉最近两词的重抽条件。补充 2 项先行 3 个有效失败断言，累计 16 项新增、相关 210 项（1 默认耐力项跳过、0 失败）通过，Tab 内容仍保留；夹具缺参数的编译错误不计行为失败。14 项阶段客户端 1377 项（1 跳过、0 失败）、服务端 131 项与原生打包通过，最终源码门禁重跑中，下方 14／208 为早期阶段数量。普通融合提交及完整 UTF-16 输入边界不提升。

2026-10-02 自定义字面提交解析：固定 `components/modals/CustomTextModal.tsx:175–185`、`test/words-generator.ts:888–894` 按字面字符而非书写簇拆候选段和内词。原生分段游标以独立标量扫描折合 CRLF／CR、映射有限特殊空格，按字面空格和管道拆分；组合标记留在后一个词。14 项新增、相关 208 项（1 默认耐力项跳过、0 失败）通过，先行 10 项有 39 个失败断言、扩展 12 项有 44 个失败断言，均为运行到真实行为后的有效红测。Morse 的字数／段数预算、词历史、反写可映射目标、102 词跨批与重复、回放和隔离记录有证据；全量门禁待本轮执行，无 GUI 新证据。

候选段字面拆分可用不等于所有 Unicode 输入可用：普通提交字符与组合标记融合、零目标、分段进度／跨批融合、非分段自定义与长文源路径仍待统一，不能凭推测词界提升计量或设备验收。Tab／未映射空白／零宽内容维持源默认保留，不引入泛化空白分词。无新持久字段、归档／协议版本、真实历史回算或发布／部署。

2026-10-02 最终单次目标接线补证：新增 18 项与相关 176 项通过，完整客户端 1363 项（1 默认耐力项跳过、0 失败）、服务端 131 项、固定参考／原创性及未打开 GUI 的原生应用包通过。下方本轮“门禁待执行”由此取代；已录目标接线不证明零目标／融合词界、旧缺失事件或实体键盘完整等价，未进行实际库迁移或历史回填。

2026-10-02 单次词目标接线：固定 `words-generator.ts:973–994` 保留变换后的 `wordRaw`，提交字符不触发第二次随机变换；原生提示、隐藏词界、词历史及完成／计量现共用一次独立变换所得目标。首批代码不再丢弃已采样文本，自定义有限／顺序／随机续批直接传递批次词目标；可靠外部边界在变换前使用。18 项新增与相关 176 项通过，包括总长度仍相等时的错误分词、70 种代码语言、实际跨批输入、重复开场、回放和隔离记录。先行 4 项 18 个有效失败断言，扩展另发现 ASCII 空格附组合标记的 3 个失败断言，现按 Unicode 标量拆字面提交；编译夹具问题不计行为红测。全量门禁待本轮执行。

零目标／跨词书写簇不伪造偏移，缺失旧词界不从随机重算恢复；这不是全部 UTF-16 输入等价证据。未排序原始配置、一般 bound、任意自定义游标 Unicode、未来随机目标重复恢复、半代理／完整日志与实际键盘仍待验证。未改持久化字段、既有结果或协议，无真实迁移、回填、发布、部署或 GUI。

2026-10-02 最终规范逐词补证：新增 17 项与扩展相关 158 项通过；完整客户端 1345 项（1 默认耐力项跳过、0 失败）、服务端 131 项、固定参考／原创性及未打开 GUI 的原生打包门禁通过。下方本轮“门禁待执行”由此取代。只关闭已列规范顺序／候选池／提交边界，原始未排序配置、随机长度词界、一般 bound、完整 Unicode／日志和实际输入仍未证明等价。

2026-10-02 规范组合逐词补证：固定 `config/setters.ts:156–205` 排序直接 toggle 的官方名称，`test/funbox/active.ts`／`list.ts` 保持数组顺序，`words-generator.ts:368–377,639–666` 按词变换并先反候选池。原生共享逐词策略不再让无空格合并破坏大小写相位，也不提前变换下划线；Morse→ROT13、双写→消息／随机、四类换行不双写、首 UTF-16 单元大写与消息内部换行／有限尾裁均有回归。17 项新增、扩展相关 158 项通过，先行 12 项有 37 个有效失败断言。此前下划线／分段组合夹具依据错误假设，现按排序／反池来源更正，保留原有完成、计分与词历史检查。全量门禁待本轮执行，无 GUI 补证。

只补证规范直接启用路径；外部原始未排序数组、一般词流 bound、随机长度变化的单次采样词界传递、随机池／方向呈现、零目标词、半代理／完整事件日志和实际键盘继续开放。没有参考实现／文本导入、格式迁移、真实数据回算或部署，旧 prompt／回放保持原样。

2026-10-02 最终 Funbox 词目标补证：`CustomFunboxWordTargetsTests` 新增 22 项、相关 147 项通过；完整客户端 1328 项（1 默认耐力项跳过、0 失败）、服务端 131 项、固定参考／原创性审计与未开启 GUI 的打包通过。下方本轮“门禁待执行”由此取代。记录往返验证 prompt／回放／既有字段，不证明旧无隐藏词界记录的全量词历史恢复；零目标词、任意组合、完整输入语义与实际设备仍开放。

2026-10-02 自定义 Funbox 词目标补证：固定 `funbox-functions.ts:601–612`、`generate.ts:32–100`、`strings.ts:9–11`、`words-generator.ts:430–499,938–1003`、`test-logic.ts:575–655` 与 `test-words.ts` 区分目标和提交。Morse 的 nospace 禁止空格提交；下划线在 bound／全局序号决定的位置参与目标变换，完成尾词后只能裁掉真实提交，不能删除 `_`。原生段游标现保留该边界，有限预取词数仍由实际输入预算结束；Morse 去重音不折叠全角，Swiss German 在变换前展示。22 项新增、相关 147 项通过，先行 17 项 269 个有效失败断言；测试成员引用编译失败不计行为证据。全量门禁本轮待执行，没有 GUI／实体输入补证。

代码、夹具与输入文本独立编写；不导入官方实现／资源，不写真实数据，不回算旧提示与日志。本轮不关闭零目标 Morse 词、所有 Unicode 事件／组合顺序或其他生成路径的下划线 bound；审计状态不再用“全部等价”遮盖这些剩余风险。

2026-10-02 最终独立分隔补证：新增 23 项、相关 106 项（1 默认跳过）通过；完整客户端 1306 项（1 默认跳过、0 失败）、服务端 131 项、固定参考／原创性审计及未打开 GUI 的原生打包门禁通过。下方本轮“门禁待执行”以本段为准；只关闭所述配置／生成／消费缺口，不宣称完整输入或所有修饰器组合等价。

2026-10-02 独立分隔补证：`components/modals/CustomTextModal.tsx:64–194` 的分隔与 limit 独立，`test/words-generator.ts:430–499,630–716,760–904,973–1030` 将选中段逐词消费。管道词数首屏按候选段数预取（硬上限百词），并非截断为词预算；真实输入仍按词数结束，后续有限尾批不得丢长段余词。原生独立游标支持四种完成方式、三种排序、空格 section、现有换行及 Unicode 空格规范化；随机 section 避免前两整段，词数／计时随机段则依前两实际词检查首词。新增 23 项回归含 70 个代码选择、101 词尾批、无空格 Unicode 词历史、重复未来抽样及旧历史不回算。初始 112 个有效失败、格式 3 个、空池 2 个、有限排序 1 个先行失败均已记录；完整门禁本轮待执行，不提升未执行的实体输入／GUI 或完整 Unicode 语义。

2026-10-02 最终补证：分段新增 22 项与相关 74 项（1 默认跳过）通过；完整客户端 1283 项（1 默认跳过、0 失败）、服务端 131 项、固定参考／原创性审计和未打开 GUI 的原生打包门禁全部通过。先行红测、夹具更正和来源边界见下文；不宣称整体输入等价。

2026-10-01 section 补证：固定 `test/words-generator.ts:430–499,630–716,760–904,973–1030` 将段内文本拆成实际词；最多百词一批，未完成段继续，文本变换后再追加提交，最终已生成才去掉提交字符。原生独立游标替换前 N 段静态拼接：70 个代码选择段间提交、换行、长段续批、0 无限、三种顺序、段进度、UTF-16 长度变化、noSpaces 词历史、Quick End 和 word-stop 错误终词修正由 22 项新增回归覆盖。13 项有效先行红测有 246 个失败断言；快速重开／Bail Out 各 1 个先行断言，反写提交顺序另 4 个先行断言亦复现并修正。随机重取上限、重复位置权重和重复测试未来批次使用合成自有文本，不导入参考夹具。GUI／实体候选栏未启动；其他 limit 模式独立 pipeDelimiter、完整 Unicode 与日志不据此升级为等价。

本轮最终补证（取代首阶段 14／76 数量）：16 项新增、相关 85 项通过。按 `validation.ts:60–90` 及 `before-insert-text.ts:78–92`，严格词首分隔符继续属第一字段、Expert 空输入不误失败，word-stop 的分隔符也受 UTF-16 输入上限；2 项先行复现 4 个失败断言。完整回归曾暴露长文本提交检查全历史分词，采样定位后终止该次自有测试并恢复局部扫描；原 60 万字符测试 19.811 秒通过，没有跳过／删减或改写其输入。完整门禁另行重跑。

2026-10-01 代码词数及 word-stop 更正：固定 `test/words-generator.ts:430–499,615–716,893–1010` 与 `input/helpers/fail-or-finish.ts:82–118` 共用词数／终词规则，没有代码整程序完成例外。70 个原生代码选择按原创语法词流生成和续接，有限尾批截至真实词数，代码终词共享 UTF-16 Quick End、错误词可编辑与实际提交；无空格保留隐藏词界，原多行缩进测试使用实际五词提示而非错误的一词整程序假设。官方语料不导入，静态原创内容多样性差异保留。

`input/helpers/validation.ts:41–90` 与 `handlers/insert-text.ts:238–290` 证明停止输入 word 只阻止导航，空格仍在当前输入内。原生保留该边界及后续文本，不增加完成词数或下一词速度信用；退格、删词、活动信心互斥及 Expert 失败覆盖，目标末尾的提前返回不能绕过它。可选回放 `commitsWord: false` 贯通游标、删除恢复、定位、声音游标和图表。有效先行代码测试 8 项复现 748 个失败断言；后续 12 项中的一项复现图表误计 12 WPM，现新增 14 项与相关 76 项均通过。旧事件无字段回退、JSON 与既有记录载体往返已验证；无真实数据库迁移、部署或 GUI。回放分隔符具体绘制、复杂 Unicode／半代理恢复、完整日志和真实候选输入仍不宣称等价。

2026-10-01 Quick End 与输入长度上限更正：依据固定 `input/helpers/fail-or-finish.ts:82–118`、`handlers/insert-text.ts:363–369`、`handlers/before-insert-text.ts:78–92`，普通有限模式的长度相等和当前词上限独立按 UTF-16 计算。有限提示不再强制等字形游标到目标末尾才 Quick End，仍要求最终词及全部生成；其他正确完成／提交路径保留。`QuickEndUnicodeTests` 的 20 项与相关 109 项（1 跳过）通过，覆盖长度反向反例、长 ZWJ 的前置输入上限、续批、原生候选不误确认、实际确认后完成、计量与便携结果。没有 GUI 或完整系统输入法证据；无空格／代码专用完成、半代理拆分、组合恢复和完整事件日志仍待单独核对。

2026-10-01 活动规则接线更正：固定 `config/metadata.tsx:465–560` 明示五项输入规则不重启；原先原生界面仅更新偏好，活动会话仍持有旧规则。现由受控同步入口接通自由回退、反向 Shift、四档自动删除、信心及 Quick End；需重启字段仅在来源明示互斥关闭停止输入时例外。已输入文本不回溯更改，错误候选不能因 Quick End 自动确认，正确候选的值拷贝预演不重复计分。`RuntimeInputRuleTests` 22 项与相关 98 项通过，含真实命令消费、无窗口 AppKit、终态冻结／重复及旧字段往返；没有实体键盘或候选栏的新验收。反向 Shift 左右手判断和 Quick End 的完整 UTF-16 终词长度边界仍需逐项补证，不把动态接线当作全部输入算法等价。

固定参考：`91bd24bb8513785c7364cbea29296ff7adafac41`。本审计只记录行为与证据，不包含或复用参考项目的代码、词表、资源或事件数据。

| 参考路径 | 固定源码行为 | 原生映射 | 自动化证据 |
| --- | --- | --- | --- |
| `input/listeners/misc.ts`、`input/input-element.ts` | 聚焦或选区变化后把光标压回输入末尾，并阻止复制、粘贴与选择。 | `TypingInputView` 没有可编辑缓冲区；响应者与 AppKit 文本命令路径均拦截复制、剪切、粘贴、全选及导航选择。 | `testTypingInputEditingPolicyBlocksClipboardAndSelectionCommands`、`testTypingInputNavigationPolicyBlocksOnlyPracticeNavigationCommands` |
| `input/listeners/key.ts`、`handlers/keydown.ts`、`handlers/keyup.ts` | 记录物理按键；重复 keydown 不重复触发快捷操作；常规方向／Home／End／Page 导航只在方向键模式外被吞掉。 | 原生桥记录按下、重复和释放；重开、放弃、禅模式结束与方向键模拟只接受首次按下，文本、Tab、换行和退格仍按系统文本输入处理。 | `testNativeInputBridgeReportsPhysicalKeyDownRepeatAndKeyUp`、`testNativeInputBridgeIgnoresRepeatedShortcutAndArrowActions`、`testNativeInputBridgeSendsArrowKeysToTheTypingEngineOnlyInArrowMode` |
| `input/hotkeys/konami.ts` | 练习页识别 Up、Up、Down、Down、Left、Right、Left、Right、B、A 的隐藏键序，并在完成后打开外部键盘练习站。 | `KonamiSequenceTracker` 在 `TypingInputView` 原有分发前只观察按键；方向取 AppKit 物理键码、B/A 取当前输入源给出的逻辑字符。重复键不推进，Command／Control／Option 组合会重置；完成时仅让 macOS 默认浏览器打开 `https://keymash.io/`，不上传提示、实际输入或按键时序。 | `testNativeInputBridgeRecognizesKonamiOnceWithoutSwallowingTypedLetters` |
| `input/listeners/input.ts`、`handlers/before-insert-text.ts` | 只处理受支持的插入、组合、退格和向后删词输入；不支持的浏览器输入类型不会进入计分。 | `NSTextInputClient` 的 `insertText` 只把确认文本送入批量插入；`doCommand(by:)` 的计分编辑映射后退、向后删词及允许的 Tab／换行，候选取消只清组合态；前向删除不改写已有输入。 | `testNativeInputKeepsMarkedCompositionOutOfTheTypingEngineUntilCommit`、`testWordBackwardDeletionClearsTheCurrentWordAndRespectsWordProtection` |
| `input/hotkeys/utils.ts` | 练习框聚焦且组合文本非空时，普通 Escape 不执行应用快捷键，由输入法处理；显式 Shift+Escape 不受这一例外影响。 | 非空 marked text 的无修饰 Escape 优先交给 AppKit 输入系统，不打开命令面板、重开或触发长测试保护；明确的取消命令清空候选而不提交。按下来源保留至对应 keyup，候选结束后仍正常报告释放；候选结束后的新 Escape 恢复原快捷键。 | `CompositionHotkeyTests` 的 6 项回归覆盖候选优先级、长测试保护、取消不提交、普通快捷键恢复、Shift+Escape 及跨候选结束的释放配对 |
| `handlers/keydown.ts`、`handlers/before-insert-text.ts`、`states/hotkeys.ts` | 普通 Return 不在 keydown 中模拟换行，换行只允许于含换行目标或禅模式；目标含换行时 Enter 重开迁到 Shift。Tab 则明确按目标中的 Tab 模拟插入。 | 允许换行且候选非空时，无修饰 Return 先交给 AppKit，可由输入法提交候选；下一次普通 Return 仍按原规则插入换行。显式 Shift+Return 重开、禅完成和长测试退出优先级不变；无换行目标中的 Enter 重开和 Tab 模拟路径不变。 | `CompositionReturnTests` 的 8 项测试覆盖 CR／LF、两种重开设置、提交及后续换行、按键事件报告、原有显式快捷键、Tab 与多行会话完成／回放 |
| `input/listeners/composition.ts`、`input/listeners/input.ts` | `compositionstart` 启动测试；普通候选更新只显示组合文本，`compositionend` 才提交。例外是全部目标已生成且最后一个词的当前输入加候选完全正确时，会自动结束组合并提交终词。 | 首次非空 `setMarkedText` 调用 `TypingSession.beginComposition`，不写入字符。终词候选由 `shouldFinishWithComposition` 用值拷贝预演普通批量输入，确认当前词完整匹配且有限测试可完成才经原有 `insertText` 路径提交；清空 marked range 后通知 AppKit 丢弃转换会话。主界面完成判定与实际输入共用镜像转换；Mouse Warrior 禁止物理输入的边界保留。 | 原有组合开始／确认回归，以及 `CompositionCompletionTests` 的阿拉伯文原生桥、中文词界、分批提示、有限模式、误匹配、强制错误、镜像与延迟确认回归 |
| `input/handlers/before-delete.ts`、`handlers/delete.ts` | 普通退格和向后删词受自由回退、信心模式、正确已提交词保护及代码反缩进共同限制。 | `TypingSession.deleteBackward` 和 `deleteWordBackward` 共用对应保护、代码反缩进及可回放删除事件。 | `testFreedomModeOnlyAllowsDeletingCommittedCorrectWordsWhenEnabled`、`testMaximumConfidenceModeDisablesBackspaceAndNormalizesConflicts`、`testCodePracticeAutoIndentsUnindentsReplaysAndFinishesWordMode` |

## 当前结论

固定参考输入监听器的可观察练习语义均已有原生映射。`FUNCTIONAL_INVENTORY.md` 的 `INP-01` 与 `INP-02` 是面向用户的汇总；本文件保留源码路径、原生边界和对应测试，防止后续更改把“组合开始计时但确认后才计分”的语义退化。

2026-10-01 导航实机补证：`MANUAL_ACCEPTANCE.md` 的 `INP-NAV-01` 现记录源码 `7e71af2` 单实例内存库 GUI 的 32 组普通／Shift／Option／Command 导航键、继续输入后的 9 字符全匹配，以及字数模式四方向推进 4/50 且零错误。自定义模式的箭头冲突拒绝同样可见。因未验证系统音频、Control+F/B 的实际派发及真人实体键盘，本项只是部分验收；单实例已正常退出、进程归零，不借此提升候选输入或全部输入边界的验收状态。

## 仍需人工验收

真实 macOS 输入源会因用户安装的输入法、候选栏和系统版本而异，自动化测试不能替代以下验证：

1. 用中文、日文或韩文输入法开始、更新、确认和取消候选，确认时钟从首次候选开始、只有确认文本进入提示与回放。
2. 在带附属 sheet、失焦提示和外部文本框间切换，确认候选组合不会越过焦点边界。
3. 用真实物理键盘验证 Option-Delete、死键和按键连发；布局输入仍必须由用户选定的 macOS 输入源决定。
4. 用真实中文／日文／韩文候选栏及第三方输入法验证终词完全匹配时自动确认、候选栏收尾与延迟回调。当前证据是直接调用 AppKit 输入桥，不冒称已验收真人候选窗口。
5. 在真实候选转换的不同阶段按 Escape，确认输入法可以逐级回退或取消，不误开命令面板、不重开测试；候选结束后释放 Escape，再按新 Escape 验证原快捷键恢复。
6. 在自定义多行、代码和禅模式中，用真实输入法按普通 Return 确认候选，确认不多插一个换行；之后再按 Return 应换行，显式 Shift+Return 仍执行配置的重开、完成或退出。

2026-10-01 多行候选 Return 更正：先行测试在 CR／LF 与关闭／Enter 重开四种组合中均得到换行而非候选提交，marked text 仍在；原因为直接换行分支提前返回。原生桥现只在允许换行、候选非空、普通 Return 的边界调用 Apple 的 [interpretKeyEvents(_:)](https://developer.apple.com/documentation/appkit/nsresponder/interpretkeyevents(_:))，不假定系统必然把这个键解释为换行，也不覆盖该方法。为稳定验证交接，内部视图允许测试子类仅替换 `inputContext`；受控 `NSTextInputContext` 按 [handleEvent(_:)](https://developer.apple.com/documentation/appkit/nstextinputcontext/handleevent(_:)) 的消费语义确认自有候选。8 项新增回归及此前 16 项组合输入回归通过；真实会话还验证后续新 Return 的换行、零错误完成及回放精确重建。测试没有改变系统输入源或启动 GUI，不代表实际候选栏、第三方输入法和实体键盘已验收。固定参考的 Tab 模拟插入路径保持不变，没有把所有候选态按键笼统移交系统。

2026-10-01 候选 Escape 优先级更正：先行测试复现候选期间误开命令面板、误重开或显示长测试保护，以及明确取消命令未清空候选。首批修正后，追加按键释放测试又复现候选结束后 keyup 被动态快捷键判断吞掉；现跟踪该次按下的来源，至匹配释放才清除。6 项新增测试及 10 项终词完成回归全部通过。依 Apple 的 [interpretKeyEvents(_:)](https://developer.apple.com/documentation/appkit/nsresponder/interpretkeyevents(_:)) 将按键交给输入系统，不假定每次 Escape 都必须丢弃全部转换；只有输入系统明确派发取消命令时才清空 marked range，并按 [discardMarkedText()](https://developer.apple.com/documentation/appkit/nstextinputcontext/discardmarkedtext()) 通知系统结束转换。这是直接 AppKit 调用的自动化证据，未启动 GUI，真人候选栏和实体按键仍待上列人工验收。

2026-10-01 终词组合完成更正：先行行为测试在终词阿拉伯文候选仍保持 active、marked range 未清空且无结果的路径失败；独立实现后，匹配候选沿现有批量输入完成并可由回放重建。完成探测不会修改真实会话；错误候选与快速结束、词界前的跨词候选、无限／计时／禅模式、候选本身或当前前缀的强制错误均不能绕过边界。分批生成只按真实终止规则完成，不把当前小批末尾当作最终目标；追加代码游标边界测试还证明，达到实际词数上限时不能因生成游标仍存在而拒绝完成，首次失败后已纳入同一准入规则。AppKit 收尾遵循 Apple 的 [discardMarkedText()](https://developer.apple.com/documentation/appkit/nstextinputcontext/discardmarkedtext()) 文档：先清空客户端 marked range，再让系统丢弃转换会话。未引入新依赖，也不读取或导入参考输入实现。
