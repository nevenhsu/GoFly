# GoFly — 开发中

[English](README.md) · [繁體中文](README.zh-Hant.md) · **简体中文**

用于研究 iOS 模拟定位、设备连接与原生 App 操作流程的 Mac／iPhone 项目。预定使用方式：下载 Mac DMG、打开 GoFly、通过 USB 连接 iPhone，再由 Mac 安装手机 App。

**开发状态 — 2026-10-17：目前尚未提供可下载的 DMG，也未完成 GoFly 完整安装流程。** 现有 Mac App 提供只读检查与流程预览；新版 iOS App 开发中。LocalGo 是较早的研究 prototype，其真机记录不能视为 GoFly 正式版验收。

## 目录

- [设备与环境](#设备与环境)
- [下载与安装](#下载与安装)
- [体验当前开发版](#体验当前开发版)
- [研究操作](#研究操作)
- [交给 AI 协助安装](#交给-ai-协助安装)
- [常见问题](#常见问题)
- [文档与源代码](#文档与源代码)
- [许可](#许可)

## 设备与环境

| 项目 | 要求 |
| --- | --- |
| 电脑 | 需要 Mac。现有 Mac App 部署目标为 macOS 15 以上；从源代码构建时，macOS 也须符合所用 Xcode 的要求。当前设置流程不支持 Windows／Linux。 |
| 手机 | 需要 iPhone，当前 iOS 部署目标为 26 以上。较早 prototype 使用 iPhone 15／iOS 27 研究，不代表所有机型及系统版本均已验证。 |
| 连接线 | 首次安装需要可传输数据的 USB 线。Wi-Fi 设备管理是后续 GoFly 开发要求。 |
| 开发工具 | Xcode、所需 iOS SDK 与 Swift 工具链；Mac 软件包需要 Swift 6.2 以上。现有 prototype 构建记录使用 Xcode 27。 |
| Apple 账号 | 开发签名使用自己的 Apple 账号，在 Xcode 登录。较早 LocalGo 设置工具支持免费 Personal Team。 |
| 手机设置 | 解锁 iPhone、信任 Mac，并启用开发安装所需的[开发者模式](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。 |
| 连接 App | 现行设备通道方案需要另行在 iPhone 安装 [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044)。 |
| 网络 | Apple 签名、依赖下载、地图／搜索及必要设备准备下载均需要网络。 |

GoFly 以免费使用为目标，Apple 签名限制仍适用：免费 Personal Team 描述文件通常七天到期，之后需要重新构建／安装。请以本次可验证的实际有效期为准，详见 [Apple 账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account)。免费使用不代表永久免续签。

## 下载与安装

**以下为预定发布流程，当前 Mac 预览版无法执行。** 此仓库尚无已验证的公开下载网址；发布前请使用下方开发版方式。

1. 从项目正式发布页下载 GoFly `.dmg`，核对版本、支持的 Mac 架构、macOS 要求及公布的校验码。
2. 打开 DMG，将 `GoFly.app` 拖入“应用程序”，再启动 GoFly。按界面完成环境检查及签名账号设置。
3. 通过 USB 连接 iPhone，解锁并在手机完成信任、开发者模式确认；在 GoFly 选择并核对目标设备。
4. 开始首次安装。Mac 负责签名与安装手机 App、私密交付配对，以及自动准备并验证实际需要的设备支持项目；已就绪的复用。进度统一显示“准备设备”，不另设手机支持数据下载或设置页。
5. 等待“安装完成”。必须同时验证 App 部署、配对导入及必要设备准备，不能仅凭下载完成或手机出现图标判定成功。完成后可拔除 USB。
6. 在 iPhone 安装／打开 LocalDevVPN、启用 VPN 通道，再打开 GoFly。首次引导须通过实际 VPN 通道检查才能继续；启动服务只准备，不会移动位置，另行执行定位操作才开始模拟。

预定设备管理会在选择设备并成功核对连接后，通过 USB 或 Wi-Fi 自动重新签名 GoFly；手动重新签名入口仍保留，且须保留 App 数据。以上仍待实现及真机验证，详见 [Mac 开发规范](app/GoFlyMac/DEVELOPMENT.md)。

## 体验当前开发版

在已配置 Xcode 的 Mac，从仓库根目录执行：

```sh
bash app/GoFlyMac/build-app.sh
open work/gofly-mac/GoFly.app
```

这会生成本机开发 App，并非可移植 DMG。生成配置含本机工作目录与 Python 路径，未做发布签名或 notarization。只读设备检查使用现有 `work/mac-setup-env/bin/python` 环境；没有该环境仍可查看界面预览，App 不会自动安装依赖。

现有 Mac GUI 尚不能签名、安装、重新配对、重新签名、备份或重装 iPhone App。预览成功使用示例数据，不代表设备已执行操作。

若要另外进行 **LocalGo prototype** 实验，请阅读 [Mac 设置 CLI 说明](app/LocalGo/MacSetup/README.md)。该工具在明确执行时会真正通过 USB 签名／安装，目标为 `com.neven.localgo`，不是新版 GoFly 的 `com.neven.gofly`。Prototype 仍在手机准备／下载设备支持数据，尚未符合 GoFly 预定的安装完成条件。

## 研究操作

GoFly 设计涵盖地点选择、路线／GPX、摇杆移动、设备服务准备及恢复 GPS。功能要求与实现状态见[产品规范](app/LocalGo/PRODUCT-SPEC.md)。

实验时记录 App 版本、iPhone 机型、iOS 版本、连接方式及实际结果。先在 Apple 地图与另一个 App 核对模拟位置，再停止任务、恢复 GPS，并另外核对真实位置。安装或配对成功不能代替 GPS 恢复验证；后台运行、断线重连、系统更新及重启均需分别验证。

研究是本项目的主要用途，不是 0BSD 的非商用限制。项目不接入 AnyGo／iToolab 服务，也不分发其代码、素材、凭证或密钥。

## 交给 AI 协助安装

先提供 [AI 安装操作说明](docs/AI-INSTALL.md#简体中文)，再粘贴：

```text
请先阅读 README.zh-Hans.md 与 docs/AI-INSTALL.md，协助我在 Mac 和自己的
iPhone 设置 GoFly。先确认实际发布版本、当前能力与目标设备，再根据我的授权
执行可用的设置流程。如果只有预览版，请明确说明限制；只有在我明确选择
LocalGo prototype 实验时才使用旧工具。Apple 登录、双重认证、信任、开发者
模式与 VPN 确认由我操作。保留现有 App 数据，逐步核对实际结果，最后报告
已完成项目、待我操作的步骤及阻碍。
```

## 常见问题

| 情况 | 处理方式 |
| --- | --- |
| 找不到 DMG | DMG 尚待发布；可从源代码打开预览，不以第三方安装包替代。 |
| 找不到 iPhone | 检查 USB 数据线、解锁／信任状态、Xcode 设备支持及选择的手机。 |
| 安装／重新签名按钮禁用 | 现有只读 Mac 版本的正常限制，可用预览讨论流程。 |
| 手机 App 无法打开 | 核对实际签名到期时间，回适用的 Mac 签名流程处理；开发者模式不会延长签名。 |
| LocalDevVPN 已连接，GoFly 仍无法继续 | 核对实际 VPN 通道。设计提供连接检查，停止发送位置后可重置通道；Connected 外观不能代替实测。 |
| 写入途中中断 | 先核对同一设备与本次事务，再决定是否重试；结果不明须如实报告并保留数据。 |

## 文档与源代码

| 路径 | 用途 |
| --- | --- |
| [app/GoFly/README.md](app/GoFly/README.md) | 开发中的新版原生 iOS App，含英文、繁中、简中资源。 |
| [app/GoFlyMac/README.md](app/GoFlyMac/README.md) | 现有 Mac 能力及开发检查。 |
| [app/GoFlyMac/DEVELOPMENT.md](app/GoFlyMac/DEVELOPMENT.md) | 已确认的 Mac 安装及设备管理要求。 |
| [app/LocalGo/README.md](app/LocalGo/README.md) | 较早 iOS prototype、设计历史与研究背景。 |
| [docs/AI-INSTALL.md](docs/AI-INSTALL.md) | 三语 AI 代理安装操作说明。 |
| [docs/LICENSING.md](docs/LICENSING.md) | 0BSD 范围、现有上游许可与发布条件。 |
| `work/` | 不纳入版本控制的本机研究证据、构建产物及设备实验，不是公开发布内容。 |

README 提供英文、繁体中文、简体中文。App 本地化同样以三语及英文 fallback 为要求；文档翻译不代表 UI 本地化或真机验证已全部完成。

## 许可

新编写、独立持有权利的内容选用 **0BSD**，允许免费使用、修改、再分发，无须署名。本次文档变更由 [LICENSE](LICENSE) 授权三份根目录 README 及 `docs/` 的两份新指南，不更改现有 App 代码或依赖许可。可查阅 [0BSD 官方条款](https://opensource.org/license/0bsd)。

LocalGo／StikDebug、复用的 Mac 设备边界及新版 GoFly 的[衍生／原生组件](app/GoFly/Legal/SOURCES.txt)保留 AGPL-3.0 声明。Mac prototype 使用 GPL-3.0 的 `pymobiledevice3`，附带 Noto Sans TC 字体维持 OFL-1.1。整合发布的 App 不能宣称全部免署名，详见[许可说明](docs/LICENSING.md)及[上游来源](app/LocalGo/UPSTREAM.md)。

文档结构参考 [Best-README-Template](https://github.com/othneildrew/Best-README-Template) 的项目介绍、必要条件、安装、使用与许可章节，按研究项目重新编写。
