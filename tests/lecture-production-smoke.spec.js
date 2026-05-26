const { test, expect } = require("@playwright/test");
const { pathToFileURL } = require("node:url");

test.describe("lecture production smoke", () => {
  test("selects a rendered lecture package and plays it from the learner flow", async ({ page }) => {
    const uiPath = process.env.OES_LECTURE_SMOKE_UI;
    test.skip(!uiPath, "Run through scripts/testing/run-lecture-production-smoke.ps1.");

    await page.goto(pathToFileURL(uiPath).href);
    await expect(page.getByRole("heading", { name: "Learner Workspace" })).toBeVisible();
    await page.getByRole("button", { name: "Lecture" }).click();

    await expect(page.locator("#lectureStatusPill")).toHaveText("rendered-fixture");
    await expect(page.locator("#lectureVideo")).toBeVisible();
    await expect(page.locator("#lectureVideo")).toHaveAttribute("data-asset-id", "lecture-video-mp4");
    await expect(page.locator("#lectureVideo source")).toHaveAttribute("src", /var\/lecture-media\/.*lecture-video-mp4\.mp4/);
    await expect(page.getByText("Archived media SHA-256")).toBeVisible();
    await expect(page.locator("#lectureTranscript")).toContainText("A verb is what the player can do.");

    await page.getByRole("button", { name: "Play lecture" }).click();
    await expect(page.getByRole("button", { name: "Pause lecture" })).toHaveAttribute("aria-pressed", "true");

    const mediaState = await page.locator("#lectureVideo").evaluate((video) => ({
      assetId: video.dataset.assetId,
      sha256: video.dataset.sha256,
      source: video.querySelector("source")?.getAttribute("src") || ""
    }));
    expect(mediaState.assetId).toBe("lecture-video-mp4");
    expect(mediaState.sha256).toMatch(/^[a-f0-9]{64}$/);
    expect(mediaState.source).toContain("lecture-video-mp4.mp4");

    await page.locator("#lectureProgress").fill("60");
    await expect(page.locator("#lecturePosition")).toHaveText("1:00 / 3:00");
  });
});
