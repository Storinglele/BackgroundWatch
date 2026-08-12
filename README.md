# Background Watch

原生 macOS 菜单栏工具，用于查看并停止本机正在运行的后台服务。

点击菜单栏图标直接展开面板：上半部分是按规则识别出的服务（可停止），下半部分把其余进程分成「应用」和「开发进程」两组只读展示，按应用/可执行名去重计数——Chrome 的数十个进程会合并成一行。

**不提供启动或重启功能**，只做观察和停止。

## 环境要求

- macOS 13 或更高
- Swift 5.9+（Xcode 或 Command Line Tools 均可）

## 构建运行

```bash
swift run                       # 直接运行
./package-app.sh                # 打包成 BackgroundWatch.app
./package-app.sh --install      # 打包并安装到 /Applications
```

不加 `--install` 时 App 只留在项目目录里，「应用程序」文件夹和 Launchpad 都看不到它——那两处只索引 `/Applications` 和 `~/Applications`。

`package-app.sh` 会做 ad-hoc 签名。由于没有 Apple 开发者证书公证，从别处下载的 .app 首次打开会被 Gatekeeper 拦截，需要在「系统设置 → 隐私与安全性」里放行，或本地自行构建。

打包出的 App 设置了 `LSUIElement`，只驻留菜单栏，不显示 Dock 图标。

应用图标是用 Core Graphics 画出来的，源码在 `Tools/make-icon.swift`。改动后重新生成：

```bash
swift Tools/make-icon.swift
iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns && rm -rf AppIcon.iconset
```

菜单栏用的字形是 SF Symbol，但应用图标没有复用它——Apple 的 SF Symbols 许可禁止将符号用作 app icon 或 logo。

## 测试

```bash
swift run BackgroundWatchTests
```

用的不是 `swift test`。XCTest 随 Xcode 分发而不随 Command Line Tools 分发，在只装了 CLT 的机器上 `swift test` 会因为找不到 XCTest 模块而失败。测试套件因此做成普通可执行目标，任何能跑 Swift 的机器都能执行。

核心逻辑在独立的 `BackgroundWatchCore` module 里，通过注入的 `CommandRunning` 喂假的 `ps` / `lsof` 输出做单元测试，不依赖运行时的真实进程状态。

## 配置识别哪些服务

默认规则很通用：持有监听端口的 node / python / java / ruby / deno 进程。

要识别自己的服务，在 `~/.config/background-watch/services.json` 写规则：

```json
[
  {
    "name": "My API",
    "matches": ["my-api", "--server.port"],
    "requiresListeningPort": true
  }
]
```

- `matches` 里的每一个字符串都必须出现在进程命令行中（大小写不敏感）才算匹配
- `requiresListeningPort` 可省略，默认 `false`；为 `true` 时进程必须持有 TCP 监听端口
- 规则按顺序匹配，命中第一条即停止

文件缺失、为空或格式错误时会回退到默认规则，不会让列表变空。示例见 `examples/services.json`。

## 停止行为

点「停止」后会先发 `SIGTERM`，然后每 250ms 轮询一次进程是否真的退出，最多等 5 秒。

如果进程仍然存活（比如 shutdown hook 卡住的 JVM），面板会行内提示并给出「强制停止」按钮，确认后才发 `SIGKILL`。**不会自动升级到 SIGKILL**——对连着数据库的服务来说，未经确认的强杀可能丢数据。

所有信号发送都记录到 `~/Library/Logs/BackgroundWatch.log`。

只有被规则识别为服务的进程才能停止；「应用」和「开发进程」两组是纯只读的。

## 开机自动启动

面板底部有「开机自动启动」复选框，基于 `SMAppService`（macOS 13+），不需要额外的 helper bundle。

**默认关闭，只在你主动勾选时才注册。** 首次运行不会擅自把自己加进登录项。

只有 App 安装在 `/Applications` 时该选项才可用——从构建目录注册会留下一个指向临时路径的登录项，下次 `swift build` 清理后就失效了。若系统要求确认，面板会提示并提供跳转到「系统设置 → 通用 → 登录项」的按钮。

## 性能

一次扫描（两次 `ps` 加一次 `lsof`）约 0.38 秒，在后台线程执行，只有结果回主线程赋值。

实测：主线程上的 50ms 心跳在扫描期间保持 0.051 秒的稳定间隔，无停顿；改回主线程同步执行则会出现最大 0.23 秒的卡顿。

扫描每 3 秒一次。若某次扫描超过 3 秒，下一次会被跳过而不是堆积排队。

## License

MIT
