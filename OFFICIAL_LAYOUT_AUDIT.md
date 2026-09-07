# 官方键盘布局兼容矩阵

## 基线与判定

- 参考仓库固定为 `monkeytypegame/monkeytype` 提交 `91bd24bb8513785c7364cbea29296ff7adafac41`。
- 固定源码的 `LayoutNameSchema` 含 239 个唯一名称；名称快照与映射保存在 `Compatibility/official-layouts.json`。
- `nativeExact` 仅表示 Typebar 有可独立选择、提示、模拟、反查、归档并进入 Layout Fluid 的语义对应布局。
- `nativeRelated` 表示已有相关原生布局，但因来源或变体不完全等价，不计入精确覆盖。
- 其余名称统一标记为 `systemInputOrCustom`：可使用 macOS 当前输入源或用户自写键盘图，但不能宣称已有同名内置实现。
- 清单只保留公开配置名称和 Typebar 自有枚举值；不读取、复制或打包 Monkeytype 键位 JSON、图例、代码或资产。

## 当前覆盖

| 状态 | 数量 | 验收含义 |
| --- | ---: | --- |
| `nativeExact` | 39 | 同名语义已有原生提示、显式输入模拟、反查和持久化测试 |
| `nativeRelated` | 3 | 仅提供相关 Typebar 原生布局，不宣称精确兼容 |
| `systemInputOrCustom` | 197 | 当前通过系统输入源或用户自定义入口处理 |
| 总计 | 239 | 与固定参考源码名称集合一一对应 |

精确覆盖名称：`qwerty`、`dvorak`、`colemak`、`colemak_dh`、`qwertz`、`swiss_german`、`swiss_french`、`workman`、`turkish_q`、`turkish_f`、`uk_qwerty`、`spanish_qwerty`、`italian_qwerty`、`latam_qwerty`、`azerty`、`persian_standard`、`persian_farsi`、`arabic_101`、`arabic_102`、`arabic_mac`、`hebrew`、`urdu_phonetic`、`thai_kedmanee`、`thai_pattachote`、`hindi_inscript`、`armenian_hm_qwerty`、`polish_programmers`、`bulgarian_phonetic_traditional`、`belarusian`、`ukrainian`、`russian`、`norwegian_qwerty`、`portuguese_pt_qwerty_iso`、`portuguese_pt_qwerty_ansi`、`swedish_qwerty`、`danish_qwerty`、`macedonian`、`pashto`、`estonian`。

相关但不等价的名称：

- `hungarian` → `Hungarian QWERTZ · Typebar`：Typebar 自写映射，不导入官方布局资产。
- `JCUKEN` → `Russian JCUKEN`：只确认同属 JCUKEN 系列，未读取参考键位 JSON，故不与独立的 `russian` 条目重复计为精确覆盖。
- `bulgarian` → `Bulgarian Cyrillic · Typebar`：Typebar 自写 Cyrillic 图，不冒充 BDS 或参考资产。

## 自动化门槛

`OfficialLayoutCoverageTests` 会验证：固定提交标识、239 个名称完整且唯一、39/3/197 三类数量守恒、每个映射名称都存在于官方集合，以及每个目标 raw value 都能解析为当前 `KeyboardLayout`。新增或重命名布局必须同步更新机器清单、该测试和本文件。
