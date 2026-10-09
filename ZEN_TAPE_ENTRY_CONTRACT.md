# Zen Tape 生产入口与双行视口

本轮把已有原生 Tape 词框接入真实 Zen 呈现分支，不复制 Monkeytype 产品代码或资产，不开放普通生成文本的换行 Tape，不宣称完整重写完成。固定只读参考为 `91bd24bb8513785c7364cbea29296ff7adafac41`；下述源码函数只在 QA 中执行，不进入应用包。

## 行为与边界

Zen 的目标文本一直为空，`hasPracticeNewlineContent` 描述的是目标，而非后来输入的 Tab／Return。因此原生产分支即使输入换行仍传入空词框数组。新的会话初始化器从 Zen 初始不可见占位符开始投影 canonical 词框，输入 Tab、连续 Return、删除和重开都保持同一原生视图 owner。生产分支与挂载测试共用该初始化器；补充静态路由断言不能当作完整 ContentView 的运行期证明。

Zen 视口始终预留两个实测行高，不因只有一个活动词而收成一行；字号改变后按原生测量更新。它不是固定 CSS 像素高度，也不保证各输入的字体行高完全相同。普通无换行 Tape 仍保持原单行高度；生产 `usesTapePractice` 的普通目标换行回退保持不变。既有组件初始化器的三行上限行为不变，未启用 Tape 的 Zen／完整行设置不在此次接线范围。

连续换行触发既有异步退休与会话确认，保留完整输入、当前空词和尝试身份。狭窄视口横向独立删词仍走会话缺口账本，确认／重绘不重复通知。平滑退休期间重开取消旧回调。没有新 timer、主程序启动、产品依赖、设置字段、数据迁移或服务协议变化；输入、计分和回放模型不修改。

## 先行证据与修正记录

- `/tmp/typebar-zen-tape-entry-red.log`：最初四项使用旧生产参数的挂载测试产生 35 个预期断言失败（22.035 秒），覆盖单行高度、换行定位、退休和入口选择。
- `/tmp/typebar-zen-tape-entry-first.log`：首版内联高度表达式引发 Swift typechecker 超时，未执行行为测试；拆成显式 `CGFloat` 属性后，`/tmp/typebar-zen-tape-entry-compiled.log` 四项通过（0.368 秒）。不是通过改测试期望修复编译问题。
- `/tmp/typebar-zen-tape-entry-expanded.log`：66 项中一项失败，错误预期退休 pace 的缓存必须为 nil。完整源 `caret.ts` 的 `goTo` 在词不存在时直接返回，`handleLineJump` 保留负向位移；删词并不清光标缓存。原生实际矩形完全在视口上方。因此未改产品代码，改验完全裁剪、无交集，并以 pace 开／关整张 PNG 精确相等证明无漏墨，非放宽任意容差。
- `/tmp/typebar-zen-tape-entry-corrected.log`：九新增／相关 66 项零失败零跳过（3.830／14.707 秒）。真实会话覆盖 word／letter、Tab、连续换行、删除 Return、字号、狭窄横向缺口、平滑重开、希伯来语／emoji／组合字符与退休 pace。
- `/tmp/typebar-zen-tape-entry-regression.log`：相关 225 项零失败零跳过（45.896 秒），包含所有 Tape、控制字符、词退休、wrapper 配置、视口和字体预览。

八张定向图位于 `/tmp/typebar-zen-tape-focused-images.7QZ3wR/zen-tape-*.png`，已逐张检查；所有窗口从未显示并及时 stop／close。位图非空断言允许文字或可见标记，不据透明背景上的黑字宣称完整排版可读性。退休 pace 的开／关图片整张精确一致，Tab 宽度及当前空词位置另有几何断言。

## 固定源码对照与风险复核

`check-source-zen-tape-viewport.mjs` 完整执行固定源 `updateWordsWrapperHeight`，192 组覆盖 off／word／letter、四种自有测量、force、原始 showAllLines、页面／结果／缺失活动词门禁与小数 margin 的 parseInt 截断。八组有效 Tape 轨迹与实际挂载的原生双行比例对照；CSSOM／字高是受控边界，不是浏览器渲染或原版字体的数值等价。探针验证参考 pin 和干净状态，并接入完整 readiness。

同会话有界风险复核重点检查：初始化器保留原方向与锚点策略；不修改目标换行属性，以免改变输入准入；普通换行回退不解除；稳定原生 owner 避免单行／换行容器切换；退休 pace 缓存遵循实际源码而以像素裁剪验收。此复核并非独立审计。

完整功能仍开放：普通含换行题目生产接线、全部 IME／组合 replacement、任意反向纵横队列／字体重建确认时序、hint／no-space 内部 LF 导航、可见范围性能、字体／主题资源及真实设备。CFG-02／MET-67 与 tapeMode 仍部分兼容；94 配置的 90 映射／3 部分／1 不适用只是元数据账本，不是全部功能通过。此前合同中“Zen 生产入口未接通”的历史结论由本合同限定范围更新；其余缺口不升级。完整 goal active，本轮零 Typebar 主程序启动。

## 最终冻结验收

首轮冻结九个文件，全程哈希一致；`/tmp/typebar-zen-tape-entry-readiness.log` 终态退出 1，原生 3,940 项中一项失败、零跳过（1,045.084 秒），新增九项通过，十万词耐久 165.580 秒。70 份原始日志保留于 `/tmp/typebar-zen-tape-entry-logs.ClhIo8`，该轮未执行服务与打包，不计完整门禁通过。失败位于旧 `TapeNewlineFlowTests`：第一次只等待 RunLoop 2 毫秒时通知为空，其后次数等于一及全部几何断言通过，表明通知稍后实际到达。完整生产 `deliverTapeWordRemoval` 明确经主队列异步发送；不能以任意短暂 RunLoop 运行保证队列已交付。`/tmp/typebar-zen-tape-callback-recheck.log` 未改代码单独复跑一项通过（0.193 秒），不据重跑抹去原始失败。

仅修正测试同步：等待实际删词事件，保留同步期间数组必须为空、完整精确词身份集合、一次通知、零纵向通知及所有几何断言；重复刷新用主队列屏障处理已排队通知，并显式拒绝 over-fulfill。相邻停止／新尝试用例也用队列屏障替代固定 2 毫秒，以实际处理完旧队列后断言取消。未改变产品通知时机或去重逻辑。`/tmp/typebar-zen-tape-entry-regression-corrected.log` 相关 225 项零失败零跳过（49.032 秒）。此修正属于已观察异步测试竞态，不宣称消除所有任意调度问题。

最终重新冻结十个文件，`/tmp/typebar-zen-tape-entry-final-frozen.sha256` 在启动、中途和终态均一致。`/tmp/typebar-zen-tape-entry-final-readiness.log` 终态退出 0：原生 3,940 项零失败零跳过（1,094.699 秒），服务 501 项零失败零跳过（15.789 秒）；新增九项 4.155 秒，十万词耐久 177.635 秒，16 项磁盘迁移 6.140 秒。此前失败的 TapeNewlineFlow 整组在该全量中通过，未以单独重跑代替最终验收。

固定源码对照（含本次 192 组）、53 页面／modal 表面、1,123 唯一人工场景的结构审计、94 配置的 90 映射／3 部分／1 不适用、未启动应用包／签名／资源和长文字原创边界检查全部通过。结构审计并非人工验收，边界检查不证明全部功能／字体／设备等价。72 份原始日志位于 `/tmp/typebar-zen-tape-entry-final-logs.wTY9Xf`，199 张图位于 `/tmp/typebar-zen-tape-entry-final-images.s4NS01`。其中八张 `zen-tape-*.png` 已由主代理逐张复查；退休 pace 开／关的整张 PNG 精确相等，Tab 和当前空词有正宽且在双行视口内。透明背景黑字的可读性限制仍如前述，不据此升级完整排版结论。

终态后确认无测试／编译／门禁／Typebar 主程序残留，再仅补 README、规范、功能盘点与本合同的验证记录；其余六个冻结文件继续逐项校验。参考 checkout 始终为干净固定 pin；本轮零主程序启动，整体 goal 继续 active。
