const { defineConfig, devices } = require("@playwright/test");

const outputDir = process.env.PLAYWRIGHT_OUTPUT_DIR || ".codex-cache/tmp/playwright-output";
const bridgePort = Number(process.env.OPEN_EDUCATION_TEST_BRIDGE_PORT || 18786);
const bridgeBaseURL = `http://127.0.0.1:${bridgePort}`;

module.exports = defineConfig({
  testDir: "./tests",
  outputDir,
  timeout: 30_000,
  expect: {
    timeout: 5_000
  },
  reporter: [["line"]],
  webServer: {
    command:
      `powershell.exe -NoProfile -ExecutionPolicy Bypass ` +
      `-File .\\scripts\\start_learner_ui_bridge.ps1 ` +
      `-RepoRoot . -HostName 127.0.0.1 -Port ${bridgePort}`,
    url: `${bridgeBaseURL}/ui/early-play/index.html`,
    reuseExistingServer: true,
    timeout: 120_000
  },
  use: {
    baseURL: bridgeBaseURL,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    video: "retain-on-failure"
  },
  projects: [
    {
      name: "chromium-desktop",
      use: {
        ...devices["Desktop Chrome"],
        viewport: { width: 1440, height: 920 }
      }
    },
    {
      name: "chromium-mobile",
      use: {
        ...devices["Pixel 7"],
        isMobile: true
      }
    }
  ]
});
