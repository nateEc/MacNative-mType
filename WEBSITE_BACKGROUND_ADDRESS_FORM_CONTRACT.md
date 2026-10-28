# 背景地址表单

固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41`。本批补齐背景设置页地址输入的提交和校验；文件选择器与完整项目仍保留各自的开放验收项。

## 实际来源与区别

`CustomBackground.tsx` 创建表单，初始值来自 getConfig。字段的 onChange 使用 `fromSchema(CustomBackgroundSchema)` 校验原始值，onBlur 调用 handleSubmit，表单 submit 事件阻止默认操作并调用同一入口。实际 onSubmit 在原始值等于 getConfig 时直接返回，否则显示保存指示并调用 setConfig。`InputField.tsx` 的 input 回调先转换文本再交给字段 handleChange，blur 回调交给 handleBlur。

这与命令面板先 trim 再校验不同：前导空格、BOM 和只有空格的表单输入会被原 schema 拒绝，空字符串则被接受。末尾空格或换行可通过实际 Zod URL／正则校验，之后 setter 保存 trim 后的值。字段本身的原始草稿与保存值分离；直接重复调用原始提交回调时，末尾空白仍会使它与已保存值不同，进而再保存一次。本批没有把原始草稿强行改成标准化后的 URL。

## 原生接线

`BackgroundSettingsPreferences.isAddressValid` 在完整配置上下文使用现有原生 WebsiteConfigSchema 校验原始字符串；提交成功后保留原始草稿及当前保存值的对应关系。外部地址或拥有者变化时同步新值，其他配置变化不抹掉未保存或错误的草稿。原生后备上下文继续使用已有 URL 规则并显示规范化地址。

设置页真实 TextField 的提交动作、失去焦点和应用按钮都走 submitAddress。编辑时显示校验错误，拒绝的值不改磁盘版本、不改变图片、不改后备设置或输入。拥有者拒绝不会写后备偏好。命令面板入口没有改成表单规则。

## 行为证据

旧路径 `/tmp/typebar-background-address-form-red.log` 的单项检查产生 7 个预期断言失败：三种原始非法输入被去空白后保存，配置版本改变，并留下错误地址。修复后 `/tmp/typebar-background-address-form-green.log` 三项检查通过，覆盖原始校验、来源对照和拥有者拒绝。

QA 探针读取实际 CustomBackground 表单配置、InputField input／blur 回调与字符串转换函数、fromSchema、原始 Zod 3.23.8 schema、setter、真实 Solid store 和背景控制器。32 条轨迹、128 个检查点分别覆盖 blur／submit、重复提交、相同地址、空值、前后空白、BOM、错误协议、大写协议／扩展名、带图片名的查询参数、引号和超长值。原生模型逐检查点比较运行时、设置快照、草稿及磁盘版本是否改变，并保留输入与后备偏好。表单／字段 API、DOM 事件与保存指示为自有适配器；这里没有声称执行 TanStack 的完整引擎或浏览器 DOM 表单。

`/tmp/typebar-background-address-native-field.log` 另以实际 NSHostingView 中的原生文本框提交动作、makeFirstResponder／失去焦点验证 SwiftUI 接线。窗口始终不可见，结束后清空视图并关闭。没有运行可见应用。后续回归还验证错误草稿失焦后不保存且继续显示。

最终 `/tmp/typebar-background-address-final-regression.log` 940 项相关回归零失败、零跳过；独立证据检查确认 122 项必需来源方法全部执行，驱动 494.362 秒。`/tmp/typebar-background-address-final-package.log` debug 包构建、签名、包资源及固定参考原创性检查通过，驱动 37.989 秒。两个原生作业串行且代码输入哈希未改变；没有启动可见 Typebar。

证据检查自身 13 项、固定参考元数据与行为审计、1,408 项人工账本结构检查通过。推送前确认参考克隆干净、开发分支无开放 PR、远端主分支未变，Actions 总数仍为 826 且最新运行成功。此次仍只推开发分支，不创建 PR。

会话内有界复核检查了原始值与保存值的区别、相等值不保存、末尾空白重复回调、错误草稿跨失焦保留、其他配置改变不抹掉草稿，以及拥有者拒绝不写后备偏好。实际源回调、原生磁盘效果与隐藏文本框接线分别验证；表单引擎和实体事件的未覆盖部分继续保留，未声称独立审查或整页完成。

## 仍需验收

TanStack 表单引擎的全部验证状态、错误指示动画、原版保存指示时序、实际按键／鼠标和多练习窗口切换的组合仍待验证。原生焦点与控件 action 检查不等于用户实体键盘验收。文件读取、上传／删除的所有异步组合继续按 BACKGROUND-SETTINGS-14 开放，完整原生重写目标保持未完成。
