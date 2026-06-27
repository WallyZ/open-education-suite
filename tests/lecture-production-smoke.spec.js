const { test, expect } = require("@playwright/test");
const { pathToFileURL } = require("node:url");

test.describe("lecture production smoke", () => {
  test("selects a rendered lecture package and plays it from the learner flow", async ({ page }) => {
    const uiPath = process.env.OES_LECTURE_SMOKE_UI;
    test.skip(!uiPath, "Run through scripts/testing/run-lecture-production-smoke.ps1.");

    await page.goto(pathToFileURL(uiPath).href);
    await expect(page.getByRole("heading", { name: "Learner Workspace" })).toBeVisible();
    await page.locator("#courseSelect").selectOption("game-development:study-plans/courses/GDEV-101-game-design-foundations.md");
    await expect(page.locator("#objectiveId")).toHaveText("game-development:objectives/course/gdev-101/design-vocabulary");
    await page.getByRole("button", { name: "Lecture" }).click();

    await expect(page.locator("#lectureStatusPill")).toHaveText("rendered-fixture");
    await expect(page.locator("#lectureVideo")).toBeVisible();
    await expect(page.locator("#lectureVideo")).toHaveAttribute("data-asset-id", "lecture-guided-camera-mp4");
    await expect(page.locator("#lectureVideo")).toHaveAttribute("data-view-mode", "guided");
    await expect(page.locator("#lectureVideo source")).toHaveAttribute("src", /open-education-game-development\/generated-lectures\/.*lecture-guided-camera-mp4\.mp4/);
    await expect(page.getByRole("button", { name: "Guided camera" })).toHaveAttribute("aria-pressed", "true");
    await expect(page.getByText("Archived media SHA-256")).toBeVisible();
    await expect(page.locator("#lectureTranscript")).toContainText("A verb is what the player can do.");
    await expect(page.locator("#learningEnvironmentList")).toContainText("Keep a paper notebook and pen available");

    await page.getByRole("button", { name: "Classroom" }).click();
    await expect(page.locator("#lectureVideo")).toHaveAttribute("data-asset-id", "lecture-video-mp4");
    await page.getByRole("button", { name: "Guided camera" }).click();
    await expect(page.locator("#lectureVideo")).toHaveAttribute("data-asset-id", "lecture-guided-camera-mp4");

    await page.getByRole("button", { name: "Board close-up" }).click();
    await expect(page.getByText("Board close-up is on.")).toBeVisible();
    await expect(page.locator("#lectureVideo")).toHaveAttribute("data-asset-id", "lecture-board-close-up-mp4");
    await page.getByRole("button", { name: "Play lecture" }).click();
    await expect(page.getByRole("button", { name: "Pause lecture" })).toHaveAttribute("aria-pressed", "true");

    const mediaState = await page.locator("#lectureVideo").evaluate((video) => ({
      assetId: video.dataset.assetId,
      sha256: video.dataset.sha256,
      source: video.querySelector("source")?.getAttribute("src") || ""
    }));
    expect(mediaState.assetId).toBe("lecture-board-close-up-mp4");
    expect(mediaState.sha256).toMatch(/^[a-f0-9]{64}$/);
    expect(mediaState.source).toContain("lecture-board-close-up-mp4.mp4");

    await page.locator('.pause-prompt-button[data-pause-second="60"]').click();
    await expect(page.locator("#lecturePosition")).toHaveText("1:00 / 3:00");
    await expect(page.locator("#lecturePauseOverlay")).toContainText("Pause and write: verb, goal, feedback");
  });
});
