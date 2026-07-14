<p align="center">
  <img src="https://raw.githubusercontent.com/Eko-Wang/CodexMeter/main/CodexMeterApp/Assets.xcassets/AppIcon.appiconset/icon_128.png" width="92" alt="CodexMeter icon">
</p>

<h1 align="center">CodexMeter</h1>

<p align="center">
  <strong>Codex 额度，不用再靠猜。</strong><br>
  <sub>See your Codex limits before they interrupt your work.</sub>
</p>

<p align="center">
  原生 macOS 用量仪表，自动识别当前额度窗口，并将 Token 活动放到桌面上。<br>
  A native macOS dashboard that detects active quota windows and brings token activity to your desktop.
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

### 自适应额度 / Adaptive quota windows

根据窗口时长识别 5 小时与每周额度。官方仅返回一档额度时只显示对应内容，恢复两档后会自动切回双额度布局。

CodexMeter identifies five-hour and weekly quotas by window duration. It shows the correct single limit when only one is returned, then automatically restores the dual-limit layout when both return.

### 重置时间 / Reset timing

同时显示重置倒计时和具体时间，并提供剩余可重置次数。

See both the countdown and exact reset time, plus the number of reset credits available.

### Token 活动 / Token activity

五档蓝色热力图呈现近一年的每日消耗，并汇总今日、本月、累计 Token、峰值、最长任务和连续使用天数。

A five-level blue heatmap shows daily activity across the past year, together with today, monthly, lifetime, peak, longest-task, and streak statistics.

### 三种桌面组件 / Three widget sizes

小号在双额度时使用对角数字，单额度时改为居中大数字与重置时间；中号聚焦用量进度；大号在单额度时补充 Token 统计。点击任意组件即可打开 App。

Small switches between a diagonal dual-limit layout and a centered single-limit view with reset timing. Medium focuses on quota progress, while large adds token statistics when one quota is active. Every widget opens the app with one click.

<p align="center">
  <img src="https://raw.githubusercontent.com/Eko-Wang/CodexMeter/main/promo/xiaohongshu/codexmeter-xhs-02-1242x1660.png" width="49%" alt="CodexMeter quota and token activity features">
  <img src="https://raw.githubusercontent.com/Eko-Wang/CodexMeter/main/promo/xiaohongshu/codexmeter-xhs-03-1242x1660.png" width="49%" alt="CodexMeter privacy and widget design">
</p>

## 本地优先 / Local first

CodexMeter 读取当前 Mac 上已有的 Codex 登录状态和本地活动数据。登录凭证不会复制到 Widget、项目文件或日志。独立后台代理定期更新脱敏用量快照，因此退出桌面应用后，Widget 仍能自动刷新。

CodexMeter reads the existing Codex session and local activity data on your Mac. Credentials are never copied into widgets, project files, or logs. A lightweight background agent periodically updates the sanitized snapshot, so widgets keep refreshing after the desktop app quits.

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

系统后台代理定期刷新额度，并把脱敏快照同步给 Widget；桌面应用无需保持运行。登录项可在“系统设置 > 通用 > 登录项与扩展”中关闭。

A system-managed background agent periodically refreshes limits and mirrors a sanitized snapshot to WidgetKit; the desktop app does not need to stay open. The login item can be disabled in System Settings > General > Login Items & Extensions.

额度接口偶发返回的空白新窗口快照会先进入连续确认，避免桌面组件突然跳回错误的高余额；真实定时重置或用户主动重置仍会正常生效。

Occasional blank-window responses are confirmed across consecutive samples before display, preventing widgets from jumping to an incorrect high balance while preserving scheduled and user-triggered resets.

## 素材 / Assets

`promo/xiaohongshu/` 包含本文使用的四张产品图片，以及用于复现竖版宣传图的 HTML 与 Playwright 渲染脚本。

`promo/xiaohongshu/` contains the four product images used in this README, plus the HTML and Playwright script used to reproduce the portrait campaign artwork.
