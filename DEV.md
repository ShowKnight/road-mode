# 迭代说明（DEV.md）

这份文档是给"三个月后的自己"看的：忘了这个项目怎么跑、怎么改、改完怎么发，照这里做就行。

## 一分钟上手

```bash
cd ~/Documents/AgenticEngineer/road-mode

./scripts/build.sh              # 只构建到 ./build/RoadMode.app
./scripts/build.sh --install    # 构建 + 装到 /Applications 并启动
./scripts/release.sh "说明文字"  # 构建自检 + 提交 + 双仓推送（日常就用这个）
```

首次在新机器上装：先 `sudo ./scripts/install-sudoers.sh`（只跑一次），否则每次点击都要输密码。

## 代码地图

只有一个文件 `src/main.swift`（约 170 行），按四块读：

| 区块 | 干什么 |
|---|---|
| `buildStatusItem()` | 建菜单栏图标，绑定点击 |
| `handleClick()` | 2.5 秒防抖，然后开 / 关 |
| `activate()` / `deactivate()` | 置 `SleepDisabled`、拉起 / 杀掉 `caffeinate`、刷新界面 |
| `tick()`（每秒心跳） | 到期判定、倒计时刷新、`caffeinate` 掉了就重生 |

改界面只动 `refresh()`；改时长只动 `windowSeconds`；改免密范围只动 `scripts/install-sudoers.sh`。

## 改完必须做的三种验收

**1. 开关是否真的生效**（这条最重要，界面好看但开关不生效等于零）

```bash
pmset -g | awk '/SleepDisabled/{print $2}'   # 点之前 0 / 点之后 1 / 再点 0
```

**2. 合盖场景是否真的不睡**

```bash
ioreg -r -k AppleClamshellState -d 4 | grep Clamshell    # 确认 Yes（真的合着）
pmset -g batt | head -1                                   # 确认当前供电方式
```

合盖状态下如果还能在这个机器上跑命令（比如远程 SSH 进来、或本地脚本仍在执行），就是活体证明。

**3. 倒计时是否真的在走**

```bash
osascript -e 'tell application "System Events" to tell process "RoadMode" to get {position, size} of menu bar item 1 of menu bar 1'
```

激活态宽度会从 38pt 撑到约 72pt（因为多了 `59m` 文字），位置 `x` 也会跟着左移。

## 三个已知的坑（改之前先读）

1. **别用 `caffeinate` 去做"合盖不睡"。** `-i` / `-u` 挡不住合盖，唯一有效的是 `SleepDisabled`。`caffeinate` 在这里只是顺带压住空闲休眠，别指望它挡合盖。
2. **别相信 `caffeinate` 一直活着。** 它会被各种清理脚本 SIGTERM 掉，所以才有每秒心跳重生逻辑。删掉心跳，功能就会时好时坏。
3. **带刘海机型菜单栏会吞图标。** 状态项从右往左排，溢出部分落在刘海左侧且不再绘制（本机实测缺口约 400pt）。新加的图标如果看不见，不是代码坏了，是排不进去。对策：图标做窄（34pt 级）、或折叠掉不常用的图标。

## 版本号与文档

- `src/Info.plist` 的 `CFBundleShortVersionString` 是版本号
- 每一次形态变化或真 bug 修复，在 `CHANGELOG.md` 补一段（重点写**为什么**，不是写"优化了体验"）
- README 面向使用者，DEV.md 面向自己，别混写

## 两个远端

```bash
git push github main   # https://github.com/ShowKnight/road-mode
git push origin main   # 内网 itgitlab.sangfor.com/blank2543320/road-mode
```

`./scripts/release.sh` 会两个一起推。内网仓库默认 Private，要同事看到得在网页上把 Visibility 改成 Internal。

## 如果哪天要做"自动续期 / 开机自愈"

先读 CHANGELOG 的「未做的事」，那几条都写清楚了该动哪个函数：

- 开机自愈 → `applicationDidFinishLaunching` 里读一次 `SleepDisabled`，为 1 就主动置 0
- 到期提醒 → `tick()` 里加阈值判断，用 `UNUserNotificationCenter` 发通知
- 图标宽度固定 → `refresh()` 里把 `item.length` 设成固定值，倒计时用小字号画在 `button.image` 的 badge 上
