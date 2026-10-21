# lw.Web2Harmony v0.1.0 Preview

将本地 HTML/Vue/React 静态构建目录或在线 URL 生成为标准鸿蒙 ArkTS + ArkWeb 工程，并通过官方工具链构建 HAP。

- 原生 Windows GUI 与 CLI，支持中文路径、自定义 PNG 图标、应用版本与屏幕方向。
- 拷贝复用 lw.Web2Android 的 JSON、SHA-256、UTF-8、进程执行与 spdlog 轮转日志基础。
- 本地资源使用独立 HTTPS 域名和精确资源白名单，支持 JS 模块、中文文件及 MIME 类型。
- 鸿蒙端记录页面、Console、HTTP 错误、视口、设备环境；日志本地时间、2 MiB 轮转、5 个归档并支持手动导出。
- CI 构建 Windows 工具和 local / remote HAP，检查包结构并生成合并发行 ZIP。
- 导入开发者自己的调试签名材料后，可生成指定测试设备使用的已签名 HAP。

这是首个开发预览版，尚待首次鸿蒙 SDK CI 和真机验证。文件上传、拍照、下载、视频全屏和外部文件关联尚未实现。公开包不含鸿蒙 SDK、JDK 或签名材料。
