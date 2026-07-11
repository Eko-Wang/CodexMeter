<p align="center">
  <img src="https://raw.githubusercontent.com/Eko-Wang/CodexMeter/main/CodexMeterApp/Assets.xcassets/AppIcon.appiconset/icon_128.png" width="92" alt="CodexMeter icon">
</p>

<h1 align="center">CodexMeter</h1>

<p align="center">
  <strong>Codex 额度，不用再靠猜。</strong><br>
  <sub>See your Codex limits before they interrupt your work.</sub>
</p>

<p align="center">
  原生 macOS 用量仪表，将 5 小时额度、每周额度和 Token 活动放到桌面上。<br>
  A native macOS dashboard for five-hour limits, weekly limits, and token activity.
</p>

<p align="center">
  <a href="https://github.com/Eko-Wang/CodexMeter/releases/latest"><strong>下载最新版 / Download</strong></a>
  &nbsp;&nbsp;|&nbsp;&nbsp;
  <a href="https://github.com/Eko-Wang/CodexMeter/releases/latest">Release notes</a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Eko-Wang/CodexMeter/main/promo/xiaohongshu/codexmeter-xhs-01-1242x1660.png" width="720" alt="CodexMeter product overview">
</p>

## 概览 / Overview

CodexMeter 把最常查看的额度和活动数据整理成一块安静、清晰的 macOS 仪表盘。打开 App 可以查看完整活动，桌面小组件则让剩余额度始终触手可及。

CodexMeter turns the usage data you check most often into a calm, focused macOS dashboard. Open the app for the complete activity view, or keep remaining limits visible through native desktop widgets.

<p align="center">
  <img src="https://raw.githubusercontent.com/Eko-Wang/CodexMeter/main/promo/xiaohongshu/codexmeter-app-light-1232x1188.png" width="860" alt="CodexMeter macOS application showing token activity and quota windows">
</p>

## 功能 / Features

### 两档额度 / Dual quota windows

分别显示 5 小时与每周剩余百分比，并使用不同色彩快速区分。

Track five-hour and weekly limits separately, with distinct colors for faster reading.

### 重置时间 / Reset timing

同时显示重置倒计时和具体时间，并提供剩余可重置次数。

See both the countdown and exact reset time, plus the number of reset credits available.

### Token 活动 / Token activity

五档蓝色热力图呈现近一年的每日消耗，并汇总今日、本月、累计 Token、峰值、最长任务和连续使用天数。

A five-level blue heatmap shows daily activity across the past year, together with today, monthly, lifetime, peak, longest-task, and streak statistics.

### 三种桌面组件 / Three widget sizes

小号用双环显示额度，中号聚焦两档用量，大号同时展示额度与热力图。点击任意组件即可打开 App。

Small uses concentric rings, medium focuses on both quota windows, and large combines limits with token activity. Every widget opens the app with one click.

<p align="center">
  <img src="https://raw.githubusercontent.com/Eko-Wang/CodexMeter/main/promo/xiaohongshu/codexmeter-xhs-02-1242x1660.png" width="49%" alt="CodexMeter quota and token activity features">
  <img src="https://raw.githubusercontent.com/Eko-Wang/CodexMeter/main/promo/xiaohongshu/codexmeter-xhs-03-1242x1660.png" width="49%" alt="CodexMeter privacy and widget design">
</p>

## 本地优先 / Local first

CodexMeter 读取当前 Mac 上已有的 Codex 登录状态和本地活动数据。登录凭证不会复制到 Widget、项目文件或日志。独立后台代理每分钟更新一次脱敏用量快照，因此退出桌面应用后，Widget 仍能自动刷新。

CodexMeter reads the existing Codex session and local activity data on your Mac. Credentials are never copied into widgets, project files, or logs. A lightweight background agent updates the sanitized snapshot every minute, so widgets keep refreshing after the desktop app quits.

## 安装 / Install

1. 从 [Releases](https://github.com/Eko-Wang/CodexMeter/releases/latest) 下载 DMG。<br>
   Download the DMG from [Releases](https://github.com/Eko-Wang/CodexMeter/releases/latest).
2. 将 `CodexMeter.app` 拖入“应用程序”。<br>
   Drag `CodexMeter.app` into Applications.
3. 运行一次 CodexMeter。<br>
   Launch CodexMeter once.
4. 在桌面右键选择“编辑小组件”，搜索 `CodexMeter`。<br>
   Right-click the desktop, choose Edit Widgets, and search for `CodexMeter`.

> 当前公开构建使用本地签名，尚未经过 Apple Developer ID 公证。首次打开时，macOS 可能要求在 Finder 中右键应用并选择“打开”。<br>
> The current public build is locally signed and not yet notarized with an Apple Developer ID. On first launch, macOS may require you to right-click the app in Finder and choose Open.

## 系统要求 / Requirements

- macOS 14 or later
- An active Codex or ChatGPT login on this Mac
- ChatGPT App installed for official account token activity

## 从源码构建 / Build from source

1. 使用 Xcode 15 或更高版本打开 `CodexMeter.xcodeproj`。<br>
   Open `CodexMeter.xcodeproj` with Xcode 15 or later.
2. 选择 `CodexMeter` scheme 和当前 Mac。<br>
   Select the `CodexMeter` scheme and your Mac.
3. Build & Run.

系统后台代理每分钟刷新额度，并把脱敏快照同步给 Widget；桌面应用无需保持运行。登录项可在“系统设置 > 通用 > 登录项与扩展”中关闭。

A system-managed background agent refreshes limits every minute and mirrors a sanitized snapshot to WidgetKit; the desktop app does not need to stay open. The login item can be disabled in System Settings > General > Login Items & Extensions.

## 素材 / Assets

`promo/xiaohongshu/` 包含本文使用的四张产品图片，以及用于复现竖版宣传图的 HTML 与 Playwright 渲染脚本。

`promo/xiaohongshu/` contains the four product images used in this README, plus the HTML and Playwright script used to reproduce the portrait campaign artwork.
