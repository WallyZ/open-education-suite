const { defineConfig, devices } = require("@playwright/test");

const outputDir = process.env.PLAYWRIGHT_OUTPUT_DIR || ".codex-cache/tmp/playwright-output";

module.exports = defineConfig({
  testDir: "./tests",
  outputDir,
  timeout: 30_000,
  expect: {
    timeout: 5_000
  },
  reporter: [["line"]],
  use: {
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
