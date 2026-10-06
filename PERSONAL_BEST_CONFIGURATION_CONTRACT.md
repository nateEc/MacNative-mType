# 个人最佳配置保存合同

后续 [账户 PB 账本](PERSONAL_BEST_LEDGER_CONTRACT.md) 和 [本机／标签账本](LOCAL_PERSONAL_BEST_LEDGER_CONTRACT.md) 已接通完整分组与删除保留；原生归档 28 运输独立本机账本，[远程小数速度](RESULT_SPEED_PRECISION_CONTRACT.md) 提供投稿数值证据。下述配置保存阶段的数字与范围保留；原版标签 ID、真实双机、官方协议和全消费者等价仍开放。

2026-10-06，完成时的 difficulty、punctuation、numbers、lazyMode 已从原生保存快照接通能力协商、服务接受记录、私有历史和远程 CSV。它补齐后续 PB 分组所需的明确配置，不改变当前 PB 选择、XP、速度榜或公开资料算法；独立个人、标签和榜单 PB 账本仍未接入，整个重写目标未完成。

## 固定源码与字段范围

参考固定于 `91bd24bb8513785c7364cbea29296ff7adafac41`。[完整 PB 模块](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/utils/pb.ts) 先按 mode／mode2，再按 difficulty、language、punctuation、numbers、lazyMode 分组；[难度定义](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/packages/schemas/src/shared.ts) 为 normal、expert、master。原生实现只投影已保存配置，不复制参考实现、内容或资产。

自有可选字段 personalBestConfiguration 的 v1 包含 version=1、上述三个难度之一及三个必填 Bool。language 和 mode／mode2 继续使用成绩自己的字段。lazyMode 来自保存的 lazyLatin 选项，不从 XP 的 Funbox 列表推断；该列表有意不包含 lazyLatin。字段不是 PB 获奖、准入、排名或真实性声明，quote 等不合 PB 资格的模式也可保存配置。

## 投稿与私有读取

ResultConsistencyPublication 读取 CompletedTestResult.configuration，绝不读取完成后的当前偏好。SwiftData 的已有不透明配置和归档恢复后沿用相同快照。仅 apiVersion=v1、service=typebar 且 resultPersonalBestConfiguration=available 才上传该字段。缺失、planned、partial、错误版本或服务标识均不算支持。

旧服务不支持时，normal 且三个开关全为 false 的成绩可沿用旧字段；远端缺失仍表示未知，不能反向推断为明确默认值。任一非默认配置在昂贵统计或 POST 前报错，保留本机成绩与既有重试路径。能力查询失败、取消与账户范围复核继续沿用现有发布流程。

服务在请求解码、直接 actor 调用、文件解码和历史解码分别检查显式字段。缺失兼容；显式 null、不完整、类型错误、未知难度或版本拒绝。若存在 XP 报告，标点和数字必须与其一致，不能同时保留相互矛盾的报告。

同一次原子保存把配置写入 StoredResult 和 ExperienceAwardRecord。仍存在的历史必须与首次接受记录一致；后者有 XP 原始输入时，还检查标点／数字绑定。显式坏字段、两份配置不一致或 XP 标志不一致的加载报错且不改文件；这不是防篡改签名。普通重复 UUID 和删除历史后重试都不能更换首次配置、重建已删除历史或再次入账。保存失败回滚完整状态，恢复可写条件后只接受一次。

GET 私有列表和单条详情返回配置，认证范围不扩大；其他账户无法读取该结果。远程 CSV 在已有 24 列之后追加版本、难度、标点、数字和 lazy_mode 五列。未知旧记录留空，明确 false 写为 false；不上传或导出提示文本、回放、凭据和密钥。

## 升级与剩余生命周期

本机模型列、归档 27 和设置文档 4 均不变。服务 JSON 为可选扩展，旧结果不回填。读取旧文件不写文件；历史无字段和首次记录无字段继续保持未知。若旧文件缺少整个 XP 账本，既有迁移只能保留结果已经明确提供的配置，不能从 XP、当前设置、删除记录或默认值补造。

升级顺序为备份服务文件、停止旧 writer、升级服务，再升级客户端；本轮未部署服务。新客户端遇到旧服务的非默认成绩会拒绝投稿，不能将其改配置后发送。禁止新旧服务 writer 混写同一文件：旧 writer 可能丢弃新字段。需要回退时恢复升级前备份或向前修复；恢复旧备份会失去备份之后的新数据，不承诺无损降级。

本合同的配置字段本身不是整体兼容认证。后续服务账本已使用该证据并保留删历史后的 PB，旧公开纪元也已改为清两套 PB 与日榜；本机与标签账本、所有练习消费者及整体等价仍未完成。

## 验证证据

先行反例在旧实现上执行：客户端 3 项产生 7 个失败断言，服务 2 项产生 5 个失败断言，均无非预期异常。日志为 `/tmp/typebar-pb-configuration-native-red.log` 与 `/tmp/typebar-pb-configuration-server-red.log`。新增客户端 8 项、服务 10 项覆盖明确默认／未知、所有模式及难度、布尔组合、归档恢复、严格能力和解码、取消、CSV、HTTP、账户隔离、重试、重载、损坏和实际原子保存失败。

最终定向客户端 70 项／服务 39 项零失败、零跳过，0.609／1.004 秒；日志为 `/tmp/typebar-pb-configuration-native-final-focused.log` 和 `/tmp/typebar-pb-configuration-server-final-focused.log`。扩展测试首轮服务编译失败来自 async let 捕获 XCTest self.now；改为局部不可变日期后验证通过，未移除断言或关闭 Swift 并发检查。客户端新增测试的 async 断言及 CSV 参数在编译前修正。

本会话风险复核检查真实保存、重试、授权和读取路径，不是独立评审。真实服务部署、网络故障、旧发行程序混写、真实用户库、窗口、VoiceOver、macOS 14／Intel 和完整 PB 生命周期仍需验收。本轮不启动 Typebar GUI、不操作真实 Typebar 库。

最终完整串行门禁客户端 3004 项／服务 391 项零失败、零跳过，701.108／9.204 秒；十万词耐久 150.407 秒、九项隔离磁盘迁移 3.895 秒，源码规则对照、905 个唯一人工场景结构和未开窗应用包／原创性通过。主记录 `/tmp/typebar-pb-configuration-readiness.log`，14 份详细日志保留在 `/tmp/typebar-pb-configuration-readiness-logs.OjXu6f`。门禁完成后只更新文档，不改生产代码或测试；Typebar 图形实例启动数为零，人工场景状态仍待验收。
