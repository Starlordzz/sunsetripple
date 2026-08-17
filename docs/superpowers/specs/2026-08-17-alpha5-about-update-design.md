# Alpha 5 关于与更新设计

## 目标

在不干扰建房和通话主流程的前提下，为 alpha5 增加一个可发现的“关于与更新”底部页，提供版本信息、GitHub 项目、CHANGELOG、许可证与隐私说明，并为后续签名更新协议保留可替换的纯 JVM 接口。

## 范围

- 首页麦克风检查区域下方增加低权重版本页脚。
- 点击页脚打开底部页；返回键和关闭按钮回到首页。
- 关于页展示当前 `versionName`、GitHub 项目链接、CHANGELOG、许可证和隐私说明。
- 更新检查本轮只实现状态模型与 fake 可测试接口，默认手动触发；不下载、不安装、不请求未知来源包权限。
- 外部链接通过 Android `Intent.ACTION_VIEW` 打开系统浏览器。
- 不在本轮迁移全部字符串资源，不重新启用 Nearby，也不改变房间生命周期。

## 边界与数据流

`MainActivity` 只组装 Android 依赖并把事件传入 Compose。关于页 UI 使用不可变 `AboutUpdateState`；更新逻辑依赖 `UpdateChecker` 接口，返回 `Idle`、`Checking`、`Available`、`UpToDate` 或 `Failed`。默认实现可以报告“暂未配置更新源”，fake 用于 JVM 测试状态转换。

## 验收

- 首页可以打开和关闭关于页，返回键行为稳定，通话未启动时不影响现有房间入口。
- 版本信息来自构建配置，不在 UI 中硬编码 alpha4。
- GitHub、CHANGELOG、许可证和隐私说明均可点击或展开查看；浏览器不可用时显示可测试的失败状态。
- 更新状态转换有纯 JVM 测试，重复点击检查不会并发启动第二次检查。
- 现有 `testDebugUnitTest`、`assembleDebug`、`lintDebug` 继续通过。
