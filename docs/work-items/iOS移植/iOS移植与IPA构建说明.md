# iOS 移植与 IPA 构建说明

## 实现范围

本分支主要适配 iPhone 17 Pro Max。iOS 使用 Swift `Wenku8Bridge` 对接现有 Flutter `legacy_api` 通道，不加载、修改或逆向 Android 的 `libcpp.so`。Android 保留原实现。

服务端仍接受公开的旧版 POST 格式：`appver=1.13`、UTF-8 action 的 Base64 `request`、毫秒时间戳 `timetoken`。地址沿用 `https://wenku8-relay.mewx.org/`，客户端标识为 `Wenku8-Flutter/0.2.3`。已通过实际只读请求验证书目、分页、元数据、简介、目录、正文、封面、出版分类和中文搜索。第三方服务的协议和可用性取决于服务方。

账号 Cookie 只保存在原生层和设备绑定 Keychain，不进入 Dart、备份或日志。账号操作串行处理；公开浏览与图片请求不携带账号 Cookie。未使用真实账号验证登录、云书架写入和发帖。

插图仅允许既有文库域名与已使用的图片 CDN，重定向逐跳校验并升级历史 HTTP 地址；限制单次响应 8 MiB、图片 5000 万像素、磁盘图片缓存 256 MiB。书评使用 iOS 系统 libiconv 保持既有 GBK 契约，拒绝无法编码的字符；iOS 的 Foundation 未提供本项目原先选用的 GBK 转换器，不能直接沿用 macOS 的 NSString 编码方式。

iOS 支持系统文件备份导入导出、分享、阅读保持亮屏和后台音频。备份限定 UTF-8、4 MiB；Android 旧版目录导入仍仅在 Android 提供。iOS 启动时启用真实联网书库、离线缓存、账号和现有在线听书。

## iPhone 17 Pro Max

布局测试使用 440 × 956 逻辑点及对应横屏尺寸；模拟安全区覆盖顶部灵动岛与底部 Home 指示条。依据 [Apple 技术规格](https://support.apple.com/zh-cn/125091) 的 1320 × 2868 像素分辨率。保留 `CADisableMinimumFrameDurationOnPhone`，允许 ProMotion，具体刷新率由系统和负载决定。

模拟安全区不等于真机测量。真实设备上的文件提供器、音频中断、后台播放、长时间阅读和电量表现仍需安装后验证。

## 开发环境

- Flutter 3.41.5 / Dart 3.11.3，与上游版本一致。
- Windows SDK：`C:\Users\Administrator\develop\flutter`，已加入当前用户 PATH。
- SDK 下载镜像：`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`。项目依赖继续使用锁文件中的官方 `pub.dev`；切换包镜像会改变依赖来源并导致严格锁文件校验失败。
- iOS 编译在 GitHub Actions macOS 15、Xcode 26.3 中执行；Windows 无法直接运行 Xcode。

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
python scripts/probe_wenku_api.py
```

原生 `RunnerTests` 检查请求格式、GBK 编码、图片限制、重定向、会话清除及真实公开联网链路；工作流在 iPhone 17 Pro Max 模拟器中运行。

## IPA 构建

在本 Fork 的 Actions 中手动运行 `iOS IPA`，对应 `.github/workflows/ios-ipa.yml`。工作流执行锁定依赖安装、静态检查、Flutter 测试、公开接口探测、arm64 release 构建与打包，并继续执行模拟器原生测试和真实 Dart 通道测试。IPA 上传成功不代表后续模拟器测试已经通过，应以完整工作流结果为准。

应用按 `Payload/Runner.app` 打包，保留框架符号链接，并检查 arm64、Flutter/App 框架、ZIP 完整性及 SHA-256。产物为 `Wenku8-0.2.3-ios-arm64-unsigned.ipa` 和 `SHA256SUMS.txt`，保留 30 天。

这是未签名 IPA，需要由 SideStore、AltStore 或 Sideloadly 使用自己的 Apple 账号重新签名后安装。无需把 Apple 密码、验证码或证书发到聊天中。生成 IPA 不代表已通过真实 iPhone 安装验收。

## 书评 GBK 字符契约与来源

书评与原 Android `Charset.forName("GBK")` / `URLEncoder` 保持一致：Android ICU 将 `GBK` 别名映射到 `windows-936-2000`，不能直接以桌面 OpenJDK 的同名映射为依据。例如 Android 接受 `U+2295 → A892`、`U+E7C8 → A8BF`，拒绝 `U+2641`；桌面 OpenJDK 的 `GBK.map` 对 `A892` 则定义为 `U+2641`。欧元符号在 Android 为单字节 `80`。

iOS 实测缺少 Foundation GBK 转换器，因此普通字符采用系统 `libiconv` 严格转换。Apple 的 GBK 私用区和少量 Unicode 映射与 Android 不同，编码层按 Android 官方数据补全全部 2150 个私用字符：`E000–E864` 及 `F8F5`，其中主要用户区使用行列公式，末 255 个字符压缩为 27 段；同时保持欧元、横线、全角英镑符号的 Android 字节，并拒绝 Apple 新分配但 Android GBK 不支持的 80 个字符。没有引入完整字符表或新第三方库。测试以官方原始映射独立计算的 SHA-256 校验全部私用字符输出，另覆盖不可表示字符、空串、嵌入 NUL 和长度边界。

来源与数据许可：

- [Android ICU GBK 别名](https://android.googlesource.com/platform/external/icu/+/refs/heads/main/icu4c/source/data/mappings/convrtrs.txt)
- [Android ICU windows-936-2000 官方映射](https://android.googlesource.com/platform/external/icu/+/refs/heads/main/icu4c/source/data/mappings/windows-936-2000.ucm)，映射数据来自 Unicode ICU，遵循 [Unicode 数据与软件许可](https://www.unicode.org/license.txt)。本次只使用映射事实及压缩数字范围。
- [Apple libiconv GBK 定义](https://github.com/apple-oss-distributions/libiconv/blob/main/esdb/GB/GBK.src)及 [Apple GB2312 扩展映射](https://github.com/apple-oss-distributions/libiconv/blob/main/csmapper/GB/UCS%25GB2312EXT.src)，用于核对系统转换器行为，没有复制其实现代码。
- [桌面 OpenJDK GBK 对照表](https://github.com/openjdk/jdk/blob/master/make/data/charsetmapping/GBK.map)，仅用于说明平台差异，未作为 Android 契约。
