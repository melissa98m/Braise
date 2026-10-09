// Tableau de bord staff — revue de modération humaine (cahier des charges C.1/C.2).
// Vanilla JS, aucune dépendance : cohérent avec la contrainte "aucun outillage/build superflu"
// du projet (voir main.py, StaticFiles servi tel quel par le backend, même origine).

const TOKEN_KEY = "bresonne_staff_token";

/** @type {{token: string|null}} */
const state = { token: sessionStorage.getItem(TOKEN_KEY) };

// ---------------------------------------------------------------------------
// Petits utilitaires DOM / réseau
// ---------------------------------------------------------------------------

function el(tag, props = {}, children = []) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (key === "class") node.className = value;
    else if (key.startsWith("on") && typeof value === "function") node.addEventListener(key.slice(2), value);
    else if (value !== null && value !== undefined) node.setAttribute(key, value);
  }
  for (const child of children) {
    if (child === null || child === undefined) continue;
    node.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return node;
}

function clear(node) {
  while (node.firstChild) node.removeChild(node.firstChild);
}

let toastTimer = null;
function toast(message, kind = "info") {
  const node = document.getElementById("toast");
  node.textContent = message;
  node.dataset.kind = kind;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    node.textContent = "";
    delete node.dataset.kind;
  }, 6000);
}

class ApiError extends Error {
  constructor(status, detail) {
    super(detail || `Erreur HTTP ${status}`);
    this.status = status;
  }
}

async function api(path, options = {}) {
  const headers = { ...(options.headers || {}) };
  if (options.body) headers["Content-Type"] = "application/json";
  if (state.token) headers["Authorization"] = `Bearer ${state.token}`;
  const response = await fetch(path, { ...options, headers });
  if (response.status === 204) return null;
  const data = await response.json().catch(() => null);
  if (!response.ok) {
    throw new ApiError(response.status, data && data.detail);
  }
  return data;
}

/** Boîte de dialogue de confirmation native <dialog> — piégeage de focus et fermeture Échap
 * gérés par le navigateur, pas de réimplémentation maison. */
function confirmAction(title, body) {
  const dialog = document.getElementById("confirm-dialog");
  document.getElementById("confirm-title").textContent = title;
  document.getElementById("confirm-body").textContent = body;
  dialog.showModal();
  return new Promise((resolve) => {
    const onAccept = () => { cleanup(); resolve(true); };
    const onCancel = () => { cleanup(); resolve(false); };
    function cleanup() {
      dialog.close();
      document.getElementById("confirm-accept").removeEventListener("click", onAccept);
      document.getElementById("confirm-cancel").removeEventListener("click", onCancel);
      dialog.removeEventListener("cancel", onCancel);
    }
    document.getElementById("confirm-accept").addEventListener("click", onAccept);
    document.getElementById("confirm-cancel").addEventListener("click", onCancel);
    dialog.addEventListener("cancel", onCancel);
  });
}

function relativeDate(iso) {
  const date = new Date(iso);
  return `${date.toLocaleDateString("fr-FR")} à ${date.toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" })}`;
}

// ---------------------------------------------------------------------------
// Connexion
// ---------------------------------------------------------------------------

function showLoginError(message) {
  const node = document.getElementById("login-error");
  node.textContent = message;
  node.hidden = !message;
}

function wireLogin() {
  const emailForm = document.getElementById("email-form");
  const codeForm = document.getElementById("code-form");
  const debugCode = document.getElementById("debug-code");
  let email = "";

  emailForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    showLoginError("");
    email = document.getElementById("email-input").value.trim().toLowerCase();
    const submitButton = document.getElementById("email-submit");
    submitButton.disabled = true;
    try {
      const result = await api("/auth/request-otp", { method: "POST", body: JSON.stringify({ email }) });
      emailForm.hidden = true;
      codeForm.hidden = false;
      if (result && result.debug_code) {
        debugCode.textContent = `Code de test (DEBUG_OTP) : ${result.debug_code}`;
        debugCode.hidden = false;
      }
      document.getElementById("code-input").focus();
    } catch (err) {
      showLoginError(err.message || "Impossible d'envoyer le code.");
    } finally {
      submitButton.disabled = false;
    }
  });

  codeForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    showLoginError("");
    const code = document.getElementById("code-input").value.trim();
    const submitButton = document.getElementById("code-submit");
    submitButton.disabled = true;

    let token;
    try {
      const tokenResult = await api("/auth/verify-otp", {
        method: "POST",
        body: JSON.stringify({ email, code }),
      });
      token = tokenResult.access_token;
    } catch (err) {
      // Le code lui-même est en cause (faux, expiré, déjà utilisé) : on reste sur ce même
      // formulaire pour permettre une nouvelle saisie.
      showLoginError(err.message || "Code invalide ou expiré.");
      submitButton.disabled = false;
      return;
    }

    state.token = token;
    try {
      const me = await api("/admin/me");
      sessionStorage.setItem(TOKEN_KEY, state.token);
      enterDashboard(me);
    } catch (err) {
      // verify-otp a réussi (donc a déjà consommé le code) : le problème ici est l'accès, pas
      // le code. Revenir à l'étape adresse plutôt que de laisser le formulaire de code affiché
      // avec un code désormais invalide — le renvoyer produirait un "code invalide" trompeur qui
      // masque le vrai message (incident réel : un compte non-staff a vu ce piège en pratique).
      state.token = null;
      resetLoginForm();
      showLoginError(
        err.status === 403
          ? "Ce compte n'a pas accès à la modération."
          : err.message || "Connexion impossible pour le moment."
      );
    }
  });
}

function resetLoginForm() {
  document.getElementById("email-form").hidden = false;
  document.getElementById("code-form").hidden = true;
  document.getElementById("email-form").reset();
  document.getElementById("code-form").reset();
  document.getElementById("debug-code").hidden = true;
  showLoginError("");
}

function logout() {
  sessionStorage.removeItem(TOKEN_KEY);
  state.token = null;
  document.getElementById("dashboard-view").hidden = true;
  document.getElementById("login-view").hidden = false;
  resetLoginForm();
}

// ---------------------------------------------------------------------------
// Tableau de bord — onglets
// ---------------------------------------------------------------------------

const QUEUES = ["reports", "ban_appeals", "flagged_ratings"];
/** Vue courante par file : "list" (par défaut) ou l'id d'un item en détail. */
const panelState = { reports: { view: "list" }, ban_appeals: { view: "list" }, flagged_ratings: { view: "list" } };

function wireTabs() {
  const tabs = QUEUES.map((q) => document.getElementById(`tab-${q}`));
  tabs.forEach((tab) => {
    tab.addEventListener("click", () => selectTab(tab.dataset.queue));
    tab.addEventListener("keydown", (event) => {
      if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return;
      event.preventDefault();
      const index = tabs.indexOf(tab);
      const next = event.key === "ArrowRight" ? (index + 1) % tabs.length : (index - 1 + tabs.length) % tabs.length;
      tabs[next].focus();
      selectTab(tabs[next].dataset.queue);
    });
  });
}

function selectTab(queue) {
  for (const q of QUEUES) {
    document.getElementById(`tab-${q}`).setAttribute("aria-selected", String(q === queue));
    document.getElementById(`tab-${q}`).tabIndex = q === queue ? 0 : -1;
    document.getElementById(`panel-${q}`).hidden = q !== queue;
  }
  renderPanel(queue);
}

async function refreshCounts() {
  try {
    const counts = await api("/admin/queue-counts");
    for (const [key, id] of [
      ["reports_pending", "count-reports"],
      ["ban_appeals_pending", "count-ban_appeals"],
      ["flagged_ratings_pending", "count-flagged_ratings"],
    ]) {
      const badge = document.getElementById(id);
      badge.textContent = String(counts[key]);
      badge.dataset.zero = String(counts[key] === 0);
    }
  } catch {
    // Décoratif : un badge qui ne se met pas à jour ne doit jamais casser le reste du tableau
    // de bord, même principe que le badge non-lus mobile (CLAUDE.md, P9.2).
  }
}

function renderPanel(queue) {
  const view = panelState[queue].view;
  if (view === "list") renderList(queue);
  else renderDetail(queue, view);
}

// ---------------------------------------------------------------------------
// Listes
// ---------------------------------------------------------------------------

const QUEUE_CONFIG = {
  reports: {
    label: "signalement",
    labelPlural: "signalements",
    listPath: (status) => `/admin/reports?status=${status}&limit=50`,
    statuses: ["pending", "founded", "unfounded"],
    columns: (item) => [relativeDate(item.created_at), item.reason, item.comment, item.status],
    headers: ["Date", "Motif", "Commentaire", "Statut"],
  },
  ban_appeals: {
    label: "contestation",
    labelPlural: "contestations",
    listPath: (status) => `/admin/ban-appeals?status=${status}&limit=50`,
    statuses: ["pending", "upheld", "overturned"],
    columns: (item) => [relativeDate(item.created_at), item.message, item.status],
    headers: ["Date", "Message", "Statut"],
  },
  flagged_ratings: {
    label: "note",
    labelPlural: "notes signalées",
    listPath: () => `/admin/flagged-ratings?limit=50`,
    statuses: null,
    columns: (item) => [relativeDate(item.created_at), String(item.score), item.comment],
    headers: ["Date", "Note", "Commentaire"],
  },
};

function statusLabel(queue, status) {
  const labels = {
    pending: "En attente",
    founded: "Fondé",
    unfounded: "Non fondé",
    upheld: "Maintenu",
    overturned: "Annulé",
  };
  return labels[status] || status;
}

async function renderList(queue) {
  const config = QUEUE_CONFIG[queue];
  const panel = document.getElementById(`panel-${queue}`);
  clear(panel);

  let currentStatus = "pending";
  const controls = el("div", { class: "list-controls" });
  if (config.statuses) {
    const select = el("select", {
      "aria-label": `Filtrer les ${config.labelPlural} par statut`,
      onchange: (e) => load(e.target.value),
    }, config.statuses.map((s) => el("option", { value: s }, [statusLabel(queue, s)])));
    controls.append(el("span", {}, [`Statut : `]), select);
  }
  panel.append(controls);

  const body = el("div", {});
  panel.append(body);

  async function load(status) {
    currentStatus = status || currentStatus;
    clear(body);
    body.append(el("p", { class: "loading-state" }, ["Chargement en cours."]));
    try {
      const items = await api(config.listPath(currentStatus));
      clear(body);
      if (items.length === 0) {
        body.append(el("p", { class: "empty-state" }, [`Aucun élément dans cette file pour le moment.`]));
        return;
      }
      const table = el("table", {}, [
        el("thead", {}, [el("tr", {}, config.headers.map((h) => el("th", {}, [h])))]),
        el("tbody", {}, items.map((item) => el("tr", {
          tabindex: "0",
          role: "button",
          "aria-label": `Voir le détail de ce ${config.label}`,
          onclick: () => openDetail(queue, item.id),
          onkeydown: (e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); openDetail(queue, item.id); } },
        }, config.columns(item).map((cell) => el("td", {}, [String(cell).slice(0, 140)]))))),
      ]);
      body.append(table);
    } catch (err) {
      clear(body);
      body.append(el("div", { class: "error-state" }, [
        el("p", {}, [err.message || "Impossible de charger cette file."]),
        el("button", { onclick: () => load(currentStatus) }, ["Réessayer"]),
      ]));
    }
  }

  load(currentStatus);
}

function openDetail(queue, id) {
  panelState[queue] = { view: id };
  renderPanel(queue);
}

function backToList(queue) {
  panelState[queue] = { view: "list" };
  renderPanel(queue);
}

// ---------------------------------------------------------------------------
// Détails + décisions
// ---------------------------------------------------------------------------

function userSummaryCard(title, user) {
  return el("div", { class: "user-summary" }, [
    el("h3", {}, [title]),
    el("dl", {}, [
      el("dt", {}, ["Nom affiché"]), el("dd", {}, [user.display_name || "—"]),
      el("dt", {}, ["Email"]), el("dd", {}, [user.email || "—"]),
      el("dt", {}, ["Vérifié"]), el("dd", {}, [user.is_verified ? "Oui" : "Non"]),
      el("dt", {}, ["Banni"]), el("dd", {}, [user.is_banned ? "Oui" : "Non"]),
      el("dt", {}, ["Confiance"]), el("dd", {}, [
        user.trust_score === null ? "Pas encore de note" : `${user.trust_score} — ${user.trust_label}`,
      ]),
    ]),
  ]);
}

function decisionForm({ legend, options, onSubmit, extraFields = [] }) {
  const fieldset = el("fieldset", {}, [el("legend", {}, [legend])]);
  const groupName = `decision-${Math.random().toString(36).slice(2)}`;
  options.forEach((opt, index) => {
    const inputId = `${groupName}-${opt.value}`;
    fieldset.append(el("div", { class: "radio-row" }, [
      el("input", { type: "radio", name: groupName, id: inputId, value: opt.value, ...(index === 0 ? { checked: "checked" } : {}) }),
      el("label", { for: inputId, style: "margin:0" }, [opt.label]),
    ]));
  });
  fieldset.append(...extraFields);

  const noteId = `note-${groupName}`;
  const note = el("textarea", { id: noteId, rows: "3", placeholder: "Motif de la décision (visible dans l'historique interne)." });
  const noteError = el("p", { class: "error", role: "alert", hidden: "hidden" });

  const submit = el("button", { type: "submit", class: "primary" }, ["Valider la décision"]);
  const form = el("form", {
    onsubmit: async (event) => {
      event.preventDefault();
      const selected = fieldset.querySelector("input[type=radio]:checked");
      if (!note.value.trim()) {
        noteError.textContent = "Merci d'indiquer un motif avant de valider.";
        noteError.hidden = false;
        note.focus();
        return;
      }
      noteError.hidden = true;
      submit.disabled = true;
      try {
        await onSubmit(selected.value, note.value.trim());
      } finally {
        submit.disabled = false;
      }
    },
  }, [
    fieldset,
    el("label", { for: noteId }, ["Motif / note interne"]),
    note,
    noteError,
    el("div", { class: "action-row" }, [submit]),
  ]);
  return form;
}

async function renderDetail(queue, id) {
  const panel = document.getElementById(`panel-${queue}`);
  clear(panel);
  panel.append(el("p", { class: "loading-state" }, ["Chargement en cours."]));

  const loaders = {
    reports: () => api(`/admin/reports/${id}`),
    ban_appeals: () => api(`/admin/ban-appeals/${id}`),
    flagged_ratings: () => api(`/admin/flagged-ratings/${id}`),
  };
  const renderers = { reports: renderReportDetail, ban_appeals: renderBanAppealDetail, flagged_ratings: renderFlaggedRatingDetail };

  try {
    const detail = await loaders[queue]();
    clear(panel);
    const back = el("button", { onclick: () => backToList(queue) }, ["← Retour à la liste"]);
    panel.append(back, renderers[queue](detail, queue));
  } catch (err) {
    clear(panel);
    panel.append(el("div", { class: "error-state" }, [
      el("p", {}, [err.status === 404 ? "Cet élément n'existe plus." : (err.message || "Erreur de chargement.")]),
      el("button", { onclick: () => backToList(queue) }, ["Retour à la liste"]),
    ]));
  }
}

function renderReportDetail(detail) {
  const card = el("div", { class: "detail-card" }, [
    el("h2", {}, [`Signalement — ${detail.reason}`]),
    el("p", {}, [`Créé le ${relativeDate(detail.created_at)} · Statut : ${statusLabel("reports", detail.status)}`]),
    el("div", { class: "comment-block" }, [detail.comment]),
    el("div", { class: "detail-grid" }, [
      userSummaryCard("Signalé par", detail.reporter),
      userSummaryCard("Personne signalée", detail.reported),
    ]),
    el("p", {}, [`Signalements précédents contre cette personne : ${detail.prior_reports_against_reported}`]),
  ]);

  if (detail.status === "pending") {
    const banCheckboxId = "ban-reported-checkbox";
    const banCheckbox = el("input", { type: "checkbox", id: banCheckboxId });
    card.append(decisionForm({
      legend: "Décision",
      options: [
        { value: "founded", label: "Fondé" },
        { value: "unfounded", label: "Non fondé" },
      ],
      extraFields: [el("div", { class: "radio-row" }, [
        banCheckbox,
        el("label", { for: banCheckboxId, style: "margin:0" }, ["Bannir la personne signalée"]),
      ])],
      onSubmit: async (decision, note) => {
        const banReported = banCheckbox.checked;
        const summary = banReported
          ? `Marquer ce signalement "${statusLabel("reports", decision)}" et bannir ${detail.reported.display_name || detail.reported.email} ?`
          : `Marquer ce signalement "${statusLabel("reports", decision)}" ?`;
        const confirmed = await confirmAction("Confirmer la décision", summary);
        if (!confirmed) return;
        await submitDecision("reports", detail.id, "resolve", { decision, note, ban_reported: banReported });
      },
    }));
  }
  return card;
}

function renderBanAppealDetail(detail) {
  const card = el("div", { class: "detail-card" }, [
    el("h2", {}, ["Contestation de bannissement"]),
    el("p", {}, [`Créée le ${relativeDate(detail.created_at)} · Statut : ${statusLabel("ban_appeals", detail.status)}`]),
    el("div", { class: "comment-block" }, [detail.message]),
    el("div", { class: "detail-grid" }, [userSummaryCard("Compte", detail.user)]),
    el("p", {}, [`Contestations précédentes de ce compte : ${detail.prior_appeals_count}`]),
  ]);
  if (detail.decision_note) {
    card.append(el("p", {}, [`Note de décision précédente : ${detail.decision_note}`]));
  }

  if (detail.status === "pending") {
    card.append(decisionForm({
      legend: "Décision",
      options: [
        { value: "overturned", label: "Annuler le bannissement" },
        { value: "upheld", label: "Maintenir le bannissement" },
      ],
      onSubmit: async (decision, note) => {
        const summary = decision === "overturned"
          ? `Annuler le bannissement de ${detail.user.display_name || detail.user.email} ? Le compte redeviendra immédiatement actif.`
          : `Maintenir le bannissement de ${detail.user.display_name || detail.user.email} ?`;
        const confirmed = await confirmAction("Confirmer la décision", summary);
        if (!confirmed) return;
        await submitDecision("ban_appeals", detail.id, "resolve", { decision, note });
      },
    }));
  }
  return card;
}

function renderFlaggedRatingDetail(detail) {
  const card = el("div", { class: "detail-card" }, [
    el("h2", {}, [`Note signalée — ${detail.score} / 5`]),
    el("p", {}, [`Créée le ${relativeDate(detail.created_at)}`]),
    el("div", { class: "comment-block" }, [detail.comment]),
    el("p", {}, [
      `Score du classifieur (rancune) : ${(detail.rancor_probability * 100).toFixed(0)} %`,
      detail.flagged_post_unlock_rule ? " · Signalée aussi par la règle post-déblocage (note très basse peu après le déblocage des photos)." : "",
    ]),
    el("div", { class: "detail-grid" }, [
      userSummaryCard("A noté", detail.rater),
      userSummaryCard("A été noté·e", detail.ratee),
    ]),
  ]);

  card.append(decisionForm({
    legend: "Décision",
    options: [
      { value: "cleared", label: "Lever le signalement (note légitime)" },
      { value: "confirmed", label: "Confirmer le signalement (exclue du score de confiance)" },
    ],
    onSubmit: async (decision, note) => {
      const summary = decision === "cleared"
        ? "Lever le signalement ? Cette note réintégrera le calcul du score de confiance."
        : "Confirmer le signalement ? Cette note restera exclue du score de confiance.";
      const confirmed = await confirmAction("Confirmer la décision", summary);
      if (!confirmed) return;
      await submitDecision("flagged_ratings", detail.id, "review", { decision, note });
    },
  }));
  return card;
}

async function submitDecision(queue, id, verb, payload) {
  const paths = {
    reports: (id) => `/admin/reports/${id}/${verb}`,
    ban_appeals: (id) => `/admin/ban-appeals/${id}/${verb}`,
    flagged_ratings: (id) => `/admin/flagged-ratings/${id}/${verb}`,
  };
  try {
    await api(paths[queue](id), { method: "POST", body: JSON.stringify(payload) });
    toast("Décision enregistrée.", "success");
    backToList(queue);
    refreshCounts();
  } catch (err) {
    if (err.status === 409) {
      toast("Cet élément a déjà été traité par quelqu'un d'autre — mise à jour de la fiche.", "error");
      renderDetail(queue, id);
    } else {
      toast(err.message || "Échec de l'enregistrement de la décision.", "error");
    }
  }
}

// ---------------------------------------------------------------------------
// Démarrage
// ---------------------------------------------------------------------------

function enterDashboard(me) {
  document.getElementById("login-view").hidden = true;
  document.getElementById("dashboard-view").hidden = false;
  document.getElementById("staff-identity").textContent = me.display_name || me.email || "";
  refreshCounts();
  selectTab("reports");
}

async function boot() {
  wireLogin();
  wireTabs();
  document.getElementById("logout-button").addEventListener("click", logout);

  if (!state.token) return;
  try {
    const me = await api("/admin/me");
    enterDashboard(me);
  } catch {
    logout();
  }
}

document.addEventListener("DOMContentLoaded", boot);
