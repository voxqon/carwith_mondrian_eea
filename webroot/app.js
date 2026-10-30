"use strict";

(() => {
  const BASE = "/data/adb/modules/carwith_mondrian_eea/control.sh";
  const commands = new Set(["status", "deploy", "undeploy", "open", "reboot"]);
  const $ = (id) => document.getElementById(id);
  const errors = {
    ROOT_REQUIRED: "未获得 Root 权限",
    DEVICE_MISMATCH: "设备不是 mondrian",
    REGION_MISMATCH: "系统不是 mondrian 欧版",
    SDK_MISMATCH: "Android SDK 不是 35",
    ABI_MISMATCH: "设备架构不匹配",
    ROM_MISMATCH: "系统版本不是 OS3.0.2.0.VMNEUXM",
    FRAMEWORK_MISMATCH: "framework.jar 与目标系统不一致",
    SERVICES_MISMATCH: "services.jar 与目标系统不一致",
    MIUI_FRAMEWORK_MISMATCH: "miui-framework.jar 与目标系统不一致",
    MIUI_SERVICES_MISMATCH: "miui-services.jar 与目标系统不一致",
    APK_CORRUPT: "模块内的 CarWith APK 校验失败",
    JAR_CORRUPT: "模块内的服务 JAR 校验失败",
    CARLIFE_CORRUPT: "模块内的 CarLife 组件校验失败",
    CARLIFE_LIBS_CORRUPT: "模块内的 CarLife 原生库校验失败",
    GUARD_MISSING: "提前启动校验脚本缺失或被修改，请重装模块",
    MODULE_DISABLED: "模块已在 Root 管理器中停用",
    MODULE_REMOVING: "模块已安排卸载",
    UPDATE_PENDING: "模块安装或更新待重启",
    WRITE_FAILED: "无法保存部署选择",
    BOOT_INCOMPLETE: "系统尚未完成启动",
    MOUNT_BACKEND_MISSING: "挂载配置缺失或无效，请重装模块",
    OVERLAY_UNSUPPORTED: "内核没有提供所需的 OverlayFS 或 EROFS 支持",
    LAYER_CORRUPT: "只读组件镜像校验失败，请重装模块",
    OVERLAY_HOOK_MISSING: "启动挂载脚本缺失或不可执行，请重装模块",
    OVERLAY_MOUNT_FAILED: "启动挂载失败，已撤销部署，请查看 state/mount.log",
    TARGET_ALREADY_PRESENT: "目标位置已存在组件，请先处理其他模块或系统内置版本",
    BOOT_STAGE_REQUIRED: "挂载只能在系统启动阶段执行",
  };
  let current = null;
  let busy = false;
  let sequence = 0;
  let feedbackTimer;
  let stale = false;
  const hostAvailable = () => !!(window.ksu && typeof window.ksu.exec === "function");
  const explain = (code) => errors[code] || code || "未知错误";

  function execute(action) {
    if (!commands.has(action)) return Promise.reject(new Error("无效操作"));
    if (!hostAvailable()) return Promise.reject(new Error("当前页面未连接 Root 管理环境"));
    return new Promise((resolve, reject) => {
      const name = `carwithCallback${++sequence}`;
      const timer = setTimeout(() => {
        // A timed out write may still finish. Keep its outcome explicitly unknown.
        delete window[name];
        reject(new Error("设备响应超时，请刷新核对状态"));
      }, 45000);
      window[name] = (code, stdout, stderr) => {
        clearTimeout(timer);
        delete window[name];
        if (Number(code) !== 0) {
          reject(new Error(explain(String(stderr || stdout || `操作失败 (${code})`).trim())));
        } else resolve(String(stdout || "").trim());
      };
      try {
        window.ksu.exec(`sh ${BASE} ${action}`, "{}", name);
      } catch (error) {
        clearTimeout(timer);
        delete window[name];
        reject(error);
      }
    });
  }

  function text(id, value, tone) {
    $(id).textContent = value;
    if (tone) $(id).dataset.tone = tone;
    else delete $(id).dataset.tone;
  }

  function feedback(message) {
    clearTimeout(feedbackTimer);
    text("feedback", message);
    $("feedback").hidden = false;
    feedbackTimer = setTimeout(() => { $("feedback").hidden = true; }, 6500);
  }

  function controls() {
    const connected = hostAvailable() && !!current && !stale;
    const canDeploy = connected && current.enabled === "yes" &&
      current.update_pending === "no" && current.compatibility === "OK" &&
      current.payload === "OK" && current.guard === "OK" && current.backend_check === "OK";
    $("refresh").disabled = busy;
    $("deployment-toggle").disabled = busy || !connected || (current.desired === "off" && !canDeploy);
    $("deployment-toggle").setAttribute("aria-checked", String(!!current && current.desired === "on"));
    document.querySelector("main").setAttribute("aria-busy", String(busy));
    $("open").disabled = busy || !connected || current.package !== "installed";
    $("reboot").disabled = busy || !connected;
  }

  function render(s) {
    current = s;
    let title, message, tone = "warn";
    if (s.compatibility !== "OK") {
      title = "系统不匹配";
      message = explain(s.compatibility) + "。部署已被阻止。";
      tone = "error";
    } else if (s.update_pending === "yes") {
      title = "安装待重启";
      message = "重启完成模块安装后，再选择是否部署。";
    } else if (s.enabled !== "yes") {
      title = s.enabled === "disabled" ? "模块已停用" : "模块待卸载";
      message = "部署开关受 Root 管理器中的模块状态控制。";
    } else if (s.payload !== "OK" || s.guard !== "OK") {
      title = "部署检查未通过";
      message = explain(s.payload !== "OK" ? s.payload : s.guard);
      tone = "error";
    } else if (s.mount_conflict === "yes") {
      title = "挂载配置与实际状态冲突";
      message = explain(s.backend_check) + "，但系统路径仍能读取组件。当前文件状态不能证明停用已生效，请重启后核对。";
      tone = "error";
    } else if (s.backend_check !== "OK") {
      title = "挂载后端不可用";
      message = explain(s.backend_check) + "。部署已被阻止，取消部署仍可使用。";
      tone = "error";
    } else if (s.reboot_required === "yes") {
      title = s.desired === "on" ? "等待重启部署" : "等待重启撤销";
      message = s.desired === "on"
        ? "CarWith、CarLife 与车联服务将在重启后加载。"
        : "已选择取消部署，本次启动中已加载的应用和服务仍可能运行。";
    } else if (s.desired === "off") {
      title = "未部署";
      message = "CarWith、CarLife 与车联服务的部署已关闭。";
      tone = "neutral";
      if (s.apk !== "missing" || s.jar !== "missing" || s.carlife_apk !== "missing" ||
          s.carlife_native !== "missing" || s.binder === "found") {
        title = "已取消模块部署";
        message = "仍检测到组件或服务，请检查其他模块、系统内置文件或现有安装。";
        tone = "warn";
      }
    } else if (s.apk === "match" && s.jar === "match" && s.binder === "found" &&
               s.package === "installed" && s.system_app === "yes" &&
               s.carlife_apk === "match" && s.carlife_package === "installed" &&
               s.carlife_system_app === "yes" && s.carlife_native === "match" &&
               s.carlife_compatible === "yes" &&
               (s.mount_backend !== "apatch_overlay" || s.overlay_state === "active")) {
      title = "基础服务就绪";
      message = "CarWith、CarLife 已安装，车联服务已注册。";
      tone = "good";
    } else {
      title = "部署尚未就绪";
      message = "实际组件或服务检测未通过，请核对挂载后端和检测详情。";
      tone = "error";
    }
    text("status-title", title);
    text("status-message", message);
    text("status-caption", "当前状态");
    $("status-dot").dataset.tone = tone;
    const notices = [];
    if (s.guard_reason) notices.push("启动校验已撤销部署：" + explain(s.guard_reason) + "。");
    if (s.selinux && s.selinux !== "Enforcing")
      notices.push("SELinux 当前为 " + s.selinux + "，此状态不能证明 Enforcing 下可用。");
    text("notice", notices.join(" "));
    $("notice").hidden = notices.length === 0;
    text("desired-label", s.desired === "on" ? "已开启" : "已关闭");
    $("reboot-row").hidden = s.reboot_required !== "yes";
    const fileLabels = { match: "文件匹配", different: "文件不匹配", missing: "未检测到" };
    let apkLabel = fileLabels[s.apk] || "无法确认";
    if (s.apk === "match" && s.system_app === "yes") apkLabel = "系统应用已识别";
    else if (s.package === "installed" && s.system_app === "no") apkLabel = "仅用户应用";
    text("apk-state", apkLabel, s.apk === "match" && s.system_app === "yes" ? "good" : "warn");
    text("jar-state", fileLabels[s.jar] || "无法确认", s.jar === "match" ? "good" : "warn");
    const carlifeReady = s.carlife_apk === "match" && s.carlife_package === "installed" &&
      s.carlife_system_app === "yes" && s.carlife_native === "match" && s.carlife_compatible === "yes";
    const carlifeLabel = carlifeReady ? "已安装"
      : s.carlife_apk !== "match" ? fileLabels[s.carlife_apk]
      : s.carlife_native !== "match" ? "原生库未就绪"
      : s.carlife_package !== "installed" ? "待系统识别"
      : s.carlife_system_app !== "yes" ? "仅用户应用"
      : s.carlife_compatible === "no" ? "版本过低" : "版本待确认";
    text("carlife-state", carlifeLabel || "无法确认", carlifeReady ? "good" : "warn");
    text("carlife-version", s.carlife_version ? `${s.carlife_version} · 小米定制版` : "8.8.4 · 小米定制版");
    text("carlife-native-detail", fileLabels[s.carlife_native] || "无法确认");
    const serviceReady = s.jar === "match" && s.binder === "found";
    text("binder-state", serviceReady ? "已注册" : s.jar !== "match" ? "JAR 未就绪" : ({ missing: "未注册", unknown: "无法确认" })[s.binder] || "无法确认", serviceReady ? "good" : "warn");
    text("manager-state", s.manager);
    text("rom-state", s.compatibility === "OK" ? "目标系统匹配" : "不匹配", s.compatibility === "OK" ? "good" : "error");
    text("payload-state", s.payload === "OK" ? "原始文件校验通过" : "校验失败", s.payload === "OK" ? "good" : "error");
    text("selinux-state", s.selinux || "无法确认");
    text("device-detail", `${s.device} / SDK ${s.sdk}`);
    text("rom-detail", s.rom);
    text("module-detail", ({ yes: "启用", disabled: "停用", removing: "待卸载" })[s.enabled] || s.enabled);
    text("backend-detail", ({ magisk: "Magisk",
      apatch_overlay: "模块自带只读 OverlayFS（" + ({ active: "已挂载", partial: "部分挂载", missing: "未挂载", unknown: "无法确认" })[s.overlay_state] + "）",
      overlay_unsupported: "内核不支持只读挂载",
      unconfirmed: "尚未确认" })[s.mount_backend] || s.mount_backend);
    text("guard-detail", s.guard === "OK" ? "提前校验脚本完整" : explain(s.guard));
    text("path-detail", s.package_paths || "未发现 com.miui.carlink");
    text("carlife-path-detail", s.carlife_package_paths || "未发现 com.baidu.carlife.xiaomi");
    text("module-version", `v${s.module_version}`);
    text("checked-at", new Date().toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false }));
    controls();
  }

  function disconnected(message) {
    stale = true;
    text("status-title", "无法读取设备状态");
    text("status-caption", "检测失败");
    text("status-message", message);
    $("status-dot").dataset.tone = "error";
    text("checked-at", "状态已失效");
    controls();
  }

  async function readStatus() {
    const status = JSON.parse(await execute("status"));
    const enums = {
      desired: ["on", "off"], boot_choice: ["on", "off", "unknown"],
      enabled: ["yes", "disabled", "removing"], reboot_required: ["yes", "no"],
      update_pending: ["yes", "no"], apk: ["match", "different", "missing"],
      jar: ["match", "different", "missing"], package: ["installed", "missing", "unknown"],
      carlife_apk: ["match", "different", "missing"], carlife_package: ["installed", "missing", "unknown"],
      carlife_system_app: ["yes", "no", "unknown"],
      carlife_native: ["match", "different", "missing"], carlife_compatible: ["yes", "no", "unknown"],
      binder: ["found", "missing", "unknown"], system_app: ["yes", "no", "unknown"],
      mount_conflict: ["yes", "no"], overlay_state: ["active", "partial", "missing", "unknown", "not_used"],
    };
    if (status.schema !== "1" || ["module_version", "compatibility", "payload", "guard", "manager", "backend_check"].some((key) => typeof status[key] !== "string") ||
        Object.entries(enums).some(([key, values]) => !values.includes(status[key]))) {
      throw new Error("设备返回了无效状态");
    }
    stale = false;
    render(status);
  }

  async function refresh() {
    if (busy) return;
    busy = true;
    controls();
    try { await readStatus(); }
    catch (error) { disconnected(error.message); }
    finally { busy = false; controls(); }
  }

  function confirm(title, message, label) {
    return new Promise((resolve) => {
      text("confirm-title", title);
      text("confirm-message", message);
      text("confirm-accept", label);
      $("confirm").returnValue = "";
      $("confirm").addEventListener("close", () => resolve($("confirm").returnValue === "accept"), { once: true });
      $("confirm").showModal();
    });
  }

  async function change(action) {
    if (busy || !current || stale) return;
    const accepted = await confirm(
      action === "deploy" ? "部署 CarWith？" : "取消 CarWith 部署？",
      action === "deploy"
        ? "将同时部署 CarWith、CarLife 组件和服务 JAR，重启后生效。"
        : "重启后停止挂载这三个组件，本次已加载的服务会保留到重启。",
      action === "deploy" ? "确认部署" : "确认取消部署"
    );
    if (!accepted) return;
    busy = true;
    controls();
    try {
      await execute(action);
      await readStatus();
      feedback(current.reboot_required === "yes" ? "选择已保存，重启后生效。" : "选择已保存。");
    } catch (error) {
      // Re-read after a rejected/timed out mutation rather than inventing success.
      try { await readStatus(); } catch { disconnected("操作结果尚未确认，请刷新状态。"); }
      feedback(error.message);
    } finally { busy = false; controls(); }
  }

  $("refresh").addEventListener("click", refresh);
  $("deployment-toggle").addEventListener("click", () => {
    if (current) change(current.desired === "on" ? "undeploy" : "deploy");
  });
  $("open").addEventListener("click", async () => {
    if (busy) return;
    busy = true; controls();
    try { await execute("open"); } catch (error) { feedback(error.message); }
    finally { busy = false; controls(); }
  });
  $("reboot").addEventListener("click", async () => {
    if (busy || !await confirm("现在重启？", "手机将立即重启，请先结束当前连接并保存其他应用中的内容。", "重启")) return;
    busy = true; controls();
    try {
      await execute("reboot");
      stale = true;
      text("status-title", "正在重启");
      text("status-message", "重启完成后重新打开管理页面检查实际状态。");
    } catch (error) { feedback(error.message); }
    finally { busy = false; controls(); }
  });
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden && !busy && hostAvailable()) refresh();
  });
  if (hostAvailable()) refresh();
  else disconnected("请从 APatch 模块 WebUI 或已授权 Root 和 Shell 的 WebUI X: Portable 打开。");
})();
