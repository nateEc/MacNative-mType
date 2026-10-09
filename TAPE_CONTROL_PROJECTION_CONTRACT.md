# Tape 控制字符与真实词归属

本轮独立修正原生 Tape 的内容投影，不开放生产含换行入口，不宣称完整功能等价。固定只读参考 `91bd24bb8513785c7364cbea29296ff7adafac41`；完整 `buildWordHTML`／`updateWordLetters` 表明 Zen Tab／Return 是隐藏但有宽度的控制字形，包含多个 LF 的一个词仅附加一组 beforeNewline／newline／afterNewline。`getNlCharWidth` 选择词内首个目标 Return，而不是词尾字符。

`TapePromptProjection` 按实际会话词范围确定归属：no-space 下一词的首 LF 不给上一词，词内 LF 不再遗漏；首个 Return 决定标记宽度。Zen 活动词包含实际合成光标／空词占位符，不生成无字形的未来空词。描述符明确区分 canonical 控制字符偏移与共享文本的结构 LF。

TextKit 仅在 canonical 偏移处把原始 Tab／LF 测量为本地箭头／Return 字形，保留原字体、颜色、透明度与装饰；普通已符号化字符、替换文字及候选正文不变，结构 LF 不获得字形 ID。多个词内 LF 保留各自 marker，结构仍只分一次行。横向缺失词保留一组结构行，无原词墨迹或 canonical 字形。该状态是尝试内投影，不新增 timer、窗口、产品依赖、存储字段或服务协议；提示、输入、计分、回放与归档不变。

## 行为证据

首轮测试自身 AttributedString 属性访问编译错误保留于 `/tmp/typebar-tape-control-projection-red.log`，不计行为失败。修正测试后六项产生 17 个断言失败，日志 `/tmp/typebar-tape-control-projection-behavior-red.log`；其中七个来自尚未成立的 no-space 输入导航／删词前提，改用已支持的未来词移除事件验证布局，不据此修引擎。首轮修正 28 项包含一个源码环境跳过与一个错误的末尾空结构高度假设，日志 `/tmp/typebar-tape-control-projection-first.log`；改为有后续正文的场景，不把无正文的末尾 filler 算作一行文字。

首个扩展阶段新增八项，相关 173 项零失败零跳过（30.440 秒），日志 `/tmp/typebar-tape-control-projection-expanded.log`。涵盖真实 Zen 初始／空格后／Return 后空词、双向连续隐藏 Return、隐藏 Tab 的单字形 advance、no-space 内部多个 LF、下一词首 LF、独立删词、候选正文与结构 LF、位图显墨正反对照。三张图 `/tmp/typebar-tape-control-focused-images.AoKq5A/tape-controls-{blank,hidden,visible}.png` 已逐张检查：hidden 与 blank 整张 PNG 精确一致，visible 非空且不同；字框均有正宽。源码 QA 探针扩为 52 个完整构建／更新案例，增加内部多个 LF 与首 LF；真实 Words／Strings，DOM、提示合并、RAF 与 CSS 测量仍为受控边界。

有界同会话风险复核发现过宽的无字形过滤可能删除普通空词，主动停止首轮完整门禁；终态退出 130 后确认无残留测试／编译进程，69 份原始日志保留于 `/tmp/typebar-tape-control-final-logs.cmSzYa`，总日志 `/tmp/typebar-tape-control-final-readiness.log`。十个冻结哈希从启动至中止一致；该轮原生未结束、服务未执行，不计完整通过。

新增普通 `a  b` 反例先产生三个有效失败断言，日志 `/tmp/typebar-tape-control-empty-word-red.log`，确认中间词身份／间距丢失。条件收窄到 Zen 未来合成空词，保留所有普通空字段。该阶段九新增／相关 174 项零失败零跳过（28.065 秒），日志 `/tmp/typebar-tape-control-projection-corrected-focused.log`。这是同会话审查与修复，不冒称独立评审；之前完整绿灯及中止轮均不是最终修正证据。

继续复核隐藏状态与额外身份后停止第二轮门禁，终态 130、无残留测试／编译进程，69 日志保留于 `/tmp/typebar-tape-control-corrected-logs.2Y2Wax`，总日志 `/tmp/typebar-tape-control-corrected-readiness.log`，不计成功。真实 strict-space 保留 LF＋隐藏额外输入反例产生三个有效失败断言：额外 LF 抢走首个目标 Return、标记宽度归零、最后目标词误把尾部额外 LF 当分隔符，见 `/tmp/typebar-tape-control-hidden-extra-red.log`。第一次只排除词内 extras 后，175 项仍有一个真实末尾边界失败；单项定位日志 `/tmp/typebar-tape-control-hidden-extra-localized.log` 确认 `range.upperBound == prompt.count` 指向追加的 extra，而非目标字符。结构候选与控制偏移现仅来自 target IDs，分隔符严格小于实际目标长度，不以隐藏／extra 外观状态替代身份。

最终十新增／相关 175 项零失败零跳过（27.745 秒），日志 `/tmp/typebar-tape-control-projection-identity-corrected.log`。测试渲染器同步使用生产 hideExtra／isExtra 参数，隐藏 extra 不能获得控制单元或结构行。前两轮中止与之前绿灯均不作最终证据。

## 最终完整验证

重新冻结门禁 `/tmp/typebar-tape-control-identity-readiness.log` 终态退出 0：原生 3,931 项零失败零跳过（1003.540 秒），服务 501 项零失败零跳过（12.109 秒）；十万词实际执行 171.047 秒，16 项隔离磁盘迁移 5.073 秒。十新增在全量中 0.020 秒通过。53 表面、1,121 唯一人工场景结构、90／3／1 配置元数据及未启动应用包资源／URL scheme／严格签名／原创性边界通过；这些元数据与清单不是完整实机等价证据。

十个冻结文件 SHA-256 从启动、中途至终态均与 `/tmp/typebar-tape-control-identity-frozen.sha256` 一致。71 份原始日志保留于 `/tmp/typebar-tape-control-identity-logs.dVzy6k`，191 张生成图保留于 `/tmp/typebar-tape-control-identity-images.Y4pt9t`；本轮控制字符 blank／hidden／visible 三张最终图已逐张复查，精确无墨与可见正对照保持。门禁终态后才补本节及 README／规范结果，其余七文件再次核对冻结哈希。既有系统 Contacts／CoreData XPC、隔离故意坏库／只读库及编译／Node 提示保留，不宣称修复。参考仍为固定干净检出，零 Typebar 主程序启动，无残留测试／编译进程，无真实账户／服务部署。

## 保留边界

生产 `usesTapePractice` 的含源换行保护仍保留。Zen 的目标 prompt 为空，`hasPracticeNewlineContent` 仍不反映已输入的 LF，因此生产 Zen 内容动态切换／两行 viewport 尚未完整接通，不能用本轮显式组件投影证明实际入口。no-space 内部 LF 的全部输入导航、首个 Return 错误／提示／候选合并宽度、零长度映射别名、横向删除未来词后目标激活、确认前字体重建、任意纵横／反向动画队列和实机 IME 均待验证。

CFG-02／tapeMode 维持部分兼容；人工场景仅结构审计，不是设备验收。不启动 Typebar 主程序、不读写真实库／账户、不部署。整体 goal active。
