const path = require("node:path");
const { pathToFileURL } = require("node:url");
const { test, expect } = require("@playwright/test");

const uiPath = path.resolve(__dirname, "..", "ui", "learner", "index.html");
const uiUrl = pathToFileURL(uiPath).href;
const learnerViews = ["lesson", "lecture", "progress", "assessment", "handoff", "evidence"];

test.describe("learner workspace", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(uiUrl);
    await page.evaluate(() => localStorage.clear());
    await page.reload();
  });

  test("loads the first catalog course when no course was previously selected", async ({ page }) => {
    await expect(page.getByRole("heading", { name: "Learner Workspace" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Start GDEV-010 toolchain readiness" })).toBeVisible();
    await expect(page.locator("#objectiveId")).toHaveText("game-development:objectives/course/gdev-010/toolchain-readiness");
    await expect(page.getByRole("heading", { name: "GDEV-010 Onboarding Studio" })).toBeVisible();
    await page.getByRole("button", { name: "Evidence" }).click();
    await expect(page.getByText("open-education-game-development / study-plans\\courses\\GDEV-010-onboarding-studio.md")).toBeVisible();
  });

  test("switches sources and courses into the active local lesson and remembers the last course", async ({ page }) => {
    await expect(page.getByRole("heading", { name: "Catalog" })).toBeVisible();
    await expect(page.locator("#courseSelect")).toHaveValue("game-development:study-plans/courses/GDEV-010-onboarding-studio.md");

    await page.locator("#sourceSelect").selectOption("software-development");
    await expect(page.getByRole("button", { name: "Debugging" })).toBeVisible();
    await expect(page.locator("#objectiveId")).toHaveText("software-development:objectives/debugging");
    await expect(page.getByRole("heading", { name: "Start debugging" })).toBeVisible();

    await page.locator("#sourceSelect").selectOption("mens-relationship-skills");
    await page.locator("#courseSelect").selectOption("mens-relationship-skills:study-plans/courses/MRS-303-modern-dating-safety-sexual-health-and-practical-partnership.md");
    await expect(page.getByRole("button", { name: "Online Dating Safety" })).toBeVisible();
    await expect(page.locator("#objectiveId")).toHaveText("mens-relationship-skills:objectives/course/mrs-303/online-dating-safety");
    await expect(page.getByRole("heading", { name: "Start MRS-303 online dating safety" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "MRS-303 - Modern Dating Safety, Sexual Health, And Practical Partnership" })).toBeVisible();
    await expect(page.getByText("Begin MRS-303 - Modern Dating Safety")).toBeVisible();

    await page.reload();
    await expect(page.locator("#sourceSelect")).toHaveValue("mens-relationship-skills");
    await expect(page.locator("#courseSelect")).toHaveValue("mens-relationship-skills:study-plans/courses/MRS-303-modern-dating-safety-sexual-health-and-practical-partnership.md");
    await expect(page.locator("#objectiveId")).toHaveText("mens-relationship-skills:objectives/course/mrs-303/online-dating-safety");
  });

  test("loads localization scaffolding for labels, dates, objectives, and feedback", async ({ page }) => {
    const locale = await page.evaluate(() => window.openEducationLocale);
    expect(locale.locale).toBe("en-US");
    expect(locale.labels.workspaceTitle).toBe("Learner Workspace");
    expect(locale.objectiveNames["game-development:objectives/course/gdev-101/design-vocabulary"]).toBe("Design Vocabulary");
    expect(locale.feedback.assessmentSaved).toBe("Assessment response saved locally as an evidence proposal.");
    await expect(page.getByRole("heading", { name: "Learner Workspace" })).toBeVisible();
  });

  test("keeps separate local profiles, preferences, and learner-owned records", async ({ page }) => {
    await expect(page.getByRole("heading", { name: "Student profile" })).toBeVisible();

    await page.getByLabel("Display name").fill("Alex");
    await page.getByLabel("Explanation").selectOption("socratic");
    await page.getByLabel("Practice").selectOption("project");
    await page.getByLabel("Pace").selectOption("deliberate");
    await page.getByLabel("Format").selectOption("hands-on");
    await page.getByLabel("Goals").fill("debugging, prototypes");
    await page.getByLabel("Access needs").fill("captions, low distraction");
    await page.getByLabel("Prior experience").fill("Scratch, board games");
    await page.getByRole("button", { name: "Save profile" }).click();

    await expect(page.locator("#learner-title")).toHaveText("Alex");
    await expect(page.locator("#preferenceValue")).toHaveText("Socratic");
    await expect(page.locator("#practiceValue")).toHaveText("Project");
    await expect(page.locator("#paceValue")).toHaveText("Deliberate");
    await expect(page.locator("#formatValue")).toHaveText("Hands on");
    await expect(page.locator("#accessValue")).toHaveText("Captions");

    await page.getByRole("button", { name: "Evidence" }).click();
    await page.getByRole("textbox", { name: "Journal" }).fill("Alex journal evidence.");
    await page.getByRole("button", { name: "Save journal" }).click();
    await page.getByRole("button", { name: "Save state" }).click();

    await page.getByLabel("Display name").fill("Blair");
    await page.getByLabel("Goals").fill("math review");
    await page.getByLabel("Access needs").fill("large text");
    await page.getByLabel("Prior experience").fill("algebra basics");
    await page.getByRole("button", { name: "Create profile" }).click();

    await expect(page.locator("#learner-title")).toHaveText("Blair");
    await expect(page.locator("#learnerProfileSelect")).toHaveValue("blair");
    await page.getByRole("textbox", { name: "Journal" }).fill("Blair journal evidence.");
    await page.getByRole("button", { name: "Save journal" }).click();
    await page.getByRole("button", { name: "Save state" }).click();

    const storage = await page.evaluate(() => {
      return Object.fromEntries(
        Object.keys(localStorage)
          .sort()
          .map((key) => [key, localStorage.getItem(key)])
      );
    });

    expect(storage.openEducationLearnerProfiles).toContain("Alex");
    expect(storage.openEducationLearnerProfiles).toContain("Blair");
    expect(storage.openEducationActiveLearnerId).toBe("blair");
    expect(storage["openEducationLearnerJournal:gdev-101-live-smoke-learner"]).toContain("Alex journal evidence.");
    expect(storage["openEducationLearnerJournal:gdev-101-live-smoke-learner"]).not.toContain("Blair journal evidence.");
    expect(storage["openEducationLearnerJournal:blair"]).toContain("Blair journal evidence.");
    expect(storage["openEducationLearnerJournal:blair"]).not.toContain("Alex journal evidence.");
    expect(storage["openEducationLearnerState:gdev-101-live-smoke-learner"]).toContain('"displayName": "Alex"');
    expect(storage["openEducationLearnerState:blair"]).toContain('"displayName": "Blair"');
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
    await expect(page.getByText("Start from GDEV-010 Onboarding Studio, then name the current objective: Toolchain Readiness.")).toBeVisible();
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
    await expect(page.getByText("Start from GDEV-010 Onboarding Studio, then name the current objective: Toolchain Readiness.")).toBeVisible();

    await page.getByRole("button", { name: "Mark complete" }).click();
    await expect(page.locator("#masteryValue")).toHaveText("18%");

    await page.getByRole("button", { name: "Evidence" }).click();
    await page.getByRole("textbox", { name: "Journal" }).fill("I can separate player actions from goals and feedback.");
    await page.getByRole("button", { name: "Save journal" }).click();
    await expect(page.getByText("Journal saved locally.")).toBeVisible();
  });

  test("supports lecture playback, transcript, citations, checkpoints, and resume", async ({ page }) => {
    await page.locator("#courseSelect").selectOption("game-development:study-plans/courses/GDEV-101-game-design-foundations.md");
    await expect(page.locator("#objectiveId")).toHaveText("game-development:objectives/course/gdev-101/design-vocabulary");

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
