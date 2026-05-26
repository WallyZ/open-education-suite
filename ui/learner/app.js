const localeConfig = window.openEducationLocale || {
  locale: "en-US",
  dateTime: { dateStyle: "medium", timeStyle: "short" },
  labels: {},
  objectiveNames: {},
  feedback: {}
};

function localize(key, fallback) {
  const value = key.split(".").reduce((current, part) => {
    return current && Object.prototype.hasOwnProperty.call(current, part) ? current[part] : null;
  }, localeConfig);
  return typeof value === "string" ? value : fallback;
}

function applyLocalizedLabels() {
  document.querySelectorAll("[data-l10n]").forEach((element) => {
    element.textContent = localize(element.dataset.l10n, element.textContent);
  });
}

function feedbackText(key, fallback) {
  return localize(`feedback.${key}`, fallback);
}

function formatLocaleDate(value) {
  if (!value) {
    return localize("labels.notScheduled", "Not scheduled");
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return String(value);
  }
  return new Intl.DateTimeFormat(localeConfig.locale || "en-US", localeConfig.dateTime).format(date);
}

function requireSessionData(value, name) {
  if (!value) {
    throw new Error(`Missing ${name}. Run scripts/teaching/export-learner-ui-session.ps1.`);
  }
  return value;
}

function titleCase(value) {
  return String(value || "")
    .split(/[-_\s]+/)
    .filter(Boolean)
    .map((part) => `${part.charAt(0).toUpperCase()}${part.slice(1)}`)
    .join(" ");
}

function lowerFirst(value) {
  const text = String(value || "");
  return `${text.charAt(0).toLowerCase()}${text.slice(1)}`;
}

function getCourseCode(objectiveId) {
  const match = String(objectiveId || "").match(/\/course\/([^/]+)\//);
  return match ? match[1].toUpperCase() : "";
}

function getObjectiveLabel(objectiveId) {
  if (localeConfig.objectiveNames && localeConfig.objectiveNames[objectiveId]) {
    return localeConfig.objectiveNames[objectiveId];
  }
  const slug = String(objectiveId || "").split("/").filter(Boolean).pop() || "objective";
  return titleCase(slug);
}

function formatPreference(value) {
  return titleCase(String(value || "").replace(/-/g, " "));
}

function explainActionReason(action) {
  if (action.reason === "no-mastery-evidence") {
    return "Selected because there is no mastery evidence yet. Begin with a short Socratic check before examples.";
  }
  if (action.reason === "low-confidence") {
    return "Selected because the current objective still needs stronger evidence.";
  }
  return `Selected by the teaching session because ${String(action.reason || "the learner is ready for this step").replace(/-/g, " ")}.`;
}

function buildActionTitle(sessionOutput) {
  const objectiveId = sessionOutput.action.objectiveId;
  const courseCode = getCourseCode(objectiveId);
  const objectiveLabel = getObjectiveLabel(objectiveId).toLowerCase();
  return `Start ${courseCode ? `${courseCode} ` : ""}${objectiveLabel}`;
}

function normalizeLearner(profile) {
  const preferences = profile.preferences || {};
  return {
    preference: formatPreference(preferences.explanationStyle || "adaptive"),
    practice: formatPreference(preferences.practiceMode || "guided"),
    access: formatPreference((profile.accommodations || [])[0] || "standard")
  };
}

function normalizeHints(sessionOutput, source) {
  const hints = (sessionOutput.hintOptions || [])
    .map((hint) => hint.text)
    .filter(Boolean);
  if (hints.length > 0) {
    return hints;
  }
  return [
    `Start from the selected source: ${source.title}.`,
    `Name one concrete player action, one goal, and one feedback signal.`,
    `Use ${source.sourceRepo} evidence before making a design claim.`
  ];
}

function normalizeSource(sessionOutput, lecturePackage) {
  const source = sessionOutput.sourceProvenance || lecturePackage.contentSource || {};
  return {
    sourceId: source.sourceId || "",
    sourceRepo: source.sourceRepo || "",
    sourcePath: source.sourcePath || "",
    title: source.title || "Selected source",
    claim: `${source.title || "The selected source"} was selected by scripts/teaching/start-session.ps1 for ${lowerFirst(getObjectiveLabel(sessionOutput.action.objectiveId))}.`
  };
}

function isPlayableMedia(asset, type) {
  const path = String(asset?.path || "").replace(/\//g, "\\");
  return asset &&
    asset.type === type &&
    ["rendered", "archived"].includes(asset.status) &&
    path.startsWith("var\\lecture-media\\") &&
    /^[a-f0-9]{64}$/i.test(String(asset.sha256 || ""));
}

function mediaPathToUrl(path) {
  const normalized = String(path || "").replace(/\\/g, "/");
  return normalized.startsWith("var/lecture-media/") ? `../../${normalized}` : normalized;
}

function normalizeMediaAsset(asset) {
  if (!asset) {
    return null;
  }
  return {
    assetId: asset.assetId,
    type: asset.type,
    path: asset.path,
    url: mediaPathToUrl(asset.path),
    sha256: asset.sha256,
    status: asset.status,
    requiredForPublish: asset.requiredForPublish === true
  };
}

function normalizeLecture(lecturePackage) {
  const instructor = lecturePackage.generatedInstructor || {};
  const transcript = lecturePackage.transcript || {};
  const adaptiveHooks = lecturePackage.adaptiveHooks || {};
  const media = Array.isArray(lecturePackage.media) ? lecturePackage.media : [];
  const video = media.find((asset) => isPlayableMedia(asset, "video/mp4"));
  const audio = media.find((asset) => isPlayableMedia(asset, "audio/mp4"));
  return {
    packageId: lecturePackage.packageId,
    title: lecturePackage.title,
    durationSeconds: lecturePackage.durationSeconds,
    renderStatus: lecturePackage.renderStatus,
    disclosure: instructor.disclosure || "Generated lecture package.",
    transcript: transcript.text || "",
    citations: lecturePackage.citations || [],
    chapters: lecturePackage.chapters || [],
    checkpoints: adaptiveHooks.checkpoints || [],
    media: {
      video: normalizeMediaAsset(video),
      audio: normalizeMediaAsset(audio)
    }
  };
}

function normalizeMastery(sessionOutput) {
  const mastery = sessionOutput.mastery || [];
  if (mastery.length === 0) {
    return [
      {
        objectiveId: sessionOutput.action.objectiveId,
        label: getObjectiveLabel(sessionOutput.action.objectiveId),
        confidence: 0,
        evidenceCount: 0
      }
    ];
  }
  return mastery.map((item) => ({
    objectiveId: item.objectiveId,
    label: getObjectiveLabel(item.objectiveId),
    confidence: Number(item.confidence) || 0,
    evidenceCount: Number(item.evidenceCount) || 0
  }));
}

function buildSessionFromStartSession(sessionOutput, lecturePackage) {
  const source = normalizeSource(sessionOutput, lecturePackage);
  return {
    learnerId: sessionOutput.learnerId,
    objectiveId: sessionOutput.action.objectiveId,
    action: {
      type: sessionOutput.action.actionType,
      reason: sessionOutput.action.reason,
      title: buildActionTitle(sessionOutput),
      prompt: sessionOutput.prompt
    },
    learner: normalizeLearner(sessionOutput.learnerProfile || {}),
    source,
    lecture: normalizeLecture(lecturePackage),
    mastery: normalizeMastery(sessionOutput),
    reviews: sessionOutput.reviewQueue || [],
    hints: normalizeHints(sessionOutput, source)
  };
}

let currentSessionOutput = requireSessionData(window.openEducationSessionOutput, "openEducationSessionOutput");
let currentLecturePackage = requireSessionData(window.openEducationLecturePackage, "openEducationLecturePackage");
let currentContentCatalog = window.openEducationContentCatalog || { schemaVersion: 1, sources: [] };
let session = buildSessionFromStartSession(currentSessionOutput, currentLecturePackage);

const LEARNER_STATE_STORAGE_KEY = "openEducationLearnerState";
const ASSESSMENT_STORAGE_KEY = "openEducationAssessmentEvidence";

const state = {
  activeView: "lesson",
  hintIndex: 0,
  masteryBoosted: false,
  lecturePlaying: false,
  lecturePosition: 0,
  liveTeacherEnabled: false,
  activeAssessmentMode: "multiple-choice",
  activeSourceId: "",
  activeCourseId: "",
  selectedObjectiveId: ""
};

const elements = {
  body: document.body,
  navItems: Array.from(document.querySelectorAll("[data-view]")),
  panels: Array.from(document.querySelectorAll("[data-panel]")),
  teacherThread: document.getElementById("teacherThread"),
  responseForm: document.getElementById("responseForm"),
  learnerResponse: document.getElementById("learnerResponse"),
  runSessionButton: document.getElementById("runSessionButton"),
  sessionBridgeLog: document.getElementById("sessionBridgeLog"),
  liveTeacherButton: document.getElementById("liveTeacherButton"),
  liveTeacherLog: document.getElementById("liveTeacherLog"),
  hintButton: document.getElementById("hintButton"),
  completeButton: document.getElementById("completeButton"),
  focusToggle: document.getElementById("focusToggle"),
  contrastToggle: document.getElementById("contrastToggle"),
  learnerTitle: document.getElementById("learner-title"),
  nextActionTitle: document.getElementById("next-action-title"),
  courseTitle: document.getElementById("course-title"),
  masteryList: document.getElementById("masteryList"),
  reviewQueue: document.getElementById("reviewQueue"),
  analyticsSummary: document.getElementById("analyticsSummary"),
  analyticsEvidenceList: document.getElementById("analyticsEvidenceList"),
  analyticsLog: document.getElementById("analyticsLog"),
  handoffBlockers: document.getElementById("handoffBlockers"),
  handoffInterventions: document.getElementById("handoffInterventions"),
  contentHealthList: document.getElementById("contentHealthList"),
  handoffLog: document.getElementById("handoffLog"),
  citationBlock: document.getElementById("citationBlock"),
  journalEntry: document.getElementById("journalEntry"),
  journalLog: document.getElementById("journalLog"),
  saveJournalButton: document.getElementById("saveJournalButton"),
  masteryValue: document.getElementById("masteryValue"),
  reviewValue: document.getElementById("reviewValue"),
  objectiveId: document.getElementById("objectiveId"),
  actionReason: document.getElementById("actionReason"),
  sourcePill: document.getElementById("sourcePill"),
  sourceSelect: document.getElementById("sourceSelect"),
  courseSelect: document.getElementById("courseSelect"),
  objectiveList: document.getElementById("objectiveList"),
  courseNavigationLog: document.getElementById("courseNavigationLog"),
  lectureFrame: document.getElementById("lectureFrame"),
  lectureStatusPill: document.getElementById("lectureStatusPill"),
  lectureDisclosure: document.getElementById("lectureDisclosure"),
  lecturePlayButton: document.getElementById("lecturePlayButton"),
  lectureProgress: document.getElementById("lectureProgress"),
  lecturePosition: document.getElementById("lecturePosition"),
  chapterList: document.getElementById("chapterList"),
  lectureTranscript: document.getElementById("lectureTranscript"),
  lectureCitations: document.getElementById("lectureCitations"),
  lectureCheckpoints: document.getElementById("lectureCheckpoints"),
  checkpointLog: document.getElementById("checkpointLog"),
  assessmentModeControls: document.getElementById("assessmentModeControls"),
  assessmentRenderSurface: document.getElementById("assessmentRenderSurface"),
  saveAssessmentButton: document.getElementById("saveAssessmentButton"),
  assessmentLog: document.getElementById("assessmentLog"),
  preferenceValue: document.getElementById("preferenceValue"),
  practiceValue: document.getElementById("practiceValue"),
  accessValue: document.getElementById("accessValue"),
  saveStateButton: document.getElementById("saveStateButton"),
  exportStateButton: document.getElementById("exportStateButton"),
  importStateButton: document.getElementById("importStateButton"),
  syncPreviewButton: document.getElementById("syncPreviewButton"),
  stateExchange: document.getElementById("stateExchange"),
  stateSyncLog: document.getElementById("stateSyncLog")
};

const assessmentModes = [
  {
    mode: "multiple-choice",
    label: "Multiple choice",
    prompt: "Which debugger command enters the called function?",
    options: ["Step over", "Step into", "Step out", "Continue"]
  },
  {
    mode: "short-answer",
    label: "Short answer",
    prompt: "Explain how one feedback signal changes a player's next decision."
  },
  {
    mode: "project-rubric",
    label: "Project rubric",
    prompt: "Prototype checkpoint rubric",
    criteria: ["Objective evidence", "Clear before/after change", "Playtest observation", "Next revision"]
  },
  {
    mode: "oral-explained-answer",
    label: "Oral explained answer",
    prompt: "Explain one design choice aloud, then paste or type the transcript."
  }
];

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function setView(view) {
  state.activeView = view;
  elements.navItems.forEach((item) => {
    const isActive = item.dataset.view === view;
    item.classList.toggle("is-active", isActive);
    item.setAttribute("aria-current", isActive ? "page" : "false");
  });
  elements.panels.forEach((panel) => {
    panel.classList.toggle("is-visible", panel.dataset.panel === view);
  });
}

function addMessage(kind, label, text) {
  const message = document.createElement("article");
  message.className = `message is-${kind}`;
  message.innerHTML = `<p class="eyebrow">${escapeHtml(label)}</p><p>${escapeHtml(text)}</p>`;
  elements.teacherThread.appendChild(message);
}

function renderThread() {
  elements.teacherThread.innerHTML = "";
  addMessage("system", "Next action", session.action.prompt);
  addMessage(
    "system",
    "Why",
    explainActionReason(session.action)
  );
}

function renderMastery() {
  const total = session.mastery.reduce((sum, item) => sum + item.confidence, 0);
  const average = session.mastery.length ? Math.round((total / session.mastery.length) * 100) : 0;
  elements.masteryValue.textContent = `${Math.round(session.mastery[0].confidence * 100)}%`;
  elements.reviewValue.textContent = String(session.reviews.length);
  elements.masteryList.innerHTML = session.mastery
    .map((item) => {
      const pct = Math.round(item.confidence * 100);
      return `
        <div class="mastery-row">
          <div>
            <strong>${escapeHtml(item.label)}</strong>
            <div class="progress-track" aria-label="${escapeHtml(item.label)} confidence ${pct} percent">
              <div class="progress-fill" style="--value: ${pct}%"></div>
            </div>
            <small>${escapeHtml(item.objectiveId)}</small>
          </div>
          <strong>${pct}%</strong>
        </div>
      `;
    })
    .join("");

  if (session.reviews.length === 0) {
    elements.reviewQueue.innerHTML = "<li>No due reviews for this objective.</li>";
  } else {
    elements.reviewQueue.innerHTML = session.reviews
      .map((review) => `<li>${escapeHtml(getObjectiveLabel(review.objectiveId))} due ${escapeHtml(formatLocaleDate(review.dueAt))}</li>`)
      .join("");
  }

  elements.actionReason.textContent = explainActionReason(session.action);
}

function renderLearnerAnalytics() {
  const evidenceCount = session.mastery.reduce((sum, item) => sum + item.evidenceCount, 0);
  const averageConfidence = session.mastery.length
    ? Math.round((session.mastery.reduce((sum, item) => sum + item.confidence, 0) / session.mastery.length) * 100)
    : 0;
  const sourceCount = getCatalogSources().length;
  elements.analyticsSummary.innerHTML = [
    ["Evidence items", evidenceCount, "Durable mastery signals"],
    ["Average confidence", `${averageConfidence}%`, "Across active goals"],
    ["Due reviews", session.reviews.length, "Scheduled practice"],
    ["Content sources", sourceCount, "Ingested catalogs"]
  ].map(([label, value, detail]) => `
    <div class="analytics-card">
      <span class="metric-label">${escapeHtml(label)}</span>
      <strong>${escapeHtml(value)}</strong>
      <span class="metric-label">${escapeHtml(detail)}</span>
    </div>
  `).join("");

  elements.analyticsEvidenceList.innerHTML = session.mastery
    .map((item) => `
      <li>
        <strong>${escapeHtml(item.label)}</strong>:
        ${escapeHtml(String(item.evidenceCount))} evidence items, ${escapeHtml(String(Math.round(item.confidence * 100)))}% confidence.
      </li>
    `)
    .join("");
  elements.analyticsLog.textContent =
    `Evidence only. No clickstream or time-spent tracking. Current source: ${session.source.sourceRepo}.`;
}

function renderList(element, items) {
  element.innerHTML = items.map((item) => `<li>${escapeHtml(item)}</li>`).join("");
}

function renderOperatorHandoff() {
  const lowEvidence = session.mastery.filter((item) => item.confidence < 0.5 || item.evidenceCount === 0);
  const blockers = lowEvidence.map((item) =>
    `${item.label}: ${item.evidenceCount} evidence items and ${Math.round(item.confidence * 100)}% confidence.`
  );
  if (session.reviews.length > 0) {
    blockers.push(`${session.reviews.length} due reviews need scheduling before expanding scope.`);
  }
  if (blockers.length === 0) {
    blockers.push("No active blockers from the current local learner state.");
  }

  const interventions = [];
  if (session.action.reason === "no-mastery-evidence") {
    interventions.push("Start with guided practice and collect one assessment artifact before mastery changes.");
  }
  if (session.action.reason === "low-confidence") {
    interventions.push("Use a worked example, then ask for an unaided retry on the same objective.");
  }
  interventions.push(`Keep the next intervention grounded in ${session.source.title}.`);
  interventions.push("Review any saved evidence proposals before writing durable learner-state updates.");

  const activeSource = getCatalogSources().find((source) => source.sourceId === session.source.sourceId);
  const health = [
    `${session.source.sourceRepo}: ${activeSource ? activeSource.objectCount : "unknown"} ingested objects available.`,
    `Lecture QA status: ${(currentLecturePackage.qaStatus || {}).status || "unknown"}.`,
    `License audit status: ${(currentLecturePackage.licenseAudit || {}).status || "unknown"}.`,
    `Current source path: ${session.source.sourcePath}.`
  ];

  renderList(elements.handoffBlockers, blockers);
  renderList(elements.handoffInterventions, interventions);
  renderList(elements.contentHealthList, health);
  elements.handoffLog.textContent = "Operator review only. No learner-state mutation.";
}

function renderCitations() {
  elements.citationBlock.innerHTML = `
    <div class="citation">
      <p class="eyebrow">Citation</p>
      <strong>${escapeHtml(session.source.title)}</strong>
      <p>${escapeHtml(session.source.claim)}</p>
      <code>${escapeHtml(session.source.sourceRepo)} / ${escapeHtml(session.source.sourcePath)}</code>
    </div>
  `;
}

function renderSession() {
  elements.learnerTitle.textContent = session.learnerId;
  elements.nextActionTitle.textContent = session.action.title;
  elements.courseTitle.textContent = session.source.title;
  elements.objectiveId.textContent = session.objectiveId;
  elements.sourcePill.textContent = getCourseCode(session.objectiveId) || session.source.title;
  elements.preferenceValue.textContent = session.learner.preference;
  elements.practiceValue.textContent = session.learner.practice;
  elements.accessValue.textContent = session.learner.access;
  renderThread();
  renderMastery();
  renderLearnerAnalytics();
  renderOperatorHandoff();
  renderCitations();
  renderLecture();
  renderAssessment();
  renderCourseNavigation();
}

function getCatalogSources() {
  return Array.isArray(currentContentCatalog.sources) ? currentContentCatalog.sources : [];
}

function getSelectedSource(sources) {
  return sources.find((source) => source.sourceId === state.activeSourceId) ||
    sources.find((source) => source.sourceId === session.source.sourceId) ||
    sources[0] ||
    null;
}

function getSelectedCourse(source) {
  const courses = Array.isArray(source.courses) ? source.courses : [];
  return courses.find((course) => course.id === state.activeCourseId) ||
    courses.find((course) => course.sourcePath === session.source.sourcePath) ||
    courses[0] ||
    null;
}

function renderCourseNavigation() {
  const sources = getCatalogSources();
  if (sources.length === 0) {
    elements.sourceSelect.innerHTML = '<option value="">No content sources</option>';
    elements.courseSelect.innerHTML = '<option value="">No courses</option>';
    elements.objectiveList.textContent = "No ingested objectives available.";
    elements.courseNavigationLog.textContent = "Content catalog is unavailable.";
    return;
  }

  const selectedSource = getSelectedSource(sources);
  state.activeSourceId = selectedSource.sourceId;
  const selectedCourse = getSelectedCourse(selectedSource);
  state.activeCourseId = selectedCourse ? selectedCourse.id : "";

  elements.sourceSelect.innerHTML = sources
    .map((source) => `<option value="${escapeHtml(source.sourceId)}">${escapeHtml(source.title)}</option>`)
    .join("");
  elements.sourceSelect.value = state.activeSourceId;

  const courses = Array.isArray(selectedSource.courses) ? selectedSource.courses : [];
  if (courses.length > 0) {
    elements.courseSelect.disabled = false;
    elements.courseSelect.innerHTML = courses
      .map((course) => `<option value="${escapeHtml(course.id)}">${escapeHtml(course.title)}</option>`)
      .join("");
    elements.courseSelect.value = state.activeCourseId;
  }
  else {
    elements.courseSelect.disabled = true;
    elements.courseSelect.innerHTML = '<option value="">No courses declared</option>';
  }

  const objectives = selectedCourse && Array.isArray(selectedCourse.objectives)
    ? selectedCourse.objectives
    : selectedSource.objectives || [];
  if (objectives.length === 0) {
    elements.objectiveList.textContent = "No objectives declared yet.";
  }
  else {
    elements.objectiveList.innerHTML = objectives
      .map((objective) => {
        const isActive = objective.objectiveId === session.objectiveId ||
          objective.objectiveId === state.selectedObjectiveId;
        return `
          <button class="objective-chip" type="button" data-objective-id="${escapeHtml(objective.objectiveId)}" aria-pressed="${isActive}">
            ${escapeHtml(objective.label)}
          </button>
        `;
      })
      .join("");
  }

  const courseText = selectedCourse ? selectedCourse.title : selectedSource.title;
  elements.courseNavigationLog.textContent =
    `Catalog view: ${courseText}. Navigation is read-only until a new session is started.`;
}

function renderAssessmentControls() {
  elements.assessmentModeControls.innerHTML = assessmentModes
    .map((mode) => `
      <button class="secondary-button assessment-mode-button" type="button" data-assessment-mode="${escapeHtml(mode.mode)}" aria-pressed="${mode.mode === state.activeAssessmentMode}">
        ${escapeHtml(mode.label)}
      </button>
    `)
    .join("");
}

function renderAssessment() {
  const mode = assessmentModes.find((item) => item.mode === state.activeAssessmentMode) || assessmentModes[0];
  renderAssessmentControls();
  if (mode.mode === "multiple-choice") {
    elements.assessmentRenderSurface.innerHTML = `
      <article class="assessment-card">
        <p class="eyebrow">${escapeHtml(mode.label)}</p>
        <h3>${escapeHtml(mode.prompt)}</h3>
        <div class="assessment-options">
          ${mode.options.map((option, index) => {
            const id = `mcq-${index}`;
            return `
              <label class="assessment-option" for="${id}">
                <input id="${id}" name="assessmentMultipleChoice" type="radio" value="${escapeHtml(option)}">
                <span>${escapeHtml(option)}</span>
              </label>
            `;
          }).join("")}
        </div>
      </article>
    `;
    return;
  }

  if (mode.mode === "short-answer") {
    elements.assessmentRenderSurface.innerHTML = `
      <article class="assessment-card">
        <p class="eyebrow">${escapeHtml(mode.label)}</p>
        <label for="assessmentShortAnswer">${escapeHtml(mode.prompt)}</label>
        <textarea id="assessmentShortAnswer" rows="5"></textarea>
      </article>
    `;
    return;
  }

  if (mode.mode === "project-rubric") {
    elements.assessmentRenderSurface.innerHTML = `
      <article class="assessment-card">
        <p class="eyebrow">${escapeHtml(mode.label)}</p>
        <h3>${escapeHtml(mode.prompt)}</h3>
        <div class="assessment-options">
          ${mode.criteria.map((criterion, index) => {
            const id = `rubric-${index}`;
            return `
              <label class="assessment-option" for="${id}">
                <input id="${id}" type="checkbox" value="${escapeHtml(criterion)}">
                <span>${escapeHtml(criterion)}</span>
              </label>
            `;
          }).join("")}
        </div>
      </article>
    `;
    return;
  }

  elements.assessmentRenderSurface.innerHTML = `
    <article class="assessment-card">
      <p class="eyebrow">${escapeHtml(mode.label)}</p>
      <label for="oralExplanation">${escapeHtml(mode.prompt)}</label>
      <textarea id="oralExplanation" rows="5"></textarea>
    </article>
  `;
}

function collectAssessmentResponse(mode) {
  if (mode.mode === "multiple-choice") {
    const selected = document.querySelector("input[name='assessmentMultipleChoice']:checked");
    return selected ? selected.value : "";
  }
  if (mode.mode === "short-answer") {
    return document.getElementById("assessmentShortAnswer").value.trim();
  }
  if (mode.mode === "project-rubric") {
    return Array.from(document.querySelectorAll(".assessment-option input[type='checkbox']:checked"))
      .map((item) => item.value);
  }
  return document.getElementById("oralExplanation").value.trim();
}

function saveAssessmentEvidence() {
  const mode = assessmentModes.find((item) => item.mode === state.activeAssessmentMode) || assessmentModes[0];
  const response = collectAssessmentResponse(mode);
  if ((Array.isArray(response) && response.length === 0) || (!Array.isArray(response) && !response)) {
    elements.assessmentLog.textContent = feedbackText("assessmentEmpty", "Assessment response is empty.");
    return;
  }
  const saved = JSON.parse(localStorage.getItem(ASSESSMENT_STORAGE_KEY) || "[]");
  saved.unshift({
    at: new Date().toISOString(),
    objectiveId: session.objectiveId,
    sourceRepo: session.source.sourceRepo,
    sourcePath: session.source.sourcePath,
    mode: mode.mode,
    prompt: mode.prompt,
    response,
    masteryImpact: "proposal-only"
  });
  localStorage.setItem(ASSESSMENT_STORAGE_KEY, JSON.stringify(saved.slice(0, 20)));
  elements.assessmentLog.textContent = feedbackText("assessmentSaved", "Assessment response saved locally as an evidence proposal.");
}

function formatTime(totalSeconds) {
  const safeSeconds = Math.max(0, Math.min(session.lecture.durationSeconds, Number(totalSeconds) || 0));
  const minutes = Math.floor(safeSeconds / 60);
  const seconds = String(safeSeconds % 60).padStart(2, "0");
  return `${minutes}:${seconds}`;
}

function saveLectureResume() {
  localStorage.setItem(
    "openEducationLectureResume",
    JSON.stringify({
      packageId: session.lecture.packageId,
      positionSeconds: state.lecturePosition
    })
  );
}

function getLectureVideo() {
  return document.getElementById("lectureVideo");
}

function setLecturePosition(nextPosition, shouldSave = true) {
  state.lecturePosition = Math.max(
    0,
    Math.min(session.lecture.durationSeconds, Number(nextPosition) || 0)
  );
  elements.lectureProgress.value = String(state.lecturePosition);
  elements.lecturePosition.textContent = `${formatTime(state.lecturePosition)} / ${formatTime(session.lecture.durationSeconds)}`;
  const lectureVideo = getLectureVideo();
  if (lectureVideo && Math.abs(lectureVideo.currentTime - state.lecturePosition) > 1) {
    lectureVideo.currentTime = state.lecturePosition;
  }

  elements.chapterList.querySelectorAll(".chapter-button").forEach((button) => {
    const start = Number(button.dataset.startSecond);
    const nextChapter = session.lecture.chapters.find((chapter) => chapter.startSecond > start);
    const isCurrent =
      state.lecturePosition >= start &&
      (!nextChapter || state.lecturePosition < nextChapter.startSecond);
    button.setAttribute("aria-current", isCurrent ? "true" : "false");
  });

  if (shouldSave) {
    saveLectureResume();
  }
}

function toggleLecturePlayback() {
  state.lecturePlaying = !state.lecturePlaying;
  elements.lecturePlayButton.setAttribute("aria-pressed", String(state.lecturePlaying));
  elements.lecturePlayButton.textContent = state.lecturePlaying ? "Pause lecture" : "Play lecture";
  const lectureVideo = getLectureVideo();
  if (!lectureVideo) {
    return;
  }
  if (state.lecturePlaying) {
    lectureVideo.currentTime = state.lecturePosition;
    lectureVideo.play().catch(() => {});
  } else {
    lectureVideo.pause();
  }
}

function renderLectureCitations() {
  elements.lectureCitations.innerHTML = session.lecture.citations
    .map(
      (citation) => `
        <div class="citation">
          <p class="eyebrow">${escapeHtml(citation.citationId)}</p>
          <p>${escapeHtml(citation.claim)}</p>
          <code>${escapeHtml(citation.sourceRepo)} / ${escapeHtml(citation.sourcePath)}</code>
        </div>
      `
    )
    .join("");
}

function renderLectureMediaFrame() {
  const video = session.lecture.media.video;
  if (!video) {
    elements.lectureFrame.setAttribute("role", "img");
    elements.lectureFrame.setAttribute("aria-label", "Generated instructor beside a paper prototype labeled verb, goal, and feedback.");
    elements.lectureFrame.innerHTML = `
      <div>
        <p class="eyebrow">Instructor video</p>
        <strong id="lectureFrameTitle">Synthetic instructor preview</strong>
        <p id="lectureDisclosure">${escapeHtml(session.lecture.disclosure)}</p>
      </div>
    `;
    elements.lectureDisclosure = document.getElementById("lectureDisclosure");
    return;
  }

  elements.lectureFrame.removeAttribute("role");
  elements.lectureFrame.setAttribute("aria-label", "Rendered generated lecture video.");
  elements.lectureFrame.innerHTML = `
    <video id="lectureVideo" class="lecture-video" controls preload="metadata" data-asset-id="${escapeHtml(video.assetId)}" data-sha256="${escapeHtml(video.sha256)}">
      <source src="${escapeHtml(video.url)}" type="${escapeHtml(video.type)}">
    </video>
    <p class="lecture-media-meta">
      Archived media SHA-256 <code>${escapeHtml(video.sha256)}</code>
    </p>
    <p id="lectureDisclosure">${escapeHtml(session.lecture.disclosure)}</p>
  `;
  elements.lectureDisclosure = document.getElementById("lectureDisclosure");
}

function renderLecture() {
  elements.lectureStatusPill.textContent = session.lecture.renderStatus;
  renderLectureMediaFrame();
  elements.lectureTranscript.textContent = session.lecture.transcript;
  elements.lectureProgress.max = String(session.lecture.durationSeconds);

  const savedResume = JSON.parse(localStorage.getItem("openEducationLectureResume") || "null");
  if (savedResume && savedResume.packageId === session.lecture.packageId) {
    state.lecturePosition = Number(savedResume.positionSeconds) || 0;
  }

  elements.chapterList.innerHTML = session.lecture.chapters
    .map(
      (chapter) => `
        <button class="secondary-button chapter-button" type="button" data-start-second="${chapter.startSecond}">
          <span>${escapeHtml(chapter.title)}</span>
          <span>${formatTime(chapter.startSecond)}</span>
        </button>
      `
    )
    .join("");

  elements.lectureCheckpoints.innerHTML = session.lecture.checkpoints
    .map(
      (checkpoint) => `
        <article class="checkpoint-card">
          <p class="eyebrow">${formatTime(checkpoint.timeSecond)}</p>
          <label for="checkpoint-${escapeHtml(checkpoint.checkpointId)}">${escapeHtml(checkpoint.prompt)}</label>
          <textarea id="checkpoint-${escapeHtml(checkpoint.checkpointId)}" rows="3"></textarea>
          <button class="secondary-button" type="button" data-checkpoint-save="${escapeHtml(checkpoint.checkpointId)}">Save checkpoint</button>
        </article>
      `
    )
    .join("");

  renderLectureCitations();
  setLecturePosition(state.lecturePosition, false);
}

function safeEventIdPart(value) {
  return String(value || "")
    .replace(/[^a-z0-9]+/gi, "-")
    .replace(/^-|-$/g, "")
    .toLowerCase();
}

function buildCheckpointEvidence(checkpoint, text) {
  return {
    schemaVersion: 1,
    learnerId: session.learnerId,
    packageId: session.lecture.packageId,
    objectiveId: session.objectiveId,
    checkpointId: checkpoint.checkpointId,
    prompt: checkpoint.prompt,
    response: text,
    evidenceType: checkpoint.evidenceType || "lecture-checkpoint",
    masteryImpact: checkpoint.masteryImpact || "proposal-only",
    submittedAt: new Date().toISOString()
  };
}

function appendCheckpointEvidenceToLearnerState(evidence) {
  const snapshot = readSavedLearnerState();
  const mastery = (snapshot.mastery || []).find((item) => item.objectiveId === evidence.objectiveId);
  const oldConfidence = Number(mastery?.confidence || 0);
  const eventId = `evt-${evidence.submittedAt.replace(/[^0-9]/g, "").slice(0, 14)}-${safeEventIdPart(evidence.checkpointId)}`;

  snapshot.learningEvents = snapshot.learningEvents || [];
  snapshot.auditLog = snapshot.auditLog || [];
  snapshot.learningEvents.unshift({
    eventId,
    learnerId: snapshot.learnerId,
    verb: "lecture_checkpoint_submitted",
    objectId: evidence.objectiveId,
    occurredAt: evidence.submittedAt,
    result: {
      success: null,
      score: null,
      evidenceType: evidence.evidenceType,
      masteryImpact: evidence.masteryImpact,
      responseLength: evidence.response.length
    },
    xapiCandidate: {
      actor: snapshot.learnerId,
      verb: "answered",
      object: evidence.checkpointId,
      result: {
        response: "stored-locally",
        masteryImpact: evidence.masteryImpact
      },
      context: {
        packageId: evidence.packageId,
        objectiveId: evidence.objectiveId
      }
    }
  });
  snapshot.auditLog.unshift({
    at: evidence.submittedAt,
    objectiveId: evidence.objectiveId,
    oldConfidence,
    newConfidence: oldConfidence,
    evidenceSource: "lecture-checkpoint",
    reason: `lecture-checkpoint:${evidence.packageId}:${evidence.checkpointId}:proposal-only`
  });
  localStorage.setItem(LEARNER_STATE_STORAGE_KEY, JSON.stringify(snapshot, null, 2));
}

function saveCheckpoint(checkpointId) {
  const checkpoint = session.lecture.checkpoints.find((item) => item.checkpointId === checkpointId);
  const input = document.getElementById(`checkpoint-${checkpointId}`);
  const text = input ? input.value.trim() : "";
  if (!checkpoint || !text) {
    elements.checkpointLog.textContent = feedbackText("checkpointEmpty", "Checkpoint answer is empty.");
    return;
  }

  const saved = JSON.parse(localStorage.getItem("openEducationLectureCheckpoints") || "[]");
  const evidence = buildCheckpointEvidence(checkpoint, text);
  saved.unshift(evidence);
  appendCheckpointEvidenceToLearnerState(evidence);
  localStorage.setItem("openEducationLectureCheckpoints", JSON.stringify(saved.slice(0, 20)));
  input.value = "";
  elements.checkpointLog.textContent = feedbackText("checkpointSaved", "Checkpoint saved to learner state as an evidence proposal.");
}

function persistJournal() {
  const text = elements.journalEntry.value.trim();
  if (!text) {
    elements.journalLog.textContent = feedbackText("journalEmpty", "Journal is empty.");
    return;
  }
  const saved = JSON.parse(localStorage.getItem("openEducationLearnerJournal") || "[]");
  saved.unshift({
    at: new Date().toISOString(),
    objectiveId: session.objectiveId,
    text
  });
  localStorage.setItem("openEducationLearnerJournal", JSON.stringify(saved.slice(0, 10)));
  elements.journalEntry.value = "";
  elements.journalLog.textContent = feedbackText("journalSaved", "Journal saved locally.");
}

function getStoredLearnerState() {
  const raw = localStorage.getItem(LEARNER_STATE_STORAGE_KEY);
  if (!raw) {
    return null;
  }
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function buildLearnerStateSnapshot() {
  const profile = currentSessionOutput.learnerProfile || {};
  const saved = getStoredLearnerState();
  return {
    schemaVersion: 1,
    learnerId: currentSessionOutput.learnerId || session.learnerId,
    profile: {
      learnerId: profile.learnerId || currentSessionOutput.learnerId || session.learnerId,
      goals: profile.goals || [session.objectiveId],
      constraints: profile.constraints || [],
      preferences: profile.preferences || {},
      accommodations: profile.accommodations || [],
      priorExperience: profile.priorExperience || []
    },
    mastery: session.mastery.map((item) => ({
      objectiveId: item.objectiveId,
      confidence: item.confidence,
      lastEvidenceAt: null,
      evidenceCount: item.evidenceCount,
      evidenceSources: []
    })),
    misconceptions: [],
    reviewQueue: session.reviews,
    learningEvents: saved?.learningEvents || [],
    auditLog: saved?.auditLog || [],
    privacy: {
      piiPolicy: "fixtures-use-non-identifying-ids",
      redactionFields: ["profile.accommodations", "profile.constraints"],
      localOnly: true
    },
    sync: {
      mode: "local",
      lastSyncedAt: null,
      conflictPolicy: "append-events-and-recompute-mastery"
    }
  };
}

function readSavedLearnerState() {
  return getStoredLearnerState() || buildLearnerStateSnapshot();
}

function loadSavedLearnerState() {
  const raw = localStorage.getItem(LEARNER_STATE_STORAGE_KEY);
  if (!raw) {
    return false;
  }
  try {
    applyLearnerStateSnapshot(JSON.parse(raw));
    elements.stateSyncLog.textContent = "Learner state loaded locally.";
    return true;
  }
  catch (error) {
    elements.stateSyncLog.textContent = "Saved learner state was rejected.";
    return false;
  }
}

function parseLearnerStateText(text) {
  const parsed = JSON.parse(text);
  const candidate = parsed && parsed.state ? parsed.state : parsed;
  if (!candidate || candidate.schemaVersion !== 1 || !candidate.learnerId || !candidate.profile) {
    throw new Error("Learner state import must use schemaVersion 1 and include learnerId/profile.");
  }
  return candidate;
}

function applyLearnerStateSnapshot(snapshot) {
  currentSessionOutput.learnerId = snapshot.learnerId;
  currentSessionOutput.learnerProfile = snapshot.profile;
  currentSessionOutput.mastery = snapshot.mastery || [];
  currentSessionOutput.reviewQueue = snapshot.reviewQueue || [];
  if (currentSessionOutput.action) {
    currentSessionOutput.action.learnerId = snapshot.learnerId;
  }
  session = buildSessionFromStartSession(currentSessionOutput, currentLecturePackage);
  renderSession();
}

function saveLearnerState() {
  const snapshot = buildLearnerStateSnapshot();
  localStorage.setItem(LEARNER_STATE_STORAGE_KEY, JSON.stringify(snapshot, null, 2));
  elements.stateSyncLog.textContent = feedbackText("stateSaved", "Learner state saved locally.");
}

function exportLearnerState() {
  const snapshot = readSavedLearnerState();
  elements.stateExchange.value = JSON.stringify(snapshot, null, 2);
  elements.stateSyncLog.textContent = feedbackText("stateExportReady", "Learner state export ready.");
}

function importLearnerState() {
  try {
    const snapshot = parseLearnerStateText(elements.stateExchange.value.trim());
    localStorage.setItem(LEARNER_STATE_STORAGE_KEY, JSON.stringify(snapshot, null, 2));
    elements.stateSyncLog.textContent = feedbackText("stateImported", "Learner state imported locally.");
    try {
      applyLearnerStateSnapshot(snapshot);
    }
    catch (error) {
      elements.stateSyncLog.textContent = feedbackText("stateImported", "Learner state imported locally.");
    }
  }
  catch (error) {
    elements.stateSyncLog.textContent = feedbackText("stateImportRejected", "Learner state import rejected.");
  }
}

function previewLearnerStateSync() {
  try {
    const incoming = parseLearnerStateText(elements.stateExchange.value.trim());
    const saved = readSavedLearnerState();
    const savedEventIds = new Set((saved.learningEvents || []).map((event) => event.eventId).filter(Boolean));
    const incomingEvents = incoming.learningEvents || [];
    const newEventCount = incomingEvents.filter((event) => !savedEventIds.has(event.eventId)).length;
    const masteryConflicts = (incoming.mastery || []).filter((incomingMastery) =>
      (saved.mastery || []).some((savedMastery) =>
        savedMastery.objectiveId === incomingMastery.objectiveId &&
        savedMastery.confidence !== incomingMastery.confidence
      )
    ).length;
    elements.stateSyncLog.textContent =
      `Sync preview: ${newEventCount} new events, ${masteryConflicts} mastery conflicts, merge policy append-events-and-recompute-mastery. No state was changed.`;
  }
  catch (error) {
    elements.stateSyncLog.textContent = "Sync preview rejected invalid learner state.";
  }
}

async function runDeterministicSessionTurn() {
  elements.runSessionButton.disabled = true;
  elements.sessionBridgeLog.textContent = "Session bridge request sent.";
  try {
    const response = await fetch("/api/session/start", { method: "POST" });
    if (!response.ok) {
      throw new Error(`bridge returned ${response.status}`);
    }
    const payload = await response.json();
    currentSessionOutput = payload.session;
    currentLecturePackage = payload.lecturePackage;
    currentContentCatalog = payload.contentCatalog || currentContentCatalog;
    session = buildSessionFromStartSession(currentSessionOutput, currentLecturePackage);
    state.hintIndex = 0;
    state.masteryBoosted = false;
    state.activeSourceId = "";
    state.activeCourseId = "";
    state.selectedObjectiveId = "";
    renderSession();
    elements.sessionBridgeLog.textContent =
      "Session bridge request sent. Session refreshed from local deterministic bridge.";
  }
  catch (error) {
    elements.sessionBridgeLog.textContent =
      "Session bridge request sent. Local deterministic bridge is not running. Start scripts/teaching/learner_ui_bridge_server.py and try again.";
  }
  finally {
    elements.runSessionButton.disabled = false;
  }
}

async function refreshLiveTeacherStatus() {
  elements.liveTeacherButton.disabled = true;
  elements.liveTeacherLog.textContent = "Checking live teacher setting...";
  try {
    const response = await fetch("/api/teacher/live/status", { method: "GET" });
    if (!response.ok) {
      throw new Error(`status returned ${response.status}`);
    }
    const payload = await response.json();
    state.liveTeacherEnabled = payload.enabled === true;
    elements.liveTeacherButton.disabled = !state.liveTeacherEnabled;
    elements.liveTeacherLog.textContent = state.liveTeacherEnabled
      ? "Live AI teacher enabled by operator setting."
      : "Live AI teacher disabled by operator setting.";
  }
  catch (error) {
    state.liveTeacherEnabled = false;
    elements.liveTeacherButton.disabled = false;
    elements.liveTeacherLog.textContent = "Live AI teacher requires the local bridge server.";
  }
}

async function invokeLiveTeacher() {
  elements.liveTeacherButton.disabled = true;
  elements.liveTeacherLog.textContent = "Checking live teacher setting...";
  try {
    const response = await fetch("/api/teacher/live", { method: "POST" });
    const payload = await response.json();
    if (response.status === 403 || payload.error === "live-ai-disabled") {
      state.liveTeacherEnabled = false;
      elements.liveTeacherLog.textContent = "Live AI teacher disabled by operator setting.";
      return;
    }
    if (!response.ok) {
      throw new Error(payload.message || `live teacher returned ${response.status}`);
    }
    if (payload.output && payload.output.response) {
      addMessage("system", "Live teacher", payload.output.response);
    }
    elements.liveTeacherLog.textContent = "Live AI teacher response received. Review citations before treating it as evidence.";
  }
  catch (error) {
    elements.liveTeacherLog.textContent = "Live AI teacher invocation failed before a learner response was shown.";
  }
  finally {
    elements.liveTeacherButton.disabled = !state.liveTeacherEnabled;
  }
}

function submitResponse(event) {
  event.preventDefault();
  const text = elements.learnerResponse.value.trim();
  if (!text) {
    addMessage("system", "Check", "Write a short response before submitting.");
    return;
  }
  addMessage("learner", "Learner", text);
  addMessage(
    "system",
    "Teacher",
    "Good start. Now sort those words into actions, goals, constraints, and feedback. That turns vocabulary into design evidence."
  );
  elements.learnerResponse.value = "";
}

function showHint() {
  const hint = session.hints[state.hintIndex] || session.hints[session.hints.length - 1];
  state.hintIndex = Math.min(state.hintIndex + 1, session.hints.length);
  addMessage("system", "Hint", hint);
}

function markComplete() {
  if (!state.masteryBoosted) {
    session.mastery[0].confidence = 0.18;
    session.mastery[0].evidenceCount = 1;
    state.masteryBoosted = true;
  }
  addMessage("system", "Complete", "Draft evidence recorded in the interface. Durable learner-state writing still belongs to the session bridge.");
  renderMastery();
}

function togglePressed(button, className) {
  const next = button.getAttribute("aria-pressed") !== "true";
  button.setAttribute("aria-pressed", String(next));
  elements.body.classList.toggle(className, next);
}

function initialize() {
  applyLocalizedLabels();
  elements.navItems.forEach((item) => {
    item.addEventListener("click", () => setView(item.dataset.view));
  });
  elements.responseForm.addEventListener("submit", submitResponse);
  elements.runSessionButton.addEventListener("click", runDeterministicSessionTurn);
  elements.liveTeacherButton.addEventListener("click", invokeLiveTeacher);
  elements.hintButton.addEventListener("click", showHint);
  elements.completeButton.addEventListener("click", markComplete);
  elements.lecturePlayButton.addEventListener("click", toggleLecturePlayback);
  elements.lectureProgress.addEventListener("input", () => setLecturePosition(elements.lectureProgress.value));
  elements.chapterList.addEventListener("click", (event) => {
    const button = event.target.closest("[data-start-second]");
    if (button) {
      setLecturePosition(button.dataset.startSecond);
    }
  });
  elements.lectureCheckpoints.addEventListener("click", (event) => {
    const button = event.target.closest("[data-checkpoint-save]");
    if (button) {
      saveCheckpoint(button.dataset.checkpointSave);
    }
  });
  elements.assessmentModeControls.addEventListener("click", (event) => {
    const button = event.target.closest("[data-assessment-mode]");
    if (button) {
      state.activeAssessmentMode = button.dataset.assessmentMode;
      renderAssessment();
      elements.assessmentLog.textContent = "";
    }
  });
  elements.saveAssessmentButton.addEventListener("click", saveAssessmentEvidence);
  elements.sourceSelect.addEventListener("change", () => {
    state.activeSourceId = elements.sourceSelect.value;
    state.activeCourseId = "";
    state.selectedObjectiveId = "";
    renderCourseNavigation();
  });
  elements.courseSelect.addEventListener("change", () => {
    state.activeCourseId = elements.courseSelect.value;
    state.selectedObjectiveId = "";
    renderCourseNavigation();
  });
  elements.objectiveList.addEventListener("click", (event) => {
    const button = event.target.closest("[data-objective-id]");
    if (button) {
      state.selectedObjectiveId = button.dataset.objectiveId;
      renderCourseNavigation();
      elements.courseNavigationLog.textContent =
        `Objective selected for inspection: ${button.textContent.trim()}. Start a new session to adapt against it.`;
    }
  });
  elements.saveJournalButton.addEventListener("click", persistJournal);
  elements.saveStateButton.addEventListener("click", saveLearnerState);
  elements.exportStateButton.addEventListener("click", exportLearnerState);
  elements.importStateButton.addEventListener("click", importLearnerState);
  elements.syncPreviewButton.addEventListener("click", previewLearnerStateSync);
  elements.focusToggle.addEventListener("click", () => togglePressed(elements.focusToggle, "is-focus"));
  elements.contrastToggle.addEventListener("click", () => togglePressed(elements.contrastToggle, "is-high-contrast"));

  if (!loadSavedLearnerState()) {
    renderSession();
  }
  refreshLiveTeacherStatus();
  setView("lesson");
}

initialize();
