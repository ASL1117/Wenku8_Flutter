轻小说文库 iOS 0.2.4（构建号 6），主要适配 iPhone 17 Pro Max。已收到用户安装后可用反馈。

### 修复内容

- 修复旧版固定请求校验值被服务端拒绝，导致书目、搜索、目录和正文等联网功能失败的问题。现在每次请求生成动态校验。
- iOS 发现页区分接口拒绝、超时、断网等原因，保留重试入口及本地资料提示。
- iOS 使用独立 Swift 联网实现，不依赖 Android 的 `libcpp.so`。

### 下载与安装

下载 `Wenku8-0.2.4-ios-arm64-unsigned.ipa`。这是未签名 IPA，需要使用自己的 Apple 账号重新签名后安装。

`SHA256SUMS.txt` 提供安装包的 SHA-256 校验值；GitHub 同时提供该发布标签对应的源码归档。

### 验证记录

40 项相关测试、16 项 iOS 原生测试、9 类真实只读接口检查，以及 Flutter → iOS → 真实目录和正文联调均通过；完整 Flutter/Android 回归通过。真实账号写入未纳入自动验证。

- [iOS 构建与联网验证](https://github.com/ASL1117/Wenku8_Flutter/actions/runs/39710189510)
- [完整 Flutter/Android 回归](https://github.com/ASL1117/Wenku8_Flutter/actions/runs/39710189180)
- 安装包由提交 `9c7590f38a0351e955edea3572dd64ca505bd6ba` 构建；此后的提交仅补充文档。

源码及第三方组件声明见仓库 `LICENSE`、`NOTICE` 和 `docs/THIRD_PARTY.md`。
