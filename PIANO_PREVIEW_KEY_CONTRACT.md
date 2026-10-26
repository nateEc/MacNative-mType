# 钢琴试听与后续点击的按键上下文

状态：32 组固定源码对照在旧原生实现上失败，修复后通过；相关原生回归通过。实体试听仍待验收，不代表完整声音验收通过。

参考为只读 Monkeytype 检出 `91bd24bb8513785c7364cbea29296ff7adafac41` 中的 `frontend/src/ts/controllers/sound-controller.ts`：`previewClick` 的钢琴分支传入 KeyQ，`playNote` 把覆盖键写回 currentCode；后续没有覆盖键的 `playClick` 使用这个值。普通 keydown 再次替换它，keyup 不替换它。这里描述的是同一个页面声音上下文，不扩展为多个原生窗口共享试听状态。

必须保持的行为：

- 钢琴试听从 Q 对应的音高播放，并将它保留为本播放器的后续点击键。
- 之前记录的是 Z、空格、Shift 或 Caps Lock，均不能让试听后的点击使用旧键。
- 之后的新普通按键覆盖试听键；不可发声的按键抑制后续点击，不能回退到 Q。
- 抬键不覆盖最近按下的键；Shift／Caps Lock 的音高规则继续独立生效。
- 音阶试听、样本音效、音量、其他页面播放器和已经播放的声部不因此改变。

`Scripts/check-source-piano-preview.mjs` 每次执行前后校验参考 HEAD 和工作区，临时在内存擦除类型并执行实际按键监听、音符映射、初始化、playNote、previewClick 和 playClick。32 组覆盖四种波形、四种旧键与两种 Shift 状态。AudioContext、声音选择配置、修饰状态和 document 注册是自有适配边界；输出频率轨迹供原生测试对照，没有执行真实浏览器、系统音频、原版音色或硬件时序验收，也不把参考代码或资产写入应用。

原生入口必须由此轨迹和现有按键监听测试验证。最终验证结果记录在 `OFFICIAL_CONFIG_AUDIT.md`；实体试听与跨窗口操作仍须人工验收。
