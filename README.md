# RoadMode · 路上模式

> 一个 34pt 的菜单栏小图标：点一下，让 MacBook **合盖也不休眠，持续 60 分钟**，到点自动还原。
> 出门在包里跑 AI 任务 / 挂着 SSH / 远程下载，不用改电源设置，不用每次输密码。

![合盖不休眠倒计时](assets/screenshots/countdown.png)

**RoadMode** is a tiny macOS menu bar utility: click once and your MacBook **stays awake with the lid closed for 60 minutes**, then restores itself automatically. Useful when an AI task, SSH session or download must survive a closed lid on the go.

- Uses the only switch that actually works for clamshell sleep: `SleepDisabled` (via `pmset -a disablesleep`)
- Password-free after a one-time `sudoers` allow-list (exactly two whitelisted arguments, nothing more)
- Live countdown in the menu bar, heart-beating `caffeinate`, no Dock icon, no hotkey
- macOS 13+, tested on macOS 26.4.1 / Apple Silicon; MIT licensed — PRs welcome

---

---

## 为什么做这个

macOS 上「合盖不睡」这件事，网上的教程基本都给错答案：

- `caffeinate -i` / `-u` 这类断言**挡不住合盖**。合盖行为由 `SleepDisabled` 这个开关决定。
- 改「合盖时永不睡眠」的系统设置要动电源策略，而且关盖行为在 Apple Silicon 上并不完全受那些勾选框控制。
- 手动敲 `sudo pmset -a disablesleep 1` 能用，但**每次都要输密码**，而且容易忘了关 —— 包里的机器会一直耗电。

所以这里做三件事把它变成「点一下」：

1. **`SleepDisabled` 开关** —— 唯一真正能阻止合盖休眠的开关
2. **sudoers 白名单** —— 只放行两条精确参数，之后免密，安全边界清晰
3. **60 分钟自动倒计时** —— 到点自动还原，不会忘了关

## 效果

| 场景 | 不点按钮 | 点了按钮（60 分钟内） |
|---|---|---|
| 合盖 + 电池 + 无外接屏 | 立刻睡眠，SSH / 任务全断 | 不睡，进程继续跑，网络保持 |
| 合盖 + 电源 + 无外接屏 | 也会睡（跟插不插电无关） | 不睡 |
| 合盖 + 外接屏 + 电源 | 原生 clamshell 模式，本来醒着 | 一样，按钮多余但不冲突 |
| 开盖 | 正常 | 正常 |

图标两态：灰色空心杯 = 关闭；绿色实心杯 + `59m` = 倒计时中。

| 关闭 | 倒计时 |
|---|---|
| ![](assets/screenshots/idle.png) | ![](assets/screenshots/countdown.png) |

## 安装

```bash
# 1. 先装免密白名单（只需一次，会要你输一次密码）
sudo ./scripts/install-sudoers.sh

# 2. 构建并安装
./scripts/build.sh --install
```

装完菜单栏会出现一个咖啡杯图标，开机自启由 App 自己写入 `~/Library/LaunchAgents/com.lonqi.roadmode.plist`。

卸载：

```bash
rm -rf /Applications/RoadMode.app
rm -f  ~/Library/LaunchAgents/com.lonqi.roadmode.plist
sudo rm -f /etc/sudoers.d/roadmode
```

## 工作原理

```
点击菜单栏图标
   ├─ sudo -n pmset -a disablesleep 1     ← 阻止合盖休眠（免密，走 sudoers 白名单）
   ├─ caffeinate -dimsu -t 3600            ← 顺带压住空闲/显示休眠
   └─ Timer 每秒心跳                        ← 刷新倒计时；caffeinate 被杀会自动重生

倒计时归零 / 再点一次
   └─ sudo -n pmset -a disablesleep 0 + 结束 caffeinate
```

设计上刻意做的取舍：

- **状态只由倒计时决定**，不信任 caffeinate 是否还活着（它经常被清理内存的脚本杀掉），心跳发现不在就立即重生
- **2.5 秒防抖**，防 macOS 把一次物理点击重复投递（早期版本出现过一次点击被回放 3 次、状态疯狂翻转）
- **无 Dock 图标、无快捷键、无右键菜单**，就一个图标一个动作
- 免密只放行 `pmset -a disablesleep 1` 和 `... 0` 两条**完整参数**，不是整个 pmset，也不是笼统的 sudo

## 已知限制（欢迎一起优化）

1. **菜单栏被占满时新图标会被挤到刘海左边，看不见。**
   这是 macOS（带刘海机型）的行为：状态项从右往左排，溢出部分藏在刘海左侧且不再绘制。本项目的应对是保持图标极窄（34–72pt），并配合菜单栏管理器（[Thaw](https://github.com/thaw-app/Thaw) / Ice）把不常用的图标折叠起来腾位。
2. **图标默认宽度会随倒计时变化**（38pt → 72pt）。如果你希望宽度固定、倒计时用更小的字号或干脆不显示，改 `refresh()` 即可。
3. **未做开机后自动恢复**：如果机器在倒计时途中被强制关机，`SleepDisabled` 会留在 1。启动时主动校正一次是个很好的 PR。
4. **未上沙盒 / 未公证**：ad-hoc 签名，首次运行可能被 Gatekeeper 拦一次。
5. **未支持 Intel Mac**：构建脚本按 arm64 编译，Intel 机器需要自己改 target。
6. **倒计时到点直接睡**，不会先给个提醒。加一个「还剩 5 分钟」的通知，或者「到期询问是否续期」也是不错的增强。

### 想参与优化的话

- Fork 后直接提 MR / PR，代码只有一个文件 `src/main.swift`（约 200 行，零第三方依赖）
- 优先级最高的三个方向：**图标不被刘海吞掉**、**异常退出后的状态自愈**、**多显示器 / 外接屏下的行为区分**
- 提 issue 时贴 `pmset -g | grep SleepDisabled` 和 `ioreg -r -k AppleClamshellState -d 4 | grep Clamshell` 的输出，定位会快很多

## 兼容性

- macOS 13+（在 macOS 26.4.1 / Apple Silicon 上实测通过）
- 编译依赖：Xcode Command Line Tools（`swiftc`）
- 需要你本人能在终端执行 sudo（用于一次性安装白名单）

## 许可

MIT，见 [LICENSE](LICENSE)。
