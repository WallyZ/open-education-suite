const { test, expect } = require("@playwright/test");

const companionPath = "/ui/early-play/index.html";
const packPath =
  "/content-repos/open-education-founder-level-civic-classical/" +
  "study-plans/modules/early-play-readiness/generated/" +
  "early-play-adult-offline-pack.html";
const requiredViewports = [
  { width: 320, height: 900 },
  { width: 768, height: 1024 },
  { width: 1280, height: 900 }
];

async function optInAndOpen(page) {
  await page.getByLabel(/I am a responsible adult/).check();
  await page.getByRole("button", { name: "Open companion pack" }).click();
  await expect(page.locator("#packFrame")).toBeVisible();
  await expect(page.getByRole("status")).toContainText("opened locally");
}

test.describe("early-play adult companion", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(companionPath);
  });

  test("fails closed until adult opt-in and exposes no child data surface", async ({
    page,
    context
  }) => {
    await expect(
      page.getByRole("heading", { name: "Early Play Adult Companion" })
    ).toBeVisible();
    await expect(page.getByRole("button", { name: "Open companion pack" })).toBeDisabled();
    await expect(page.locator("#packRegion")).toBeHidden();
    await expect(page.getByText("No child accounts or chat")).toBeVisible();
    await expect(page.getByText("No profiling or persuasion")).toBeVisible();
    await expect(page.getByText("No identifiable uploads")).toBeVisible();

    await expect(page.locator('input[type="file"]')).toHaveCount(0);
    await expect(page.locator("textarea")).toHaveCount(0);
    await expect(page.locator("[contenteditable]")).toHaveCount(0);
    await expect(page.locator("form")).toHaveCount(0);

    const beforeOpenStorage = await page.evaluate(() => ({
      local: localStorage.length,
      session: sessionStorage.length
    }));
    expect(beforeOpenStorage).toEqual({ local: 0, session: 0 });
    expect(await context.cookies()).toEqual([]);

    await optInAndOpen(page);
    const frame = page.frameLocator("#packFrame");
    await expect(
      frame.getByRole("heading", { name: "Early Play Adult Offline Pack" })
    ).toBeVisible();
    await expect(frame.locator(".invitation-card")).toHaveCount(126);
    await expect(frame.locator("script")).toHaveCount(0);
    await expect(frame.locator("form")).toHaveCount(0);
    await expect(frame.locator("input")).toHaveCount(0);
    await expect(frame.locator("textarea")).toHaveCount(0);
    await expect(frame.locator("iframe")).toHaveCount(0);
    await expect(page.locator("#downloadPack")).toHaveAttribute("href", /^blob:/);

    const afterOpenStorage = await page.evaluate(() => ({
      local: localStorage.length,
      session: sessionStorage.length
    }));
    expect(afterOpenStorage).toEqual({ local: 0, session: 0 });
    expect(await context.cookies()).toEqual([]);

    await page.getByRole("button", { name: "Clear and close" }).click();
    await expect(page.locator("#packRegion")).toBeHidden();
    await expect(page.getByRole("button", { name: "Open companion pack" })).toBeDisabled();
    await expect(page.locator("#downloadPack")).not.toHaveAttribute("href", /.+/);
  });

  test("supports keyboard entry, visible focus, and semantic landmarks", async ({
    page
  }) => {
    await page.keyboard.press("Tab");
    await expect(page.locator(".skip-link")).toBeFocused();
    await page.keyboard.press("Enter");
    await expect(page.locator("#main")).toBeFocused();

    await page.keyboard.press("Tab");
    await expect(page.locator("#adultOptIn")).toBeFocused();
    await page.keyboard.press("Space");
    await page.keyboard.press("Tab");
    await expect(page.locator("#openPack")).toBeFocused();

    const focusStyle = await page.locator("#openPack").evaluate((element) => {
      const style = getComputedStyle(element);
      return {
        outlineStyle: style.outlineStyle,
        outlineWidth: style.outlineWidth
      };
    });
    expect(focusStyle.outlineStyle).not.toBe("none");
    expect(Number.parseFloat(focusStyle.outlineWidth)).toBeGreaterThanOrEqual(3);

    await page.keyboard.press("Enter");
    await expect(page.locator("#printPack")).toBeFocused();
    await expect(page.getByRole("main")).toHaveCount(1);
    await expect(page.getByRole("heading", { level: 1 })).toHaveCount(1);
    await expect(page.locator("#packFrame")).toHaveAttribute(
      "title",
      "Early Play Adult Offline Pack"
    );
    await expect(page.locator("#status")).toHaveAttribute("aria-live", "polite");
  });

  test("passes the three required responsive viewports without overflow", async ({
    page
  }, testInfo) => {
    const results = [];
    for (const viewport of requiredViewports) {
      await page.setViewportSize(viewport);
      await page.goto(companionPath);
      const lockedMetrics = await page.evaluate(() => ({
        clientWidth: document.documentElement.clientWidth,
        scrollWidth: document.documentElement.scrollWidth
      }));
      expect(lockedMetrics.scrollWidth).toBeLessThanOrEqual(
        lockedMetrics.clientWidth + 1
      );

      await optInAndOpen(page);
      const openMetrics = await page.evaluate(() => {
        const frame = document.querySelector("#packFrame").getBoundingClientRect();
        return {
          clientWidth: document.documentElement.clientWidth,
          scrollWidth: document.documentElement.scrollWidth,
          frameLeft: Math.round(frame.left),
          frameRight: Math.round(frame.right),
          frameWidth: Math.round(frame.width)
        };
      });
      expect(openMetrics.scrollWidth).toBeLessThanOrEqual(
        openMetrics.clientWidth + 1
      );
      expect(openMetrics.frameLeft).toBeGreaterThanOrEqual(0);
      expect(openMetrics.frameRight).toBeLessThanOrEqual(
        openMetrics.clientWidth + 1
      );
      expect(openMetrics.frameWidth).toBeGreaterThan(250);
      results.push({ viewport, lockedMetrics, openMetrics });
    }

    await testInfo.attach("early-play-responsive-contract", {
      body: JSON.stringify(results, null, 2),
      contentType: "application/json"
    });
  });

  test("retains the loaded pack offline and presents a print-only route", async ({
    page,
    context
  }) => {
    await optInAndOpen(page);
    const frame = page.frameLocator("#packFrame");
    await expect(frame.getByText("Family Controls And Route Choice")).toBeVisible();

    await context.setOffline(true);
    await expect(frame.getByText("Family Controls And Route Choice")).toBeVisible();
    await expect(page.locator("#downloadPack")).toHaveAttribute("href", /^blob:/);
    await context.setOffline(false);

    await page.emulateMedia({ media: "print" });
    await expect(page.locator(".site-header")).toBeHidden();
    await expect(page.locator(".gate-card")).toBeHidden();
    await expect(page.locator(".safeguards")).toBeHidden();
    await expect(page.locator("#packRegion")).toBeVisible();
  });

  test("uses only the approved local origin and fails closed on pack errors", async ({
    page
  }) => {
    const externalRequests = [];
    page.on("request", (request) => {
      const url = new URL(request.url());
      if (url.origin !== new URL(page.url()).origin && url.protocol !== "blob:") {
        externalRequests.push(request.url());
      }
    });

    await page.route(`**${packPath}`, async (route) => {
      await route.fulfill({
        status: 503,
        contentType: "text/plain",
        body: "temporarily unavailable"
      });
    });

    await page.getByLabel(/I am a responsible adult/).check();
    await page.getByRole("button", { name: "Open companion pack" }).click();

    await expect(
      page.getByRole("heading", { name: "The companion pack could not be opened" })
    ).toBeVisible();
    await expect(page.locator("#failurePanel")).toBeFocused();
    await expect(page.locator("#failureMessage")).toContainText(
      "No child-facing fallback, chat, upload, or alternate network route was opened"
    );
    await expect(page.locator("#packRegion")).toBeHidden();
    expect(externalRequests).toEqual([]);
  });
});
