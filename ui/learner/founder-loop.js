/* The existing learner state owns this sequence's local, self-reported evidence. */
(() => {
  const lessonId = "lesson:lesson-g1-cw10-d01";
  const sourceId = "founder-level-civic-classical";
  const synthetic = new URLSearchParams(location.search).get("founderRehearsal") === "1";
  let content;
  let renderedOwner;
  const el = (id) => document.getElementById(id);
  const owner = () => el("learnerProfileSelect").value;
  const key = () => `openEducationLearnerState:${owner()}`;
  const stored = () => JSON.parse(localStorage.getItem(key()) || "null");
  const current = () => stored()?.founderLoop;
  function day(value) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || new Date(value).toISOString().slice(0, 10) !== value) throw Error("Invalid review date");
    return value;
  }
  const today = () => day(synthetic ? el("founderClock").value : new Date().toISOString().slice(0, 10));
  const due = (value) => new Date(Date.parse(day(value)) + 7 * 86400000).toISOString().slice(0, 10);
  function phase(record) {
    if (record?.withdrawn) return "withdrawn";
    if (!record?.plan) return "plan";
    if (!record.studied) return "study";
    const last = record.attempts.at(-1);
    if (!last) return "initial";
    if (last.stage === "initial" && !record.corrected) return "feedback";
    if (last.stage === "initial" || (last.stage === "retry" && last.score < 3)) return "retry";
    if (last.stage === "retry") return "delayed";
    return last.score >= 3 ? "complete-self-report" : "delayed-needs-remediation";
  }
  function validate(record, learnerId) {
    if (record.schemaVersion !== 1 || record.learnerId !== learnerId || record.lessonId !== lessonId || record.sourceId !== sourceId || record.synthetic !== synthetic || !/^[a-f0-9]{64}$/.test(record.contentRevision) || !Array.isArray(record.attempts) || record.attempts.length > 100 || typeof record.studied !== "boolean" || typeof record.corrected !== "boolean" || typeof record.withdrawn !== "boolean" || (content && record.contentRevision !== content.contentRevision)) throw Error("Founder state binding rejected");
    if (record.plan !== null && !["text", "oral"].includes(record.plan)) throw Error("Unknown learning route");
    if ((record.studied && !record.plan) || (record.corrected && !record.attempts.length)) throw Error("Invalid learning order");
    let previous;
    for (const attempt of record.attempts) {
      const expected = !previous ? "initial" : previous.stage === "initial" || (previous.stage === "retry" && previous.score < 3) ? "retry" : "delayed";
      if (!record.studied || (previous && previous.stage === "delayed") || attempt.stage !== expected || (previous && !record.corrected) || !Number.isInteger(attempt.score) || attempt.score < 1 || attempt.score > 4 || typeof attempt.response !== "string" || !attempt.response.trim() || attempt.response.length > 4000 || attempt.support !== "self-check") throw Error("Invalid attempt record");
      day(attempt.date);
      if (!synthetic && attempt.date > new Date().toISOString().slice(0, 10)) throw Error("Future-dated evidence rejected");
      if (previous && (attempt.date < previous.date || (attempt.stage === "delayed" && attempt.date < due(previous.date)))) throw Error("Early or unordered review");
      const suffix = { initial: "i1", retry: "x1", delayed: "d1" }[attempt.stage];
      if (attempt.assessmentId !== `assessment:assess-g1-t1-src-${suffix}`) throw Error("Wrong assessment form");
      previous = attempt;
    }
    return record;
  }
  function save(record) {
    validate(record, owner());
    const snapshot = stored() || buildLearnerStateSnapshot();
    snapshot.founderLoop = record;
    localStorage.setItem(key(), JSON.stringify(snapshot));
    render();
  }
  function render() {
    if (!content) return;
    if (renderedOwner !== owner()) {
      el("founderResponse").value = "";
      el("founderScore").value = "";
      renderedOwner = owner();
    }
    el("founderHistory").replaceChildren();
    el("founderPrompt").textContent = "";
    let record;
    try { record = current(); if (record) validate(record, owner()); }
    catch { el("founderStatus").textContent = "Saved Founder state rejected; restore a valid export or clear this practice."; return; }
    const next = phase(record);
    const form = content.forms.find((item) => item.stage === next);
    el("founderHistory").replaceChildren(...(record?.attempts || []).map((attempt) => {
      const item = document.createElement("li");
      item.textContent = `${attempt.stage}, ${attempt.date}, self-check ${attempt.score}: ${attempt.response}`;
      return item;
    }));
    el("founderPrompt").textContent = form?.prompt || "Use the plan, study, and correction controls in order.";
    el("founderFeedback").textContent = [content.feedback, ...content.correction].join(" ");
    el("founderStatus").textContent = `${synthetic ? "Synthetic rehearsal. " : ""}Stage: ${next}. Attempts: ${record?.attempts.length || 0}. Independent mastery unearned.${next === "delayed" ? ` Review due: ${due(record.attempts.at(-1).date)}.` : ""}`;
  }
  function act(operation) {
    try {
      if (!content) throw Error("Open the Founder sequence first");
      const record = structuredClone(current() || { schemaVersion: 1, learnerId: owner(), sourceId, lessonId, contentRevision: content.contentRevision, synthetic, plan: null, studied: false, corrected: false, withdrawn: false, attempts: [] });
      validate(record, owner());
      operation(record);
      save(record);
    } catch (error) { el("founderStatus").textContent = `Founder action rejected: ${error.message}`; }
  }
  window.openEducationFounderLoop = { validate, render };
  document.addEventListener("DOMContentLoaded", () => {
    el("founderMode").textContent = synthetic ? "Synthetic rehearsal: dates are simulated; this is not learner-outcome evidence." : "Local practice: use a guardian or facilitator for the original age-gated activity, or choose the safe equivalent.";
    el("founderOpen").classList.add("primary-button");
    el("founderContent").querySelectorAll("button").forEach((button) => button.classList.add("secondary-button"));
    el("founderClock").hidden = !synthetic;
    el("founderClockLabel").hidden = !synthetic;
    el("founderOpen").addEventListener("click", async () => {
      try {
        const response = await fetch("/api/founder/lesson");
        if (!response.ok) throw Error("Source unavailable");
        content = await response.json();
        const selection = findCatalogSelection(sourceId,
          "founder-level-civic-classical:study-plans/courses/FCC-K12-founder-level-civic-classical.md",
          "founder-level-civic-classical:objectives/course/fcc-k12/fcc-1-literacy-numeracy");
        if (selection) applyCatalogSelection(selection, { persist: true });
        el("founderContent").hidden = false;
        el("founderLessonTitle").textContent = content.title;
        el("founderObjective").textContent = content.objective;
        el("founderSource").textContent = `${content.reading.sourceRoute} ${content.reading.license}`;
        el("founderReading").textContent = content.reading.text;
        el("founderRubric").textContent = content.rubric;
        render();
      } catch { el("founderContent").hidden = false; el("founderStatus").textContent = "Founder source unavailable; no progress was changed."; }
    });
    el("founderPlan").addEventListener("click", () => act((record) => { if (phase(record) !== "plan") throw Error("Plan already recorded"); record.plan = el("founderRoute").value; }));
    el("founderStudy").addEventListener("click", () => act((record) => { if (phase(record) !== "study") throw Error("Save the plan before study"); record.studied = true; }));
    el("founderCorrect").addEventListener("click", () => act((record) => { if (phase(record) !== "feedback") throw Error("Initial feedback is required"); record.corrected = true; }));
    el("founderAttempt").addEventListener("click", () => act((record) => {
      const stage = phase(record);
      if (!["initial", "retry", "delayed"].includes(stage)) throw Error("No attempt is due");
      if (stage === "delayed" && today() < due(record.attempts.at(-1).date)) throw Error("Delayed review is not due");
      const attempt = { stage, assessmentId: content.forms.find((form) => form.stage === stage).id, date: today(), response: el("founderResponse").value.trim(), score: Number(el("founderScore").value), support: "self-check" };
      record.attempts.push(attempt);
    }));
    el("founderWithdraw").addEventListener("click", () => act((record) => { record.withdrawn = true; }));
    el("founderClear").addEventListener("click", () => {
      const snapshot = stored();
      if (snapshot) { delete snapshot.founderLoop; localStorage.setItem(key(), JSON.stringify(snapshot)); }
      render();
    });
    el("learnerProfileSelect").addEventListener("change", render);
    el("createProfileButton").addEventListener("click", () => setTimeout(render, 0));
  });
})();
