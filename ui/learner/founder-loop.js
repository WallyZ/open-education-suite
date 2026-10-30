/* The existing learner state owns this sequence's local, self-reported evidence. */
(() => {
  const lessonId = "lesson:lesson-g1-cw10-d01";
  const sourceId = "founder-level-civic-classical";
  const synthetic = new URLSearchParams(location.search).get("founderRehearsal") === "1";
  let content;
  let renderedOwner;
  let challenge;
  let closedSources = false;
  let lastSubmission;
  let assessmentControls = [];
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
      challenge = null;
      lastSubmission = null;
      closedSources = false;
      el("founderGradeFields").replaceChildren();
      el("founderGradeStatus").textContent = stored()?.founderAssessment ? "Saved assessment requires server verification." : "Server-scored evidence: none.";
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
  const gradedObjective = "founder-level-civic-classical:objective/lesson-g1-cw10-d01";
  async function assessmentRequest(operation, body) {
    const response = await fetch(`/api/founder/assessment/${operation}`, {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body)
    });
    const result = await response.json();
    if (!response.ok || result.accepted === false) throw Error(result.error || "Assessment unavailable");
    return result;
  }
  function mergeReceipt(snapshot, receipt) {
    const body = receipt.body;
    if (body.learnerId !== snapshot.learnerId || body.lessonId !== lessonId || body.objectiveId !== gradedObjective || body.synthetic !== synthetic) throw Error("Assessment receipt binding rejected");
    const merged = structuredClone(snapshot);
    for (const [field, target] of [["mastery", "objectiveId"], ["reviewQueue", "objectiveId"], ["learningEvents", "objectId"], ["auditLog", "objectiveId"], ["misconceptions", "objectiveId"]]) {
      merged[field] = [...(merged[field] || []).filter((item) => item[target] !== gradedObjective), ...body.state[field]];
    }
    merged.founderAssessment = receipt;
    return merged;
  }
  function unverifiedSnapshot(snapshot) {
    const safe = structuredClone(snapshot);
    for (const [field, target] of [["mastery", "objectiveId"], ["reviewQueue", "objectiveId"], ["learningEvents", "objectId"], ["auditLog", "objectiveId"], ["misconceptions", "objectiveId"]]) {
      safe[field] = (safe[field] || []).filter((item) => item[target] !== gradedObjective);
    }
    return safe;
  }
  async function verifySnapshot(snapshot) {
    if (!snapshot.founderAssessment) {
      for (const [field, target] of [["mastery", "objectiveId"], ["reviewQueue", "objectiveId"], ["learningEvents", "objectId"], ["auditLog", "objectiveId"], ["misconceptions", "objectiveId"]]) {
        if ((snapshot[field] || []).some((item) => item[target] === gradedObjective)) throw Error("Scored evidence requires a server receipt");
      }
      return snapshot;
    }
    const verified = await assessmentRequest("verify", { receipt: snapshot.founderAssessment, learnerId: snapshot.learnerId });
    return mergeReceipt(snapshot, verified);
  }
  function showReceipt(receipt) {
    const result = receipt.body.results.at(-1);
    const mastery = receipt.body.state.mastery[0];
    el("founderGradeStatus").textContent = `${receipt.body.withdrawn ? "Scored assessment withdrawn. " : ""}Server score: ${result.status} (${result.score}). Objective confidence: ${mastery.confidence}. Audit entries: ${receipt.body.state.auditLog.length}. ${receipt.body.synthetic ? "Synthetic rehearsal; no learner outcomes." : "Bounded structured evidence; not whole-course mastery."}`;
  }
  async function acceptReceipt(receipt, learner) {
    if (owner() !== learner) throw Error("Active learner changed during assessment");
    const snapshot = mergeReceipt(stored() || buildLearnerStateSnapshot(), receipt);
    localStorage.setItem(key(), JSON.stringify(snapshot));
    applyLearnerStateSnapshot(snapshot, { assessmentVerified: true });
    showReceipt(receipt);
  }
  async function verifyStored() {
    const learner = owner();
    const snapshot = stored();
    if (snapshot?.founderAssessment) {
      const verified = await verifySnapshot(snapshot);
      await acceptReceipt(verified.founderAssessment, learner);
    }
  }
  function gradeAction(operation) {
    return async () => {
      const controls = [el("founderGradeBegin"), el("founderGradeSubmit"), el("learnerProfileSelect"), el("createProfileButton")];
      const disabled = controls.map((control) => control.disabled);
      controls.forEach((control) => { control.disabled = true; });
      try { await operation(); }
      catch (error) { el("founderGradeStatus").textContent = `Assessment action rejected: ${error.message}`; }
      finally { controls.forEach((control, index) => { control.disabled = disabled[index]; }); }
    };
  }
  function releaseAssessmentControls() {
    for (const [control, property, prior] of assessmentControls) control[property] = prior;
    assessmentControls = [];
  }
  window.openEducationFounderLoop = { validate, render, verifySnapshot, unverifiedSnapshot };
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
        try { await verifyStored(); }
        catch { el("founderGradeStatus").textContent = "Saved assessment could not be verified. No mastery was restored; check the private authority store."; }
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
    el("founderGradeBegin").addEventListener("click", gradeAction(async () => {
      releaseAssessmentControls();
      challenge = null;
      closedSources = false;
      el("founderGradeClose").disabled = true;
      el("founderGradeFields").hidden = true;
      el("founderGradeStatus").textContent = "Preparing assessment...";
      const learner = owner();
      const request = { learnerId: learner, correctionReviewed: el("founderGradeCorrection").checked };
      if (stored()?.founderAssessment) request.receipt = stored().founderAssessment;
      if (synthetic) request.now = today();
      const prepared = await assessmentRequest("begin", request);
      if (owner() !== learner) throw Error("Active learner changed");
      challenge = { ...prepared, learnerId: learner };
      closedSources = false;
      lastSubmission = null;
      el("founderReading").hidden = false;
      el("founderGradeStudy").hidden = false;
      el("founderGradeStudy").textContent = prepared.studyText;
      el("founderGradeFields").replaceChildren();
      for (const field of prepared.fields) {
        const label = document.createElement("label");
        label.htmlFor = `founderGrade-${field.id}`;
        label.textContent = field.label;
        const input = document.createElement(field.kind === "boolean" || Array.isArray(field.kind) ? "select" : "input");
        input.id = label.htmlFor;
        if (input.tagName === "SELECT") {
          const options = field.kind === "boolean" ? [["", "Choose"], ["true", "Yes"], ["false", "No"]] : [["", "Choose"], ...field.kind.map((value) => [value, value.replaceAll("-", " ")])];
          for (const [value, text] of options) input.add(new Option(text, value));
        } else { input.type = field.kind; input.maxLength = 100; }
        el("founderGradeFields").append(label, input);
      }
      el("founderGradeFields").hidden = true;
      el("founderGradeClose").disabled = false;
      el("founderGradeStatus").textContent = `Prepared ${prepared.stage} assessment. Study, then close the sources. No score has been awarded.`;
    }));
    el("founderGradeClose").addEventListener("click", () => {
      if (!challenge) { el("founderGradeStatus").textContent = "Prepare an assessment first."; return; }
      closedSources = true;
      for (const id of ["founderReading", "founderGradeStudy", "founderFeedback", "founderPrompt", "founderHistory", "teacherThread"]) {
        assessmentControls.push([el(id), "hidden", el(id).hidden]);
        el(id).hidden = true;
      }
      for (const id of ["hintButton", "liveTeacherButton", "runSessionButton", "founderOpen", "founderCorrect"]) {
        assessmentControls.push([el(id), "disabled", el(id).disabled]);
        el(id).disabled = true;
      }
      el("founderGradeClose").disabled = true;
      el("founderGradeFields").hidden = false;
      el("founderGradeStatus").textContent = challenge.prompt;
    });
    el("founderGradeSubmit").addEventListener("click", gradeAction(async () => {
      if (!challenge || challenge.learnerId !== owner() || !closedSources) throw Error("Close sources before submitting");
      let request = lastSubmission;
      if (!request) {
        const answers = {};
        for (const field of challenge.fields) {
          const value = el(`founderGrade-${field.id}`).value;
          answers[field.id] = field.kind === "boolean" ? value === "true" ? true : value === "false" ? false : value : field.kind === "number" && /^\d+$/.test(value) ? Number(value) : value;
        }
        request = { learnerId: owner(), token: challenge.token, answers, support: el("founderGradeSupport").value };
      }
      const receipt = await assessmentRequest("grade", request);
      lastSubmission = request;
      await acceptReceipt(receipt, request.learnerId);
      releaseAssessmentControls();
    }));
    el("founderGradeVerify").addEventListener("click", gradeAction(verifyStored));
    el("founderGradeWithdraw").addEventListener("click", gradeAction(async () => {
      const receipt = stored()?.founderAssessment;
      if (!receipt) throw Error("No scored assessment exists");
      const learner = owner();
      await acceptReceipt(await assessmentRequest("withdraw", { learnerId: learner, receipt }), learner);
      releaseAssessmentControls();
    }));
  });
})();
