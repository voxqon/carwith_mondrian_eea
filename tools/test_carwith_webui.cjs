const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const http = require("node:http");
const { chromium } = require(process.env.PLAYWRIGHT_PATH || "playwright");

const root = path.resolve(__dirname, "..");
const webroot = path.join(root, "webroot");
const evidence = process.env.WEBUI_EVIDENCE || path.join(root, "dist/webui-tests");
const version = fs.readFileSync(path.join(root, "module.prop"), "utf8").match(/^version=(.+)$/m)[1].trim();
const initial = {
  schema: "1", module_version: version, manager: "Magisk", mount_backend: "magisk",
  backend_check: "OK", mount_conflict: "no", overlay_state: "not_used",
  device: "mondrian", rom: "OS3.0.2.0.VMNEUXM", sdk: "35",
  compatibility: "OK", payload: "OK", guard: "OK", guard_reason: "",
  enabled: "yes", update_pending: "no", desired: "off", boot_choice: "off",
  reboot_required: "no", apk: "missing", jar: "missing", package: "missing",
  system_app: "unknown", package_paths: "", binder: "missing", selinux: "Enforcing",
  carlife_apk: "missing", carlife_package: "missing", carlife_system_app: "unknown",
  carlife_package_paths: "", carlife_version: "",
  carlife_native: "missing", carlife_compatible: "unknown",
};

async function main() {
  fs.mkdirSync(evidence, { recursive: true });
  const server = http.createServer((req, res) => {
    const pathname = new URL(req.url, "http://local").pathname;
    const target = path.resolve(webroot, "." + (pathname === "/" ? "/index.html" : pathname));
    if (!target.startsWith(webroot + path.sep)) { res.writeHead(403).end(); return; }
    const mime = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".png": "image/png", ".svg": "image/svg+xml" };
    try { res.writeHead(200, { "Content-Type": mime[path.extname(target)] || "application/octet-stream" }); res.end(fs.readFileSync(target)); }
    catch { res.writeHead(404).end(); }
  });
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  const url = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({ headless: true });
  const results = [];
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1 });
    const pageErrors = [];
    page.on("pageerror", error => pageErrors.push(error.message));
    await page.addInitScript((state) => {
      window.fixture = { ...state };
      window.executed = [];
      window.failNext = "";
      window.ksu = {
        exec(command, options, callback) {
          if (!/^sh \/data\/adb\/modules\/carwith_mondrian_eea\/control\.sh (status|deploy|undeploy|open|reboot)$/.test(command))
            throw new Error("Unexpected command: " + command);
          if (options !== "{}") throw new Error("Unexpected options");
          window.executed.push(command);
          const action = command.split(" ").at(-1);
          setTimeout(() => {
            if (window.failNext === action) {
              window.failNext = "";
              window[callback](1, "", "ROOT_REQUIRED");
              return;
            }
            if (action === "deploy" || action === "undeploy") {
              window.fixture.desired = action === "deploy" ? "on" : "off";
              window.fixture.reboot_required = window.fixture.desired === window.fixture.boot_choice ? "no" : "yes";
            }
            window[callback](0, action === "status" ? JSON.stringify(window.fixture) : "OK", "");
          }, 5);
        },
      };
    }, initial);
    await page.goto(url);
    await page.getByText("未部署", { exact: true }).waitFor();
    assert.equal(await page.locator("#deployment-toggle").isEnabled(), true);
    assert.equal(await page.locator("#deployment-toggle").getAttribute("aria-checked"), "false");
    assert.equal(await page.locator("#module-version").textContent(), "v" + version);
    results.push("inactive state and versioned status schema");
    await page.evaluate(() => { window.location.href = "javascript:window.nativeCallbackProbe=true;void(0)"; });
    await page.waitForFunction(() => window.nativeCallbackProbe === true);
    results.push("javascript URL callbacks allowed for APatch native bridge");

    await page.locator("#deployment-toggle").click();
    await page.getByRole("button", { name: "取消", exact: true }).click();
    assert.equal(await page.evaluate(() => window.fixture.desired), "off");
    await page.locator("#deployment-toggle").click();
    assert.match(await page.locator("#confirm-message").textContent(), /CarWith、CarLife/);
    await page.locator("#confirm-accept").click();
    await page.getByText("等待重启部署", { exact: true }).waitFor();
    assert.equal(await page.locator("#reboot-row").isVisible(), true);
    assert.equal(await page.locator("#deployment-toggle").getAttribute("aria-checked"), "true");
    results.push("cancel confirmation and successful deployment");
    await page.screenshot({ path: path.join(evidence, "webui-mobile-pending.png"), fullPage: true });

    async function update(patch, title) {
      await page.evaluate(patch => Object.assign(window.fixture, patch), patch);
      await page.locator("#refresh").click();
      await page.getByText(title, { exact: true }).waitFor();
      await page.waitForFunction(() => !document.querySelector("#refresh").disabled);
    }
    await update({
      desired: "on", boot_choice: "on", reboot_required: "no", apk: "match", jar: "match",
      binder: "found", package: "installed", system_app: "yes",
      package_paths: "package:/product/app/CarWith/CarWith.apk",
      carlife_apk: "match", carlife_package: "installed", carlife_system_app: "yes",
      carlife_package_paths: "package:/product/app/CarLife/CarLife.apk",
      carlife_native: "match", carlife_compatible: "yes", carlife_version: "8.8.4",
    }, "基础服务就绪");
    await page.locator("#open").click();
    await page.waitForFunction(() => window.executed.some(command => command.endsWith(" open")));
    await page.waitForFunction(() => !document.querySelector("#refresh").disabled);
    results.push("registered service and CarWith settings command");
    assert.equal(await page.locator(".diagnostics").getAttribute("open"), null);
    assert.equal(await page.locator("#notice").isHidden(), true);
    assert.equal(await page.locator("#carlife-state").textContent(), "已安装");
    assert.equal(await page.locator("footer").evaluate(el => el.getBoundingClientRect().bottom <= innerHeight), true);
    results.push("compact default view fits one mobile screen with diagnostics folded");
    await page.locator("#feedback").evaluate(el => { el.hidden = true; });
    await page.screenshot({ path: path.join(evidence, "webui-mobile-ready.png"), fullPage: true });
    await page.locator("#deployment-toggle").click();
    await page.locator("#confirm-accept").click();
    await page.getByText("等待重启撤销", { exact: true }).waitFor();
    assert.equal(await page.locator("#binder-state").textContent(), "已注册");
    results.push("undeploy keeps live service visible");
    await page.locator("#reboot").click();
    await page.getByRole("button", { name: "取消", exact: true }).click();
    assert.equal(await page.evaluate(() => window.executed.some(command => command.endsWith(" reboot"))), false);
    results.push("reboot cancellation");
    await update({ ...initial, manager: "APatch", mount_backend: "unconfirmed", backend_check: "MOUNT_BACKEND_MISSING" }, "挂载后端不可用");
    assert.equal(await page.locator("#deployment-toggle").isDisabled(), true);
    results.push("APatch mount prerequisite warning");
    await page.screenshot({ path: path.join(evidence, "webui-mobile-apatch.png"), fullPage: true });
    await update({ mount_backend: "overlay_unsupported", backend_check: "OVERLAY_UNSUPPORTED" }, "挂载后端不可用");
    assert.equal(await page.locator("#deployment-toggle").isDisabled(), true);
    assert.match(await page.locator("#status-message").textContent(), /OverlayFS.*EROFS/);
    await page.screenshot({ path: path.join(evidence, "webui-mobile-backend-blocked.png"), fullPage: true });
    await update({ desired: "on", boot_choice: "on" }, "挂载后端不可用");
    assert.equal(await page.locator("#deployment-toggle").isEnabled(), true);
    await page.locator("#deployment-toggle").click();
    await page.locator("#confirm-accept").click();
    await page.waitForFunction(() => window.fixture.desired === "off");
    await page.waitForFunction(() => !document.querySelector("#refresh").disabled);
    results.push("unsupported kernel blocks deployment while cancellation remains available");
    await update({ ...initial, manager: "APatch", mount_backend: "apatch_overlay",
      backend_check: "LAYER_CORRUPT" }, "挂载后端不可用");
    await update({ mount_conflict: "yes", apk: "match", jar: "match", desired: "on" }, "挂载配置与实际状态冲突");
    assert.equal(await page.locator("#deployment-toggle").isEnabled(), true);
    await page.screenshot({ path: path.join(evidence, "webui-mobile-mount-conflict.png"), fullPage: true });
    results.push("unavailable backend with surviving components never reports ready");
    await update({ ...initial, manager: "APatch", mount_backend: "apatch_overlay",
      overlay_state: "missing" }, "未部署");
    assert.equal(await page.locator("#deployment-toggle").isEnabled(), true);
    assert.match(await page.locator("#backend-detail").textContent(), /OverlayFS/);
    assert.equal(await page.locator("#notice").isHidden(), true);
    await update({ desired: "on", boot_choice: "on", apk: "match", jar: "match",
      binder: "found", package: "installed", system_app: "yes",
      carlife_apk: "match", carlife_package: "installed", carlife_system_app: "yes",
      carlife_native: "match", carlife_compatible: "yes" }, "部署尚未就绪");
    await update({ overlay_state: "active" }, "基础服务就绪");
    await page.screenshot({ path: path.join(evidence, "webui-mobile-native-overlay.png"), fullPage: true });
    results.push("native read-only overlay requires actual init mounts for readiness");
    await update({ carlife_package: "missing" }, "部署尚未就绪");
    await update({ carlife_package: "installed", carlife_system_app: "no" }, "部署尚未就绪");
    results.push("missing or unsystemized CarLife cannot report readiness");
    await update({ carlife_system_app: "yes", carlife_native: "different" }, "部署尚未就绪");
    assert.equal(await page.locator("#carlife-state").textContent(), "原生库未就绪");
    await update({ carlife_native: "match", carlife_compatible: "no" }, "部署尚未就绪");
    assert.equal(await page.locator("#carlife-state").textContent(), "版本过低");
    await update({ carlife_compatible: "unknown" }, "部署尚未就绪");
    results.push("missing native libraries and incompatible or unknown CarLife versions never report readiness");
    await update(initial, "未部署");
    await update({ compatibility: "ROM_MISMATCH", rom: '<img src=x onerror="alert(1)">' }, "系统不匹配");
    assert.equal(await page.locator("#deployment-toggle").isDisabled(), true);
    assert.equal(await page.locator("#rom-detail img").count(), 0);
    results.push("wrong ROM rejects deployment; diagnostics rendered as text");
    await update({ ...initial, payload: "APK_CORRUPT" }, "部署检查未通过");
    assert.equal(await page.locator("#deployment-toggle").isDisabled(), true);
    results.push("corrupt APK rejected");
    await update({ ...initial, update_pending: "yes", reboot_required: "yes" }, "安装待重启");
    assert.equal(await page.locator("#deployment-toggle").isDisabled(), true);
    results.push("pending install blocked");
    await update(initial, "未部署");
    await page.evaluate(() => { window.failNext = "deploy"; });
    await page.locator("#deployment-toggle").click();
    await page.locator("#confirm-accept").click();
    await page.getByText("未获得 Root 权限", { exact: true }).waitFor();
    assert.equal(await page.evaluate(() => window.fixture.desired), "off");
    results.push("rejected mutation rereads actual state");
    await update({
      ...initial, desired: "on", boot_choice: "on", apk: "missing", jar: "missing",
    }, "部署尚未就绪");
    results.push("mount failure never reports ready");
    await update({
      ...initial, desired: "on", boot_choice: "on", apk: "match", jar: "match",
      binder: "found", package: "installed", system_app: "no",
    }, "部署尚未就绪");
    results.push("user APK alone never reports system installation success");
    await update(initial, "未部署");
    await page.evaluate(() => { window.failNext = "status"; });
    await page.locator("#refresh").click();
    await page.getByText("无法读取设备状态", { exact: true }).waitFor();
    assert.equal(await page.locator("#deployment-toggle").isDisabled(), true);
    results.push("stale diagnostics disable actions");
    await page.locator("#refresh").click();
    await page.getByText("未部署", { exact: true }).waitFor();
    await page.locator("summary").click();
    for (const width of [320, 360, 390, 768, 1280]) {
      await page.setViewportSize({ width, height: width >= 768 ? 960 : 844 });
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, `Overflow at ${width}px`);
      const overlapping = await page.locator(".deployment-row").evaluate(el => {
        const [label, toggle] = [...el.children].map(child => child.getBoundingClientRect());
        return label.right > toggle.left || toggle.width !== 48 || toggle.height !== 28;
      });
      assert.equal(overlapping, false);
      assert.equal(await page.locator(".brand img").evaluate(img => img.complete && img.naturalWidth > 0), true);
    }
    await page.screenshot({ path: path.join(evidence, "webui-desktop.png"), fullPage: true });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.screenshot({ path: path.join(evidence, "webui-mobile-dark.png"), fullPage: true });
    results.push("320/360/390/768/1280px layouts, logo, details and dark mode");
    if (process.env.STATUS_FIXTURE) {
      const shellStatus = JSON.parse(fs.readFileSync(process.env.STATUS_FIXTURE, "utf8"));
      assert.equal(shellStatus.module_version, version);
      await update(shellStatus, "基础服务就绪");
      assert.equal(await page.locator("#carlife-state").textContent(), "已安装");
      results.push("actual shell fixture status is accepted by the WebUI and reports all components ready");
    }
    const offline = await browser.newPage({ viewport: { width: 390, height: 844 } });
    await offline.goto(url);
    await offline.getByText("无法读取设备状态", { exact: true }).waitFor();
    assert.equal(await offline.locator("#deployment-toggle").isDisabled(), true);
    results.push("ordinary browser has no fake device success or privileged actions");
    assert.deepEqual(pageErrors, []);
    const report = { fixture_groups: results.length, passed: results, uncaught_errors: pageErrors, actual_android_webview_tested: false };
    fs.writeFileSync(path.join(evidence, "webui-tests.json"), JSON.stringify(report, null, 2) + "\n");
    console.log(JSON.stringify(report, null, 2));
  } finally {
    await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
