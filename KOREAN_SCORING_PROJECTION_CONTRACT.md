# 韩文计分拆分基础与接入边界

本阶段独立实现 KoreanScoringUnits，只提供原始 UInt16 到计分单位的纯投影。它尚未接入生产会话、结果展示、归档或服务投稿，不能视为韩文功能已完成。完整 Monkeytype 重写 goal 保持 active；原始输入、回放、IME 状态和旧固定成绩均不改变。

## 固定源合同

参考提交为 91bd24bb8513785c7364cbea29296ff7adafac41。[getChars](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/events/stats.ts#L438) 先规范输入的源空格，再按 context.koreanStatus 对输入与已知目标拆分；未知目标回退为已拆分输入。它使用锁定的 hangul-js 0.2.6，不是 Unicode NFD。

[初始目标检测](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L512) 根据生成目标中五组 Hangul 范围设定韩文状态，事件上下文保存此状态。依据本次阅读，后续接入应冻结初始检测，不能按语言菜单名、用户后来输入或增长提示重新猜测；本阶段未执行完整初始化生命周期。准确率仍按输入事件判断，不能把计分拆分数当成键盘尝试数。

现代音节按 [Unicode Hangul 音节算术](https://www.unicode.org/versions/Unicode16.0.0/core-spec/chapter-3/) 独立展开，再映射为兼容 jamo。混合辅音／元音簇拆分，重复 shifted 双辅音不拆分；现代 11,172 音节最多五单位。连接 jamo、古字、扩展区、未分配单位及代理半部保持原单位，不做 NFC／NFD 或跨单位组合。

固定依赖还存在非 Unicode 规则的计分特例：NUL（U+0000）投影为 ㄱ。实际实现的零键查找表把零识别为首辅音，穷举证据确认唯一额外非簇映射。仅在显式韩文计分投影保留此行为，不改原始保存数据或普通模式。

## 源证据与原创性

Scripts/check-source-terminal-history.mjs 可接受第二个参数，指向仓库外的只读 oracle 目录。该目录必须包含从官方 npm tarball 提取的 package 与 hangul-js-0.2.6.tgz；探针验证固定 pnpm-lock 的 SHA512、完整 hangul.js SHA256 与版本，再在无 require／网络绑定的 VM 执行它。它不是应用或包的依赖，第三方代码、资产和压缩包都不进入原生仓库。

获取地址为 https://registry.npmjs.org/hangul-js/-/hangul-js-0.2.6.tgz。压缩包 SHA512 的 base64 为 `48axU8LgjCD30FEs66Xc04/8knxMwCMQw0f67l67rlttW7VXT3qRJgQeHmhiuGwWXGvSbk6YM0fhQlcjE1JFQA==`，hangul.js SHA256 为 `94362dfdd81723a3cb94e5d27c7c0ef09b6949dc25002ecc06aff5448602bfc8`。先在独立临时目录下载／提取，再执行 `node --experimental-vm-modules Scripts/check-source-terminal-history.mjs <固定参考绝对路径> <oracle目录绝对路径>`。省略第二参数仅验证既有非韩文夹具，韩文调用明确报错，不提供假 oracle。

实际 oracle 与原生测试穷举 65,536 个单 UInt16 输入。按升序将输入 UInt16、输出数量 UInt16 和每个输出 UInt16 编码为 little-endian，串接后 SHA256 为 `3ce3e56e227e9d618cd7b00e63c65ffd783807a110e071bde31d1172d05144a7`。测试另检查全域幂等、逐单位组合、最大长度与空输入，不以有限示例替代穷举。

实际完整 stats／helpers／strings／numbers 四模块和完整验证依赖还通过十二组 getChars 夹具：前缀与漏打、混合簇、重复辅音、连接 jamo、emoji、代理半部及全角空格。原生测试显式组合投影与现有分类器得到同样五计数；这不证明会话已经自动选择投影。探针预置韩文上下文，不证明真实 IME、输入 handler、浏览器、布局或服务投稿。

## 接入前必须解决的兼容性

当前结果／历史／CSV 将 sourceUnits 标记为 UTF-16 单位；韩文拆分必须保存明确计分基础并相应展示，不能悄悄冒用原始单位列。默认归档仍 20，最低版本保护与旧固定成绩不回算保持；未来新增基础字段需要版本门控、往返与真实旧夹具测试，而不是本阶段先抬格式。

服务端 ResultInputMetrics v1 要求 retainedUnits 不超过 totalAttempts，并在 AuthStore 要求 retainedUnits 不少于 eventCount。一次合成韩文尝试可投影五单位，直接发布会被第一条拒绝；普通末词 SPACE 裁剪后保留二单位但输入三次，也会被第二条拒绝。上述接口风险已定位，但本阶段未修复。后续必须引入明确单位基础与版本化指标、精确能力协商和客户端旧服务保护，并用合法／伪造载荷测试服务端边界，不能只放宽旧 v1 校验。

最终与实时 WPM／Raw、曲线、准确率、挑战、复制及归档的所有消费者仍需逐一取证和接入；原始日志永远保留，初始化冻结状态与 Zen 无目标状态不能混淆。真实键盘／IME／VoiceOver、旧库／旧二进制降级／混合版本及服务部署仍未验证，不启动图形实例或操作真实库。

## 已完成的定向验证

新增八项 KoreanScoringUnitsTests，扩大相关回归共 72 项零失败（0.656 秒）。先用可编译 identity 投影复现四项八处预期失败；初始实现七项中仅全域指纹失败，逐单位对照定位为 NUL。随后补明确映射和独立保护，保持 oracle 指纹不变；其他六项均已通过，不把此测试失败当作现有应用回归。

行为优先、源码驱动、根因调试以及本会话有界决策／风险／迁移复核限定实现，非独立评审。write-page 技能将已验证基础、历史失败和未接入风险分开记录。已有普通 Hangul sourceUnits 缺省守卫继续通过，没有以新模块掩盖生产接入缺口。人工清单新增一条待设备验收，不改官方配置或 Funbox 覆盖等级。

## 最终完整验证

最终串行门禁成功退出：客户端 2,372 项零失败（555.820 秒）、服务端 131 项零失败（1.405 秒），784 条人工场景结构、固定参考与原创性审计、未打开应用包验证通过。本次实际十万词 passed 行用时 119.250 秒；旧 12,000 次组合字符删除双投影为 0.025641 秒，详细日志已在清理前保存。不以历史耗时、环境开关或普通耐久样本证明韩文实机／混合路径性能等价。

Typebar 图形实例为零，真实背景成绩路径不存在，没有删除用户数据；测试使用内存成绩库，不写真实设置／成绩、播放实际音频或部署服务。固定参考仍干净，编译测试活跃时没有编辑输入。所有生产接入缺口仍按上节追踪，完整 goal 不因本基础增量结束。
