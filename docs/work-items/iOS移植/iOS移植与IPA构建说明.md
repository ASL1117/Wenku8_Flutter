# iOS 移植与 IPA 构建说明

## 实现范围

本分支主要适配 iPhone 17 Pro Max。iOS 使用 Swift `Wenku8Bridge` 对接现有 Flutter `legacy_api` 通道，不加载、修改或逆向 Android 的 `libcpp.so`。Android 保留原实现。

当前 POST 使用按分钟生成的 HMAC-SHA256 `appver`、UTF-8 action 的 Base64 `request`、毫秒时间戳 `timetoken`。签名与时间戳共用一次时钟采样，每次请求重新计算。2026-10-22 已复现旧版固定 `appver=1.13` 返回 HTTP 400，而动态签名请求返回正常数据；不再使用固定旧版本值。地址沿用 `https://wenku8-relay.mewx.org/`，客户端标识为 `Wenku8-Flutter/0.2.4`。实际只读验证覆盖书目、分页、元数据、简介、目录、正文、封面、出版分类和中文搜索。第三方服务的协议和可用性取决于服务方，设备时间需要准确。

动态签名根据 [YeXuanHs/novvera-app 的公开 GPL-3.0 实现](https://github.com/YeXuanHs/novvera-app/blob/a4b603210c91595dc5a10134b56a047e56153fb6/lib/foundation/novel_backend/wenku8_client.dart) 适配，来源已记录在 `NOTICE`，没有读取或修改 Android 二进制。该实现属于第三方兼容协议依据，不能将其描述为服务方的官方接口文档。账号与 Cookie 处理保持原有隔离。

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

应用按 `Payload/Runner.app` 打包，保留框架符号链接，并检查 arm64、Flutter/App 框架、ZIP 完整性及 SHA-256。当前修复版产物为 `Wenku8-0.2.4-ios-arm64-unsigned.ipa` 和 `SHA256SUMS.txt`，保留 30 天。

这是未签名 IPA，需要由 SideStore、AltStore 或 Sideloadly 使用自己的 Apple 账号重新签名后安装。无需把 Apple 密码、验证码或证书发到聊天中。生成 IPA 不代表已通过真实 iPhone 安装验收。

## 书评 GBK 字符契约与来源

书评与原 Android `Charset.forName("GBK")` / `URLEncoder` 保持一致：Android ICU 将 `GBK` 别名映射到 `windows-936-2000`，不能直接以桌面 OpenJDK 的同名映射为依据。例如 Android 接受 `U+2295 → A892`、`U+E7C8 → A8BF`，拒绝 `U+2641`；桌面 OpenJDK 的 `GBK.map` 对 `A892` 则定义为 `U+2641`。欧元符号在 Android 为单字节 `80`。

iOS 实测缺少 Foundation GBK 转换器，因此普通字符采用系统 `libiconv` 严格转换。Apple 的 GBK 私用区和少量 Unicode 映射与 Android 不同，编码层按 Android 官方数据补全全部 2150 个私用字符：`E000–E864` 及 `F8F5`，其中主要用户区使用行列公式，末 255 个字符压缩为 27 段；同时保持欧元、横线、全角英镑符号的 Android 字节，并拒绝 Apple 新分配但 Android GBK 不支持的 80 个字符。没有引入完整字符表或新第三方库。测试以官方原始映射独立计算的 SHA-256 校验全部私用字符输出，另覆盖不可表示字符、空串、嵌入 NUL 和长度边界。

来源与数据许可：

- [Android ICU GBK 别名](https://android.googlesource.com/platform/external/icu/+/refs/heads/main/icu4c/source/data/mappings/convrtrs.txt)
- [Android ICU windows-936-2000 官方映射](https://android.googlesource.com/platform/external/icu/+/refs/heads/main/icu4c/source/data/mappings/windows-936-2000.ucm)，映射数据来自 Unicode ICU，遵循 [Unicode 数据与软件许可](https://www.unicode.org/license.txt)。本次只使用映射事实及压缩数字范围。
- [Apple libiconv GBK 定义](https://github.com/apple-oss-distributions/libiconv/blob/main/esdb/GB/GBK.src)及 [Apple GB2312 扩展映射](https://github.com/apple-oss-distributions/libiconv/blob/main/csmapper/GB/UCS%25GB2312EXT.src)，用于核对系统转换器行为，没有复制其实现代码。
- [桌面 OpenJDK GBK 对照表](https://github.com/openjdk/jdk/blob/master/make/data/charsetmapping/GBK.map)，仅用于说明平台差异，未作为 Android 契约。

## 2026-10-16 交付与验证记录

- 构建源码：`6af6f7d`；[GitHub Actions 构建及验证记录](https://github.com/ASL1117/Wenku8_Flutter/actions/runs/38838696936)。
- Flutter 静态检查、iPhone 17 Pro Max 横竖屏及本地功能测试通过；9 类真实只读接口探测通过。
- iPhone 17 Pro Max / iOS 26.2 模拟器的 15 项原生测试全部通过，包含 GBK、Keychain、会话隔离、图片限制及真实公开接口。
- Flutter 集成测试“真实目录与章节正文可加载”通过，覆盖 Dart → MethodChannel → Swift → URLSession → 真实列表、封面、详情、目录与正文。该测试不运行完整应用界面，不能替代真机完整使用验收。
- 最终 IPA：`dist/ios/Wenku8-0.2.3-ios-arm64-unsigned.ipa`，28,764,046 字节；ZIP CRC、iPhoneOS 平台、Runner/App/Flutter 的 arm64 架构检查通过，不含 `libcpp.so`。
- SHA-256：`cdf3252cbda64db4fbfb704476d1fecbe3e34eabe6288651754260d24f6f28a2`，同时保存于 `dist/ios/SHA256SUMS.txt`。
- 未签名，需要自行重新签名安装；尚未执行真实 iPhone 安装、真实账号登录/写入、系统文件提供器和后台音频验收。

## 2026-10-22 联网修复版 0.2.4+6

- 已复现：旧版固定 `appver=1.13` 在直连与代理环境均返回 HTTP 400；补上动态校验后，相同地址、请求内容及原有客户端标识返回正常数据。
- 修复签名随请求重新生成，使用同一个毫秒时间戳派生分钟桶和 `timetoken`，并验证分钟切换边界。保持 HTTPS，不增加明文 HTTP 降级或自动重发账号写入。
- 区分原生 HTTP 状态与系统网络错误，只将固定安全提示传入界面，不输出响应正文、Cookie 或底层请求信息。iOS 发现页显示具体原因，保留重试入口及本地资料提示。
- 源码：`9c7590f`；[iOS 构建与验证记录](https://github.com/ASL1117/Wenku8_Flutter/actions/runs/39710189510)、[完整 Flutter/Android 回归](https://github.com/ASL1117/Wenku8_Flutter/actions/runs/39710189180)。静态检查、40 项针对性测试、16 项 iOS 原生测试、9 类真实只读接口及 Flutter → iOS → 真实目录/正文联调均通过。直连无代理的书目请求也已验证。
- 安装包：`dist/ios/0.2.4-network-fix/Wenku8-0.2.4-ios-arm64-unsigned.ipa`，28,769,310 字节，版本 0.2.4、构建号 6；ZIP CRC、iPhoneOS、arm64 框架与 SHA-256 检查通过。
- SHA-256：`e17a2fa9b98a9a2b4ff316d16ece9a2614fc18ff2da25895a8ec4639c9b845c7`；同目录有 `SHA256SUMS.txt`。
- 按之前的方式重新签名安装 0.2.4，再检查发现页、搜索与章节阅读。若仍失败，请记录新版的完整提示；模拟器验证不能替代手机端验收，真实账号写入仍未验证。
