const path = require("node:path");
const { pathToFileURL } = require("node:url");
const { test, expect } = require("@playwright/test");

const uiPath = path.resolve(__dirname, "..", "ui", "learner", "index.html");
const uiUrl = pathToFileURL(uiPath).href;
const learnerViews = ["lesson", "lecture", "progress", "assessment", "handoff", "evidence"];

test.describe("learner workspace", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(uiUrl);
  });

  test("loads the GDEV-101 learner workspace with source provenance", async ({ page }) => {
    await expect(page.getByRole("heading", { name: "Learner Workspace" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Start GDEV-101 design vocabulary" })).toBeVisible();
    await expect(page.locator("#objectiveId")).toHaveText("game-development:objectives/course/gdev-101/design-vocabulary");
    await expect(page.getByRole("heading", { name: "GDEV-101 Game Design Foundations" })).toBeVisible();
    await page.getByRole("button", { name: "Evidence" }).click();
    await expect(page.getByText("open-education-game-development / study-plans\\courses\\GDEV-101-game-design-foundations.md")).toBeVisible();
  });

  test("browses ingested sources, courses, and objectives without changing the active session", async ({ page }) => {
    await expect(page.getByRole("heading", { name: "Catalog" })).toBeVisible();
    await page.locator("#sourceSelect").selectOption("software-development");
    await expect(page.getByRole("button", { name: "Debugging" })).toBeVisible();

    await page.locator("#sourceSelect").selectOption("game-development");
    await page.locator("#courseSelect").selectOption("game-development:study-plans/courses/GDEV-102-programming-for-games.md");
    await expect(page.getByRole("button", { name: "Programming Fundamentals" })).toBeVisible();
    await page.locator('[data-objective-id="game-development:objectives/course/gdev-102/programming-fundamentals"]').click();
    await expect(page.getByText("Objective selected for inspection: Programming Fundamentals")).toBeVisible();
    await expect(page.locator("#objectiveId")).toHaveText("game-development:objectives/course/gdev-101/design-vocabulary");
  });

  test("loads localization scaffolding for labels, dates, objectives, and feedback", async ({ page }) => {
    const locale = await page.evaluate(() => window.openEducationLocale);
    expect(locale.locale).toBe("en-US");
    expect(locale.labels.workspaceTitle).toBe("Learner Workspace");
    expect(locale.objectiveNames["game-development:objectives/course/gdev-101/design-vocabulary"]).toBe("Design Vocabulary");
    expect(locale.feedback.assessmentSaved).toBe("Assessment response saved locally as an evidence proposal.");
    await expect(page.getByRole("heading", { name: "Learner Workspace" })).toBeVisible();
  });

  test("shows evidence-centered learner analytics without surveillance framing", async ({ page }) => {
    await page.getByRole("button", { name: "Progress" }).click();
    await expect(page.getByRole("heading", { name: "Evidence view" })).toBeVisible();
    await expect(page.getByText("Evidence items")).toBeVisible();
    await expect(page.getByText("No clickstream or time-spent tracking")).toBeVisible();
    await expect(page.getByText("Current source: open-education-game-development")).toBeVisible();
  });

  test("shows instructor operator handoff for blockers, interventions, and content health", async ({ page }) => {
    await page.getByRole("button", { name: "Handoff" }).click();
    await expect(page.getByRole("heading", { name: "Operator handoff" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Blockers" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Interventions" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Content health" })).toBeVisible();
    await expect(page.getByText("Operator review only. No learner-state mutation.")).toBeVisible();
  });

  test("supports keyboard skip link and tab-accessible primary controls", async ({ page }) => {
    await page.keyboard.press("Tab");
    await expect(page.locator(".skip-link")).toBeFocused();
    await page.keyboard.press("Enter");
    await expect(page.locator("#workspace")).toBeFocused();

    await page.getByRole("button", { name: "Hint" }).focus();
    await page.keyboard.press("Enter");
    await expect(page.getByText("Start from the selected source: GDEV-101 Game Design Foundations.")).toBeVisible();
  });

  test("supports keyboard flow across all learner workspace views", async ({ page }) => {
    for (const view of learnerViews) {
      await page.locator(`[data-view="${view}"]`).focus();
      await page.keyboard.press("Enter");
      await expect(page.locator(`[data-panel="${view}"]`)).toBeVisible();
      await expect(page.locator(`[data-view="${view}"]`)).toHaveAttribute("aria-current", "page");
    }
  });

  test("keeps a deterministic visual regression contract for every learner view", async ({ page }, testInfo) => {
    const visualContract = [];
    for (const view of learnerViews) {
      await page.locator(`[data-view="${view}"]`).focus();
      await page.keyboard.press("Enter");
      const metrics = await page.evaluate((currentView) => {
        const panel = document.querySelector(`[data-panel="${currentView}"]`);
        const rect = panel.getBoundingClientRect();
        return {
          view: currentView,
          panel: {
            width: Math.round(rect.width),
            height: Math.round(rect.height),
            top: Math.round(rect.top),
            left: Math.round(rect.left)
          },
          viewport: {
            width: document.documentElement.clientWidth,
            height: document.documentElement.clientHeight
          },
          hasHorizontalOverflow: document.documentElement.scrollWidth > document.documentElement.clientWidth + 1
        };
      }, view);
      expect(metrics.hasHorizontalOverflow).toBe(false);
      expect(metrics.panel.width).toBeGreaterThan(280);
      expect(metrics.panel.height).toBeGreaterThan(120);
      const screenshot = await page.screenshot({ fullPage: false });
      expect(screenshot.length).toBeGreaterThan(5000);
      visualContract.push(metrics);
    }
    await testInfo.attach("learner-visual-regression-contract", {
      body: JSON.stringify(visualContract, null, 2),
      contentType: "application/json"
    });
  });

  test("records a response, hint, completion, and journal locally", async ({ page }) => {
    await page.getByLabel("Response").fill("Verbs are actions. Goals define success. Feedback tells the player what changed.");
    await page.getByRole("button", { name: "Submit" }).click();
    await expect(page.getByText("Sort those words into actions, goals, constraints, and feedback")).toBeVisible();

    await page.getByRole("button", { name: "Hint" }).click();
    await expect(page.getByText("Start from the selected source: GDEV-101 Game Design Foundations.")).toBeVisible();

    await page.getByRole("button", { name: "Mark complete" }).click();
    await expect(page.locator("#masteryValue")).toHaveText("18%");

    await page.getByRole("button", { name: "Evidence" }).click();
    await page.getByRole("textbox", { name: "Journal" }).fill("I can separate player actions from goals and feedback.");
    await page.getByRole("button", { name: "Save journal" }).click();
    await expect(page.getByText("Journal saved locally.")).toBeVisible();
  });

  test("supports lecture playback, transcript, citations, checkpoints, and resume", async ({ page }) => {
    await page.getByRole("button", { name: "Lecture" }).click();
    await expect(page.getByRole("heading", { name: "Design Vocabulary: Verbs, Goals, and Feedback" })).toBeVisible();
    await expect(page.getByText("This lecture uses an original generated instructor")).toBeVisible();
    await expect(page.locator("#learningEnvironmentList")).toContainText("Keep a paper notebook and pen available");
    await expect(page.getByText("Verb is the action, goal is the target state")).toBeVisible();
    await expect(page.locator("#lectureTranscript")).toContainText("A verb is what the player can do.");
    await expect(page.getByText("open-education-game-development / study-plans\\courses\\GDEV-101-game-design-foundations.md")).toBeVisible();

    await page.getByRole("button", { name: "Board close-up" }).click();
    await expect(page.getByText("Board close-up is on.")).toBeVisible();

    await page.getByRole("button", { name: "Play lecture" }).click();
    await expect(page.getByRole("button", { name: "Pause lecture" })).toHaveAttribute("aria-pressed", "true");

    await expect(page.locator("#pausePromptList")).toContainText("Jump to 1:00 pause");
    await page.locator('.pause-prompt-button[data-pause-second="60"]').click();
    await expect(page.locator("#lecturePosition")).toHaveText("1:00 / 3:00");
    await expect(page.locator("#lecturePauseOverlay")).toContainText("Pause and write: verb, goal, feedback");

    await page.locator("#lectureProgress").fill("95");
    await expect(page.locator("#lecturePosition")).toHaveText("1:35 / 3:00");
    await expect(page.locator("#lecturePauseOverlay")).toBeHidden();

    await page.getByRole("button", { name: "Practice Handoff 2:15" }).click();
    await expect(page.locator("#lecturePosition")).toHaveText("2:15 / 3:00");

    await page.getByLabel("In a familiar game, identify one verb, one goal, and one feedback signal.").fill("Jump, reach the flag, and hear a success sound.");
    await page.locator('[data-checkpoint-save="identify-vgf"]').click();
    await expect(page.getByText("Checkpoint saved locally as an evidence proposal.")).toBeVisible();

    await page.reload();
    await page.getByRole("button", { name: "Lecture" }).click();
    await expect(page.locator("#lecturePosition")).toHaveText("2:15 / 3:00");
  });

  test("keeps core content within the viewport", async ({ page }) => {
    const hasHorizontalOverflow = await page.evaluate(() => {
      return document.documentElement.scrollWidth > document.documentElement.clientWidth + 1;
    });
    expect(hasHorizontalOverflow).toBe(false);

    await page.getByRole("button", { name: "Contrast" }).click();
    await expect(page.locator("body")).toHaveClass(/is-high-contrast/);
    await page.getByRole("button", { name: "Focus" }).click();
    await expect(page.locator("body")).toHaveClass(/is-focus/);
  });
});
