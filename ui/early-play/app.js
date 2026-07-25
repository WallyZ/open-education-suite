(() => {
  "use strict";

  const packPath =
    "/content-repos/open-education-founder-level-civic-classical/" +
    "study-plans/modules/early-play-readiness/generated/" +
    "early-play-adult-offline-pack.html";

  const adultOptIn = document.querySelector("#adultOptIn");
  const openPack = document.querySelector("#openPack");
  const closePack = document.querySelector("#closePack");
  const printPack = document.querySelector("#printPack");
  const downloadPack = document.querySelector("#downloadPack");
  const packRegion = document.querySelector("#packRegion");
  const packFrame = document.querySelector("#packFrame");
  const failurePanel = document.querySelector("#failurePanel");
  const failureMessage = document.querySelector("#failureMessage");
  const skipLink = document.querySelector(".skip-link");
  const main = document.querySelector("#main");
  const status = document.querySelector("#status");

  const requiredElements = [
    adultOptIn,
    openPack,
    closePack,
    printPack,
    downloadPack,
    packRegion,
    packFrame,
    failurePanel,
    failureMessage,
    skipLink,
    main,
    status
  ];

  if (requiredElements.some((element) => !element)) {
    throw new Error("Early-play adult companion markup is incomplete.");
  }

  let downloadUrl = "";
  let opening = false;

  const prohibitedPackPatterns = [
    /<script\b/i,
    /<iframe\b/i,
    /<form\b/i,
    /<input\b/i,
    /<textarea\b/i,
    /contenteditable/i,
    /\bhttps?:\/\//i,
    /\bfetch\s*\(/i,
    /\blocalStorage\b/i,
    /\bsessionStorage\b/i
  ];

  function setStatus(message) {
    status.textContent = message;
  }

  function revokeDownloadUrl() {
    if (downloadUrl) {
      URL.revokeObjectURL(downloadUrl);
      downloadUrl = "";
    }
    downloadPack.removeAttribute("href");
  }

  function closeCompanion({ preserveOptIn = false } = {}) {
    revokeDownloadUrl();
    packFrame.removeAttribute("src");
    packFrame.srcdoc = "";
    packRegion.hidden = true;
    failurePanel.hidden = true;
    closePack.hidden = true;
    if (!preserveOptIn) {
      adultOptIn.checked = false;
    }
    openPack.disabled = !adultOptIn.checked;
    openPack.hidden = false;
    setStatus(
      adultOptIn.checked
        ? "Responsible-adult opt-in confirmed. The companion is ready to open."
        : "Waiting for responsible-adult opt-in. No companion content has loaded."
    );
  }

  function validatePack(html) {
    if (!html.includes("<title>Early Play Adult Offline Pack</title>")) {
      throw new Error("The approved offline-pack identity was not found.");
    }
    if (!html.includes("126 Age-Specific Invitation Cards")) {
      throw new Error("The approved 126-card inventory was not found.");
    }
    if (prohibitedPackPatterns.some((pattern) => pattern.test(html))) {
      throw new Error("The pack contains a prohibited interactive or network feature.");
    }
  }

  async function openCompanion() {
    if (!adultOptIn.checked || opening) {
      return;
    }

    opening = true;
    openPack.disabled = true;
    failurePanel.hidden = true;
    setStatus("Opening the approved local pack. No learner data is being sent.");

    try {
      const response = await fetch(packPath, {
        cache: "no-store",
        credentials: "omit",
        headers: { Accept: "text/html" }
      });
      if (!response.ok) {
        throw new Error(`Approved pack unavailable (${response.status}).`);
      }

      const html = await response.text();
      validatePack(html);

      revokeDownloadUrl();
      downloadUrl = URL.createObjectURL(
        new Blob([html], { type: "text/html;charset=utf-8" })
      );
      downloadPack.href = downloadUrl;
      packFrame.srcdoc = html;
      packRegion.hidden = false;
      closePack.hidden = false;
      openPack.hidden = true;
      setStatus(
        "Companion opened locally for this tab. No child profile, chat, upload, or tracking was created."
      );
      packRegion.scrollIntoView({ block: "start" });
      printPack.focus();
    } catch (error) {
      closeCompanion({ preserveOptIn: true });
      failureMessage.textContent =
        `${error.message} No child-facing fallback, chat, upload, ` +
        "or alternate network route was opened.";
      failurePanel.hidden = false;
      setStatus("The companion failed closed. No content or learner data was retained.");
      failurePanel.focus?.();
    } finally {
      opening = false;
      if (!openPack.hidden) {
        openPack.disabled = !adultOptIn.checked;
      }
    }
  }

  adultOptIn.addEventListener("change", () => {
    if (!adultOptIn.checked) {
      closeCompanion();
      return;
    }
    openPack.disabled = false;
    setStatus("Responsible-adult opt-in confirmed. The companion is ready to open.");
  });

  skipLink.addEventListener("click", (event) => {
    event.preventDefault();
    main.focus();
  });
  openPack.addEventListener("click", openCompanion);
  closePack.addEventListener("click", () => closeCompanion());
  printPack.addEventListener("click", () => {
    const frameWindow = packFrame.contentWindow;
    if (!frameWindow) {
      setStatus("Print is unavailable. Save the offline copy and print it locally.");
      return;
    }
    frameWindow.focus();
    frameWindow.print();
  });

  window.addEventListener("beforeunload", revokeDownloadUrl);
  closeCompanion();
})();
