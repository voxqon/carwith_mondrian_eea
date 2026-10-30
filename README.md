<img src="webroot/assets/carwith.png" alt="CarWith" width="64" height="64">

# CarWith for mondrian EEA

适用于 mondrian 欧版 HyperOS 的 CarWith 模块，支持 Magisk / APatch，提供中文 WebUI 部署管理。

## 兼容范围

| 项目 | 要求 |
| --- | --- |
| 设备 | `mondrian` / `mondrian_eea_global` |
| 系统 | `OS3.0.2.0.VMNEUXM`，Android 15 / SDK 35，ARM64 |
| Root | Magisk 26.4+ 或 APatch |
| APatch 内核 | 支持 EROFS、OverlayFS 和 loop 设备 |

安装和启动时会校验目标系统及核心框架。不支持其他系统版本；OTA 前请先取消部署并重启。

## 包含组件

| 组件 | 版本 |
| --- | --- |
| CarWith | `3.7.3-20251021` / `com.miui.carlink` |
| 小米定制 CarLife | `8.8.4` / `com.baidu.carlife.xiaomi`，含 49 个原始 ARM64 目录文件 |
| 车联服务 | `miui.car.server.jar` |

两个 APK、原生文件和 JAR 均保留原始内容及签名。部署后重启，由系统识别应用并加载服务。

## 安装与管理

1. 在 Magisk 或 APatch 中安装发布的模块 ZIP，然后重启。
2. 打开管理页面：APatch 使用模块 WebUI；Magisk 使用 [WebUI X: Portable](https://github.com/MMRLApp/WebUI-X-Portable/releases)，允许 Root 和 Shell 权限。
3. 开启“部署组件”并确认，再次重启。
4. 返回页面检查 CarWith、CarLife 和车联服务状态；通过“连接设置”打开 CarWith。

初装和升级均默认关闭部署。APatch 使用模块自带挂载方式，无需启用 Magisk Mount 或其他 MetaModule。

安装包采用无损整体压缩，安装时自动还原完整组件和只读镜像。安装后的文件内容、挂载方式和空间占用保持不变。

## 取消与卸载

- **取消部署：** 关闭页面中的部署开关，确认后重启。
- **卸载：** 在 Root 管理器中卸载模块，然后重启。

已有用户安装版本可能影响系统识别，可在“诊断详情”查看实际包路径。模块不会自动清理应用数据。

## 验证范围

当前版本通过主机端部署、校验、回滚和页面测试，尚未完成新增 CarLife 组件的实机与车机连接验证。“基础服务就绪”表示组件和服务检测通过，投屏、音频、通话等功能仍需实车测试。

## 源码与来源

GitHub 源码包的 `payloads/` 已包含 CarWith、CarLife 两个原始 APK 和服务 JAR，构建方法见 [tools/README_carwith.md](tools/README_carwith.md)。原生库和组件镜像由构建脚本生成。

第三方来源与许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和 [licenses/](licenses/)。
