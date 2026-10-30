# Sources and Licenses

The repository's MIT license applies to project-authored material only. The
following components retain their own licenses and ownership:

- `META-INF/com/google/android/update-binary` is an unmodified copy of Magisk's
  `scripts/module_installer.sh`, commit
  `33bfff7ce750c27f157ddb4580e36bf842d6d95b`, GPL-3.0.
  Source: https://github.com/topjohnwu/Magisk/tree/33bfff7ce750c27f157ddb4580e36bf842d6d95b
  License: `licenses/Magisk-GPL-3.0.txt`.
- The three controls in `webroot/assets/icons.svg` use Lucide 0.468.0 SVG paths,
  ISC license. Source: https://github.com/lucide-icons/lucide/tree/0.468.0
  License: `licenses/Lucide-ISC.txt`.
- `webroot/assets/carwith.png` is rendered from the original CarWith application's
  `app_icon_carwith` Android vector resource. CarWith's original APK, service JAR
  and icon remain the property of their respective rights holders.
- Xiaomi CarLife 8.8.4 (`com.baidu.carlife.xiaomi`, versionCode 273) is an
  unmodified signed APK obtained from the MemeOS Updates mirror, not from either
  mondrian source ROM:
  https://memeosupdates.com/apps/com.baidu.carlife.xiaomi/273
  Its v1/v2 signatures were verified with Android apksig 8.7.3. Its signing
  certificate matches the ordinary CarLife APK downloaded through Baidu's
  official owner page: https://carlife.baidu.com/carlife/carowner
  The ordinary APK is a certificate reference only and is not distributed here.
  All 49 files under `system/product/app/CarLife/lib/arm64/` are copied verbatim
  from the bundled APK. They include a speech model named `libvad.dnn.so`;
  48 entries are ELF libraries. APK, libraries and bundled third-party materials
  remain the property of their respective rights holders. No relicensing is
  implied. The release's `payload-manifest.json` records provenance;
  `carlife-native.sha256` records the native file hashes.
