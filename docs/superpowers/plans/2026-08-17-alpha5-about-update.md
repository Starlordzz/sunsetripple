# Alpha 5 关于与更新实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 增加可测试的关于与更新底部页，并把首页入口接入现有 Compose 导航。

**架构：** Compose 通过 `Screen` 状态显示 About 页面；`AboutUpdateState` 与 `UpdateChecker` 保持 Android 无关。`MainActivity` 负责版本读取、浏览器 Intent 和依赖组装，不承载更新状态机。

**技术栈：** Kotlin、Jetpack Compose Material 3、JUnit 4、现有单 Activity 导航。

---

### 任务 1：定义更新状态与纯 JVM 检查器

**文件：**
- 创建：`app/src/main/kotlin/host/msknet/sunsetripple/update/UpdateChecker.kt`
- 测试：`app/src/test/kotlin/host/msknet/sunsetripple/update/UpdateCheckerTest.kt`

- [ ] **步骤 1：编写状态转换测试**：覆盖 idle→checking、available、up-to-date、failed，以及 checking 状态拒绝重复启动。
- [ ] **步骤 2：运行 `./gradlew :app:testDebugUnitTest --tests '*UpdateCheckerTest'` 确认测试先失败**。
- [ ] **步骤 3：实现不可变状态、结果类型和串行检查器**。
- [ ] **步骤 4：重新运行同一测试确认通过**。
- [ ] **步骤 5：提交 `feat: add alpha5 update state model`**。

### 任务 2：增加关于页 UI

**文件：**
- 创建：`app/src/main/kotlin/host/msknet/sunsetripple/ui/AboutUpdateScreen.kt`
- 修改：`app/src/main/kotlin/host/msknet/sunsetripple/ui/RoomFlow.kt`
- 测试：`app/src/test/kotlin/host/msknet/sunsetripple/ui/AboutUpdateScreenTest.kt`

- [ ] **步骤 1：为页面状态和关闭/检查事件写 JVM 决策测试**。
- [ ] **步骤 2：运行目标测试确认失败**。
- [ ] **步骤 3：实现底部页布局、版本文本、链接按钮、更新状态和关闭入口，复用现有配色与按钮组件**。
- [ ] **步骤 4：接入 `Screen.ABOUT_UPDATE`，保持返回栈回到首页**。
- [ ] **步骤 5：运行目标测试确认通过并提交 `feat: add alpha5 about screen`**。

### 任务 3：首页入口与 Android 依赖接线

**文件：**
- 修改：`app/src/main/kotlin/host/msknet/sunsetripple/ui/HomeScreen.kt`
- 修改：`app/src/main/kotlin/host/msknet/sunsetripple/MainActivity.kt`
- 修改：`app/src/main/kotlin/host/msknet/sunsetripple/ui/RoomFlow.kt`

- [ ] **步骤 1：增加页脚点击事件和关于页导航测试**。
- [ ] **步骤 2：运行相关 UI 测试确认失败**。
- [ ] **步骤 3：接入构建版本读取、浏览器 Intent、CHANGELOG/许可证/隐私文本展开和返回键处理**。
- [ ] **步骤 4：运行相关测试确认通过并提交 `feat: wire alpha5 about update flow`**。

### 任务 4：全量验证与文档同步

**文件：**
- 修改：`README.md`
- 修改：`CHANGELOG.md`
- 修改：`docs/wiki/构建与发布.md`

- [ ] **步骤 1：同步 alpha5 当前功能与未实现更新协议的限制**。
- [ ] **步骤 2：运行 `./gradlew :app:testDebugUnitTest :app:assembleDebug :app:lintDebug`**。
- [ ] **步骤 3：检查分支 diff，确认未跟踪环境文件未被加入**。
- [ ] **步骤 4：提交 `docs: document alpha5 about update slice`**。
