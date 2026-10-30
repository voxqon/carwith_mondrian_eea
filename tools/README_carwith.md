# 构建与测试

GitHub 源码包以模块文件为仓库根目录，已包含安装器、页面资源、第三方许可，
以及两个原始 APK 和服务 JAR。CarLife 原生库及 EROFS 镜像由构建脚本生成。

## 构建

需要 Python 3.10+，以及支持 Android fs-config / SELinux 的
`mkfs.erofs 1.8.10-gee46dd74`。使用 `EROFS_MKFS` 环境变量指定工具完整路径；
也可将其放入 PATH。构建器校验固定镜像哈希，其他工具构建结果不一致时会停止。

以下原始输入已随源码包附带，无需另行准备：

```text
payloads/
  CarWith_3.7.3-20251021.apk
  miui.car.server.jar
  CarLife_xiaomi_8.8.4_273.apk
```

CarWith 和 JAR 来自国行 `OS3.0.8.0.VMNCNXM`；
CarLife 使用小米定制 `com.baidu.carlife.xiaomi` 8.8.4 / versionCode 273，
来源见 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)。
构建器会拒绝哈希不一致的输入：

| 文件 | SHA-256 |
| --- | --- |
| CarWith APK | `081ac798b3a114f14e602b2cb1c5c691ff2cb47009c1a6ba4eebbb4e87caeb2f` |
| 服务 JAR | `292e38490c907831a0cfde59db383418da34b32d0d102a52ca6ce98e190285f3` |
| CarLife APK | `00df4aaacbbc5837f3a0ef17fc55dfabf038596dd27b652cfb23c9722770a994` |

```sh
python tools/build_carwith_module.py
```

输出位于 `dist/`：完整模块 ZIP、包含原始组件的源码 ZIP、SHA-256 校验文件及构建校验结果。
构建不会下载文件或操作手机。只重新打包源码及原始组件时，无需 EROFS 工具：

```sh
python tools/build_carwith_module.py --source-only
```

安装包只保存一份 XZ 压缩的原始 EROFS 镜像，使用 BusyBox 支持的
64 MiB 字典。构建器定位并逐字节验证 52 个原始组件的块数据和尾部，
生成 `payload.map`。安装时用 XZ 还原镜像，再用 `dd` 按表还原 APK、
JAR 和原生库，核对原始哈希后移除安装资料；过程不执行额外挂载。
后续构建会校验并复用相同的压缩镜像。

## 测试

Shell 测试需要 Bash、Python，以及目标欧版 ROM 中以下四个原始框架文件。
`REAL_CORE` 指向包含该目录结构的文件夹：

```text
system/system_a/system/framework/framework.jar
system/system_a/system/framework/services.jar
system_ext/system_ext_a/framework/miui-framework.jar
system_ext/system_ext_a/framework/miui-services.jar
```

构建完成后，在 Git Bash / Linux 下执行，每次使用新的测试目录：

```sh
REAL_CORE=/path/to/eea/fs PYTHON_EXE=python bash tools/test_carwith_module.sh "$PWD" "$PWD/dist/test-module"
bash tools/test_carwith_backend.sh "$PWD" "$PWD/dist/test-backend"
sh tools/test_carwith_install.sh /absolute/path/to/module.zip "$PWD/dist/test-install"
STATUS_FIXTURE="$PWD/dist/test-module/running-status.json" node tools/test_carwith_webui.cjs
```

页面测试另需 Node.js 18+、Playwright 和对应 Chromium；
可用 `PLAYWRIGHT_PATH` 指定 Playwright 包路径。
测试使用文件夹及 Android 服务模拟，不执行真实系统挂载。
页面截图和结果保存至 `dist/webui-tests/`。主机测试不代表手机或车机实测。
安装测试需要 XZ 支持，覆盖两个管理器的部署初始化、损坏压缩包、
解压失败及还原文件损坏；也可直接使用管理器附带的 BusyBox ash 执行。

GitHub 仓库使用源码包内容；完整安装 ZIP 作为 Release 附件。
