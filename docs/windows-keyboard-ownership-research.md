# Windows 本机 / 远端键盘控制权切换研究

本文保留实现前的研究与建议；最终实现（包括全局恢复热键）和验收记录见 [Windows keyboard control switching](windows-keyboard-control.md)。

研究日期：2026-10-18。范围：Windows 控制端；本轮仅研究，不修改或运行客户端。外部资料来自官方文档及项目维护者源码。本地基线：`5c2ab71abf895b1bb9ad15ee45d1fade7a717ea7`；上游 master 查询值：`53996e3c404ea5083df0775057e4149e49102084`。以下区分源码事实、设计建议和待实测项。

## 结论与术语

建议将“键盘输入发到哪里”设为用户可明确切换的状态，并在切换后报告“当前控制本机”或“当前控制远端”。它与连接是否保持、远端声音是否播放、鼠标是否被抓取是不同状态。此项是产品设计建议，不能用“窗口从全屏变成窗口”替代验收。

只解决 RustDesk 自己的输入转发，不等于能暂停所有本机读屏软件。读屏自身可能先消费快捷键；需将输入目的地切换与读屏兼容性分开验证。

## 已有产品的官方行为

| 产品 / 来源 | 已核实行为 | 可以借鉴的部分 |
| --- | --- | --- |
| NVDA Remote 独立插件 | 默认 `F11` 同键往返本机与远端，可在输入手势中改键；切换有语音提示。[插件 README](https://github.com/NVDARemote/NVDARemote#controlling-the-remote-machine) | 显式状态、同键往返、明确提示。不能推断 RustDesk 应占用裸 `F11`。 |
| NVDA 内置远程访问 | 当前官方用户指南列出 `NVDA+Alt+Tab` 切换控制对象；这是内置功能的键位，与旧插件的默认键不同。[NVDA 用户指南](https://api.nvaccess.org/documentation/userGuide.html#RemoteAccess) | 只借鉴交互，不要求用户改用 NVDA。这里的在线指南不是用户本机版本清单。 |
| Windows 远程桌面 | `Ctrl+Alt+Home` 激活连接栏；`Ctrl+Alt+Break` 等组合切换全屏 / 窗口；`Ctrl+Alt+End` 打开远端 Windows 安全界面。Windows 组合键的本机 / 远端路由由另一项设置决定。[微软快捷键文档](https://learn.microsoft.com/en-us/windows/win32/termserv/terminal-services-shortcut-keys) | 返回本机工具栏是一个可用出口，但不能把上述三个快捷键说成同一个“切换控制权”命令。嵌套 RDP 快捷键另有限制。 |

## Windows 输入机制与读屏边界

1. **`RegisterHotKey` 适合接收系统热键通知。** 注册后收到 `WM_HOTKEY`，`MOD_NOREPEAT` 可防长按重复；组合被占用时通常注册失败。必须处理失败，并在不用时注销。`F12` 为调试器保留，含 Windows 键的组合为系统保留，不建议作为默认候选。[RegisterHotKey](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey)
2. **它不能替代远端转发前的拦截。** 远程客户端如果已经在底层按键回调中发送了事件，窗口稍后收到通知不可能撤销远端已执行的动作；这是由处理顺序得出的实现约束。还需核实 RustDesk 当前底层捕获与消息循环的关系。
3. **`WH_KEYBOARD_LL` 能消费事件，但没有永久最高优先级。** 返回非零可阻止后续钩子与目标窗口收到该事件；`SetWindowsHookEx` 将新钩子插到对应链首。因此，某个读屏后来安装钩子后，可能先于 RustDesk 收到输入，不能保证仅靠一个钩子屏蔽三款读屏。[LowLevelKeyboardProc](https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelkeyboardproc)、[Hooks Overview](https://learn.microsoft.com/en-us/windows/win32/winmsg/about-hooks)
4. **钩子回调必须快速返回。** 回调线程需有消息循环；超时可能导致 Windows 静默移除钩子。语音播报、界面更新、网络等待不应直接阻塞它。[LowLevelKeyboardProc](https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelkeyboardproc)
5. **从其他应用全局切回远端，比会话内切换多一个窗口激活问题。** `SetForegroundWindow` 受系统规则限制，而且可能失败。只有确定目标会话在前台后才能恢复向远端发键；激活失败应保持本机状态。这是安全输入路由的设计建议。[SetForegroundWindow](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setforegroundwindow)

NVDA 自己提供“下一个键透传”和应用睡眠模式；语音关闭模式仍会响应命令，因此静音不等于键盘透传。睡眠模式还会停止当前应用的语音 / 盲文输出，不能未经验证就作为 RustDesk 工具栏无障碍的默认解法。[NVDA 基本命令与语音模式](https://api.nvaccess.org/documentation/userGuide.html#BasicNVDACommands)

本轮没有取得足以证明 ZDSR、BoyPcReader 完整输入钩子或暂停接口契约的一手资料；两者的键位冲突、启动顺序、重启后的行为必须实测。此处不推断它们与 NVDA 相同。

## 默认快捷键候选

**优先验证 `Ctrl+Shift+F11` 同键往返，仅对前台远程会话生效。** 这是待验证候选，不是已确认无冲突的最终键位。好处是不用读屏专用的 Insert / CapsLock，也不占用裸 F11。在线 NVDA 用户指南和 `globalCommands.py` 未发现这个默认组合；这一检索不覆盖 NVDA 插件、用户自定义手势或其他应用。[NVDA 默认全局命令源码](https://github.com/nvaccess/nvda/blob/6c981c640e9b586da3d6aae32422d3ff83e1d904/source/globalCommands.py)

| 候选 | 评价 |
| --- | --- |
| `Ctrl+Shift+F11` | 首选验证；笔记本可能另需 Fn。需验证 Ctrl+Shift 释放是否误切输入法。 |
| `Ctrl+Shift+F10` | 首选被用户现有快捷键占用时的备选；同样不能声称无冲突，且应验证不会误执行 Shift+F10 上下文菜单。 |
| 裸 `F11` | 与 NVDA Remote 独立插件默认控制切换键重合，不作为本项目默认值。 |
| `NVDA+Alt+Tab` | 已属于 NVDA 内置远程功能，不适合作为支持三款读屏的通用 RustDesk 默认值。 |
| `Ctrl+Alt+Home` / `Ctrl+Alt+End` / `Ctrl+Alt+Pause` | 前两者与 RDP 既有行为重合；后者是 RustDesk 待合入提案的选择。当前 RustDesk 相对鼠标模式在 Ctrl+Alt 同时按下时就退出，需处理组合前缀冲突；Pause 在部分键盘上也不便输入。 |
| `F12` 或含 Windows 键的组合 | 不作为 `RegisterHotKey` 默认候选，参见上述系统保留规则。 |

如果首版限定前台会话，交互应明确：切回本机后，用户可以操作 RustDesk 工具栏，或用本机 `Alt+Tab` 去其他程序；返回 RustDesk 会话后再按同一组合恢复远端。若需要在任意应用中一键返回远端，应另行定义全局注册、多个会话的目标选择与窗口激活失败行为。

## 可参考的 NVDA 原生输入处理

NVDA 当前内置远程实现通过 `inputCore.decide_handleRawKey` 参与 NVDA 自己的输入处理，在远端模式中保留本机切换命令、转发其余键；回到本机时释放远端修饰键。源码还记录切换前已在本机按下的键，避免把其后续释放错误地交给远端。[NVDA remote client 源码](https://github.com/nvaccess/nvda/blob/6c981c640e9b586da3d6aae32422d3ff83e1d904/source/_remoteClient/client.py)

同一文件的 `releaseKeys()` 特别检查“单独释放修饰键是否会触发动作”，必要时先发送 `VK_NONE` 再释放。借鉴重点是防止组合键的一部分已送出后，仅吞掉主键造成 Ctrl+Shift 切输入法或 Alt 打开菜单；不能未经协议核实把 NVDA 的 `VK_NONE` 约定直接复制到 RustDesk。

## 实现前需要验证的结果

以下是待实现后的验收要求，本次没有运行客户端或宣称已通过：

- 两个方向切换均不需要移动鼠标，且可听到当前控制对象；文本状态也能通过读屏重读。
- 切回本机后 `Tab`、`Alt+Tab`、Windows 键和读屏命令在本机生效；恢复后预期的远端按键正常。
- 切换组合本身不执行远端应用命令；按下 / 释放均配对；长按只切换一次；Ctrl、Shift、Alt 不残留，输入法和菜单不被误触发。
- 切回本机后鼠标原地停在远端画面、窗口重新获得焦点，都不会自动抢回远端键盘。
- 本机模式中打开工具栏、聊天或本机对话框时不会向远端泄漏输入；关闭、失焦、断线、重连有可解释的状态。
- NVDA、ZDSR、BoyPcReader 分别验证；至少覆盖读屏先启动、RustDesk 先启动、会话中重启读屏。与真实键盘共同测试，不能只用模拟快捷键通过代替。
- 窗口 / 全屏、常用键盘输入模式、多会话、普通 / 提权环境分别核查。首版没有覆盖的场景明确标记，不称全兼容。

## RustDesk 源码调查

### 当前版本的实际路径

1. Windows 默认输入源为原生 rdev 路径。`init_input_source()` 启动抓键线程，`change_input_source()` 支持另一条 Flutter 输入路径。这两个输入源与 Map / Translate / Legacy 键盘映射模式是不同概念。[keyboard.rs:1544](https://github.com/jintonglu6688/rustdesk/blob/5c2ab71abf895b1bb9ad15ee45d1fade7a717ea7/src/keyboard.rs#L1544)
2. Windows 远端画面的焦点变化调用 `InputModel.enterOrLeave()`，再经 `session_enter_or_leave()` 进入 `change_grab_status(Run/Wait)`。Rust 已按会话窗口 UUID 记录抓取归属，过滤旧窗口的延迟释放。[remote_page.dart:723](https://github.com/jintonglu6688/rustdesk/blob/5c2ab71abf895b1bb9ad15ee45d1fade7a717ea7/flutter/lib/desktop/pages/remote_page.dart#L723)、[input_model.dart:1138](https://github.com/jintonglu6688/rustdesk/blob/5c2ab71abf895b1bb9ad15ee45d1fade7a717ea7/flutter/lib/models/input_model.dart#L1138)、[flutter_ffi.rs:653](https://github.com/jintonglu6688/rustdesk/blob/5c2ab71abf895b1bb9ad15ee45d1fade7a717ea7/src/flutter_ffi.rs#L653)、[keyboard.rs:158](https://github.com/jintonglu6688/rustdesk/blob/5c2ab71abf895b1bb9ad15ee45d1fade7a717ea7/src/keyboard.rs#L158)
3. 原生抓取期间，普通按键由 Rust 先转换、发送；按下事件被消费，释放事件仍可向本机传播，CapsLock / NumLock 另有例外。故 Flutter 界面快捷键不能独立承担退出原生抓取的职责。释放抓取后 Windows hook 保留，但正常事件透传本机；这一点可以支持反向恢复。[keyboard.rs:612](https://github.com/jintonglu6688/rustdesk/blob/5c2ab71abf895b1bb9ad15ee45d1fade7a717ea7/src/keyboard.rs#L612)
4. `Wait` 会取出已发送按下的键，补发释放；Flutter 输入路径也有 `toReleaseKeys` / `toReleaseRawKeys`。应复用这些路径，同时处理新快捷键的自动重复、跨状态释放和修饰键副作用，不能只翻转一个 UI 布尔值。[keyboard.rs:287](https://github.com/jintonglu6688/rustdesk/blob/5c2ab71abf895b1bb9ad15ee45d1fade7a717ea7/src/keyboard.rs#L287)、[keyboard.rs:737](https://github.com/jintonglu6688/rustdesk/blob/5c2ab71abf895b1bb9ad15ee45d1fade7a717ea7/src/keyboard.rs#L737)
5. `onWindowFocus()` 在鼠标仍处于远端画面时会请求远端焦点；`enterView()`、鼠标按下也会请求焦点。因此必须保存用户明确选择的本机状态，并让相应抓取入口尊重它。只在热键里调用一次 `Wait`，不能保证本机状态持续有效。[remote_page.dart:521](https://github.com/jintonglu6688/rustdesk/blob/5c2ab71abf895b1bb9ad15ee45d1fade7a717ea7/flutter/lib/desktop/pages/remote_page.dart#L521)、[remote_page.dart:834](https://github.com/jintonglu6688/rustdesk/blob/5c2ab71abf895b1bb9ad15ee45d1fade7a717ea7/flutter/lib/desktop/pages/remote_page.dart#L834)
6. 当前 `Ctrl+Alt` 只在相对鼠标模式有效，用于退出该模式，不是通用的本机 / 远端键盘切换。[keyboard.rs:483](https://github.com/jintonglu6688/rustdesk/blob/5c2ab71abf895b1bb9ad15ee45d1fade7a717ea7/src/keyboard.rs#L483)、[input_model.dart:1225](https://github.com/jintonglu6688/rustdesk/blob/5c2ab71abf895b1bb9ad15ee45d1fade7a717ea7/flutter/lib/models/input_model.dart#L1225)

### 可借鉴的上游提案与作者其他改动

截至本次 GitHub API 查询，[PR #16173](https://github.com/rustdesk/rustdesk/pull/16173) 仍为 **open、未合入**，头提交 `5d3d20ec6eca4f8779211d5841ca659e9ca927e2`。关联 [Issue #16174](https://github.com/rustdesk/rustdesk/issues/16174) 关闭的原因是转为 Discussion，不能据此说功能已发布。

已查看该 PR 全部非翻译补丁，并查询作者 `ujmyvq1582` 的 RustDesk PR、fork 分支及公开相关仓库。当前查到这一份 PR；fork 的功能分支相对 master 有五个提交，均属于该功能及测试。未发现另一个覆盖全客户端的无障碍改造分支。这是本次公开检索的范围，不代表作者没有未公开或已删除的其他工作。[作者 fork](https://github.com/ujmyvq1582/rustdesk)、[功能分支差异](https://github.com/ujmyvq1582/rustdesk/compare/bf1ebe5be2f5ac1ce634572e9ff7bc88e8b1d6aa...5d3d20ec6eca4f8779211d5841ca659e9ca927e2)

该提案除了热键，确有配套无障碍工作：

| 改动 | 可复用价值 | 本项目还需核实 |
| --- | --- | --- |
| `Ctrl+Alt+Pause/Break` 在原生 hook 中切换抓取 | 拦截位置早于远端发送；复用已有 Run / Wait | 默认键位、相对鼠标模式冲突、显式本机状态、前台会话限定 |
| Rust 发送 `keyboard_grab` 会话事件 | UI 状态来自实际抓取变化，而非按键后猜测 | 同时与用户选择的本机状态区分；失焦不是用户永久退出 |
| 现有键盘工具栏按钮提供本机 / 远端状态文本和颜色 | 无需新增一排空焦点；有可查询状态 | 不能仅依赖颜色或鼠标 tooltip；应进入按钮无障碍名称 / 状态 |
| Windows 原生 `UiaRaiseNotificationEvent` | 在不移动焦点时向辅助技术报告切换 | 这是 UIA 通知，不保证三款读屏都会播报；需比较已有 Flutter 宣告路径 |
| 无键盘权限、只读或非远控会话不能重新抓取；模型清理时复位状态 | 保留权限边界，避免重用会话时状态残留 | 断线、切换标签、当前前台窗口以及两种输入源都需覆盖 |
| 按键重复、平台 Pause 映射和状态清理测试 | 可借鉴验收场景 | 其模拟测试不代替真实读屏与键盘验证 |

来源为 [PR 的实际文件差异](https://github.com/rustdesk/rustdesk/pull/16173/files)。其中 native 通知通过 method channel 取得 Flutter 窗口的 UIA provider，再发送通知；没有添加 NVDA 专用插件，也没有自动暂停 ZDSR / BoyPcReader。

不能直接整份移植的原因（源码审查推论，尚未运行该 PR）：

- 恢复抓取使用 `get_cur_session()`，所读补丁中没有检查真实前台窗口，也没有先激活目标窗口。残留的“当前会话”不能独立证明用户正准备控制它。
- 没有修改 `remote_page.dart` 的焦点 / 鼠标重获逻辑；明确本机状态和工具栏 Tab 流程仍需补齐。
- 功能明确依赖原生输入源；Flutter 输入源不支持该切换，状态 getter 也会隐藏其提示。
- 本机转远端时快捷键的部分修饰键可能先在本机按下；远端转本机则相反。需核对两端释放配对、输入法和菜单副作用，不能把截图或编译成功当作完成。

上游另有已于 **2026-10-13 合入**的 [PR #14933](https://github.com/rustdesk/rustdesk/pull/14933)，提供可配置的会话快捷键。当前本地没有该模块；所查 master 的 [动作注册表](https://github.com/rustdesk/rustdesk/blob/53996e3c404ea5083df0775057e4149e49102084/src/keyboard/shortcuts.rs#L17) 没有键盘抓取切换动作。`switch_sides` 是互换控制角色，`toggle_view_only` 是只读模式，均不能替代本机 / 远端键盘模式。如果后续同步该功能，应复用它的改键界面和事件处理，而不是维护两套通用快捷键框架；本轮不合并上游。

### 最小实现建议

- **控制端改动即可。** 复用既有键盘消息，不需要改变中继配置或要求被控端实现新的控制权协议。这是由现有客户端抓取和发送链得出的判断。
- **首版限定前台远控会话。** 一个可更改的组合键同键往返。连接和远端声音继续；本机状态时允许 Tab 到本机工具栏，允许 Alt+Tab 操作其他程序。回到 RustDesk 后再次按键进入远端，不因鼠标悬停或窗口恢复焦点自动进入。明确点击远端画面是否恢复，可保留为鼠标用户的主动操作。
- **状态和焦点一起切换。** 本机模式将焦点放到可访问的现有键盘工具栏控件，并阻止 Tab 误入抓键画面；进入远端时聚焦远端画面。快捷键不应在密码等本机模态对话框打开时重新抓键。
- **热键在原生转发前识别。** Flutter 输入源也要有对应的拦截 / 焦点规则。复用现有事件通道和 Run / Wait；保持不支持平台的旧路径。无需为单个功能引入新的全局快捷键依赖。
- **先确保原生停止发送，再更新 UI。** 切换主键与其重复 / 释放被消费；已有修饰键配对释放。恢复时妥善处理还未松开的切换组合，不让第一个普通键带上残留 Ctrl / Shift。切换成功后报告“键盘已切换到本机”或“键盘已切换到远端：设备名称”。
- **优先试现有宣告能力。** 本机定制 Flutter engine 已实现 accessibility channel 的 `announce` → `AnnounceAlert` → Windows 无障碍事件路径，无需先增加新的桥接接口。源码位置：`D:/Dev/SDKs/rustdesk-engine/src/flutter/shell/platform/windows/accessibility_plugin.cc:92`、`flutter_windows_view.cc:766`。是否在 RustDesk 多窗口及三款读屏中有效仍待测；若不足，再借鉴 PR 的 UIA notification。无论哪种通知，都保留可重读的文本状态，避免仅有一声提示。

预期涉及 Rust 键盘捕获入口及现有 FFI / 会话事件、Flutter 远控页面焦点、输入模型、工具栏和翻译。若已有宣告满足需要，不改 native runner / Flutter engine。中继服务器、被控端注入、接受连接安全保护、Android 和此前延后的服务状态改造不属于本功能。

研究阶段仅新增本文档，未改应用代码或进行双端连接、读屏、编译及运行验证；后续实现和验证记录见上方链接。
