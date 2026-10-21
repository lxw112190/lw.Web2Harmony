# lw.Web2Harmony v0.1.0 Preview

将本地 HTML/Vue/React 静态构建目录或在线 URL 生成为标准鸿蒙 ArkTS + ArkWeb 工程，并通过官方工具链构建 HAP。

- 原生 Windows GUI 与 CLI，支持中文路径、自定义 PNG 图标、应用版本与屏幕方向。
- 固定 `runtime/` 基础鸿蒙工程；GUI 只保留单一 HAP 打包入口，内部自动寻找工具链、创建工作副本并交付最终产物。
- 一次导入匹配的华为证书/Profile，密码由 Windows DPAPI 加密；按 Bundle Name 自动复用。不使用 Android 本地自签冒充鸿蒙真机授权。
- 拷贝复用 lw.Web2Android 的 JSON、SHA-256、UTF-8、进程执行与 spdlog 轮转日志基础。
- 本地资源使用独立 HTTPS 域名和精确资源白名单，支持 JS 模块、中文文件及 MIME 类型。
- 鸿蒙端记录页面、Console、HTTP 错误、视口、设备环境；日志本地时间、2 MiB 轮转、5 个归档并支持手动导出。
- CI 构建 Windows 工具和 local / remote HAP，检查包结构并生成合并发行 ZIP。
- 导入开发者自己的调试签名材料后，可生成指定测试设备使用的已签名 HAP。

这是首个开发预览版，已在本地使用官方 CLT 26.0.0.851（Hvigor 6.26.8、SDK API 26）和 JDK 21 编译本地/在线两种未签名 HAP，并通过包结构及 Web 资源 SHA-256 校验。提供本地构建脚本，CI 不再是真机测试前的必经步骤。真机签名、安装及页面运行仍待验证。文件上传、拍照、下载、视频全屏和外部文件关联尚未实现。公开包不含鸿蒙 SDK、JDK 或签名材料。
