const $ = (sel) => document.querySelector(sel);

function basenamePath(p) {
  if (!p) return "";
  const parts = p.replace(/\\/g, "/").split("/");
  return parts[parts.length - 1] || p;
}

async function health() {
  try {
    const r = await fetch("/api/health");
    const j = await r.json();
    const dot = $("#health-dot");
    const txt = $("#health-text");
    const hint = $("#data-canonical-hint");
    if (hint) {
      if (j.ok && j.data_xlsx && j.lit_review_rows != null) {
        hint.textContent = `Canonical spreadsheet: ${basenamePath(j.virus_xlsx_path)} — Lit_Review ${j.lit_review_rows} row(s).`;
        hint.title = j.virus_xlsx_path || "";
      } else if (j.ok && !j.data_xlsx) {
        hint.textContent =
          "Place Virus.xlsx (or virus.xlsx) in the project root next to chlorine_tool/ for the data table.";
        hint.title = "";
      } else {
        hint.textContent = "";
        hint.title = "";
      }
    }
    if (j.ok && !j.rscript_available) {
      dot.className = "status-dot bad";
      txt.textContent =
        "Rscript not on PATH — install R and add its bin folder to PATH (needed for lme4 + ranger).";
    } else if (j.ok && j.model_loaded && j.data_xlsx) {
      dot.className = "status-dot ok";
      const lr =
        j.lit_review_rows != null ? ` Lit_Review: ${j.lit_review_rows} row(s).` : "";
      txt.textContent = `R model (rf_nonlinear.rds) and Virus.xlsx loaded.${lr}`;
      txt.title = j.virus_xlsx_path || "";
    } else if (j.ok && j.model_loaded) {
      dot.className = "status-dot ok";
      txt.textContent = "R model loaded; Virus.xlsx missing (data table limited).";
      txt.title = "";
    } else {
      dot.className = "status-dot bad";
      txt.textContent =
        "Model not trained — with R installed run `python train_model.py` (uses chlorine_tool/r/train_rf_nonlinear.R).";
      txt.title = "";
    }
  } catch {
    $("#health-dot").className = "status-dot bad";
    $("#health-text").textContent = "Cannot reach API — start the server (uvicorn).";
    const hint = $("#data-canonical-hint");
    if (hint) hint.textContent = "";
  }
}

function tabInit() {
  const buttons = document.querySelectorAll(".tab-bar button");
  const panels = document.querySelectorAll(".panel");
  buttons.forEach((btn) => {
    btn.addEventListener("click", () => {
      const id = btn.dataset.tab;
      buttons.forEach((b) => b.classList.toggle("active", b === btn));
      panels.forEach((p) => p.classList.toggle("active", p.id === `panel-${id}`));
      if (id === "queue") loadQueue();
      if (id === "model") loadBenchmark();
    });
  });
}

async function estimate() {
  const ph = parseFloat($("#ph").value);
  const temp = parseFloat($("#temp").value);
  $("#err-box").style.display = "none";
  $("#warn-box").style.display = "none";
  try {
    const r = await fetch("/api/predict", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ph, temperature: temp }),
    });
    if (!r.ok) {
      const err = await r.json().catch(() => ({}));
      throw new Error(err.detail || r.statusText);
    }
    const j = await r.json();
    $("#result-placeholder").style.display = "none";
    $("#result-body").style.display = "block";
    $("#out-mean").textContent = formatNum(j.prediction);
    $("#out-units").textContent = j.units || "";
    $("#out-ci").textContent = `${formatNum(j.ci_95_low)} — ${formatNum(j.ci_95_high)}`;
    $("#out-ct-cons").textContent = formatNum(j.ct_4log_conservative);
    $("#out-ct-mean").textContent = formatNum(j.ct_4log_mean);
    const low = j.ct_4log_95_low;
    const high = j.ct_4log_95_high;
    if (low != null && high != null) {
      $("#out-ct-range").textContent = `${formatNum(low)} — ${formatNum(high)}`;
    } else {
      $("#out-ct-range").textContent = "—";
    }
    const bits = [];
    if (j.study_effects_source === "lme4_r") {
      bits.push("Predictions use R ranger + lme4 study effects (same stack as the notebook).");
    }
    if (bits.length) {
      $("#warn-box").textContent = bits.join(" ");
      $("#warn-box").style.display = "block";
    }
  } catch (e) {
    $("#err-box").textContent = String(e.message || e);
    $("#err-box").style.display = "block";
  }
}

function formatNum(x) {
  if (x == null || Number.isNaN(x)) return "—";
  const v = Number(x);
  if (!Number.isFinite(v)) return "—";
  if (Math.abs(v) >= 1000 || (Math.abs(v) < 0.01 && v !== 0)) return v.toExponential(3);
  return v.toFixed(4);
}

async function loadTable() {
  const strain = $("#filter-strain").value.trim();
  const phVal = $("#filter-ph").value;
  const tempVal = $("#filter-temp").value;
  const params = new URLSearchParams();
  if (strain) params.set("strain", strain);
  if (phVal !== "") params.set("ph", phVal);
  if (tempVal !== "") params.set("temp", tempVal);
  $("#table-count").textContent = "Loading…";
  try {
    const r = await fetch(`/api/data?${params}`);
    if (!r.ok) throw new Error(await r.text());
    const j = await r.json();
    const total = j.lit_review_total_rows;
    const n = j.count;
    const filtered = Boolean(j.filters_applied);
    if (filtered && typeof total === "number") {
      $("#table-count").textContent = `Showing ${n} of ${total} Lit_Review row(s) (filters applied).`;
    } else if (typeof total === "number") {
      $("#table-count").textContent = `${n} row(s) — full Lit_Review sheet.`;
    } else {
      $("#table-count").textContent = `${n} row(s)`;
    }
    renderTable(j.rows || [], "#data-thead", "#data-tbody");
  } catch (e) {
    $("#table-count").textContent = `Error: ${e.message}`;
  }
}

function renderTable(rows, theadSel = "#data-thead", tbodySel = "#data-tbody") {
  const thead = $(theadSel);
  const tbody = $(tbodySel);
  thead.innerHTML = "";
  tbody.innerHTML = "";
  if (!rows.length) return;
  const colSet = new Set();
  rows.forEach((row) => Object.keys(row).forEach((k) => colSet.add(k)));
  const cols = Array.from(colSet).sort((a, b) => {
    if (a === "_line") return -1;
    if (b === "_line") return 1;
    return a.localeCompare(b);
  });
  const hr = document.createElement("tr");
  cols.forEach((c) => {
    const th = document.createElement("th");
    th.textContent = c;
    hr.appendChild(th);
  });
  thead.appendChild(hr);
  rows.forEach((row) => {
    const tr = document.createElement("tr");
    cols.forEach((c) => {
      const td = document.createElement("td");
      const v = row[c];
      td.textContent = v != null ? String(v) : "";
      tr.appendChild(td);
    });
    tbody.appendChild(tr);
  });
}

function fmtBenchCell(v) {
  if (v === null || v === undefined || v === "") return "—";
  if (typeof v === "number" && Number.isFinite(v)) {
    if (Math.abs(v) >= 1000 || (Math.abs(v) < 1e-4 && v !== 0)) return v.toExponential(3);
    return v.toFixed(4);
  }
  return String(v);
}

async function loadBenchmark() {
  const hint = $("#benchmark-hint");
  const wrap = $("#benchmark-table-wrap");
  const tbody = $("#benchmark-tbody");
  const meta = $("#benchmark-updated");
  try {
    const r = await fetch("/api/benchmark");
    const j = await r.json().catch(() => ({}));
    if (!r.ok) {
      throw new Error(j.detail || r.statusText);
    }
    if (!j.loaded || !j.benchmark) {
      if (hint) hint.textContent = j.hint || "No benchmark file.";
      if (wrap) wrap.style.display = "none";
      if (tbody) tbody.innerHTML = "";
      if (meta) meta.textContent = "";
      return;
    }
    const b = j.benchmark;
    const models = Array.isArray(b.models) ? b.models : [];
    if (hint) hint.textContent = b.note || "";
    if (meta) {
      const parts = [];
      if (b.updated_at) parts.push(`Updated: ${b.updated_at}`);
      if (j.path) parts.push(j.path);
      meta.textContent = parts.join(" · ");
    }
    if (tbody) {
      tbody.innerHTML = "";
      const keys = ["name", "role", "r2", "rmse", "oob_r2", "kfold_r2", "loo_r2", "notes"];
      models.forEach((m) => {
        const tr = document.createElement("tr");
        keys.forEach((k) => {
          const td = document.createElement("td");
          td.textContent = fmtBenchCell(m[k]);
          tr.appendChild(td);
        });
        tbody.appendChild(tr);
      });
    }
    if (wrap) wrap.style.display = models.length ? "block" : "none";
  } catch (e) {
    if (hint) hint.textContent = `Could not load benchmarks: ${e.message}`;
    if (wrap) wrap.style.display = "none";
  }
}

async function loadQueue() {
  const st = $("#queue-status");
  if (st) st.textContent = "Loading…";
  try {
    const r = await fetch("/api/submissions");
    if (!r.ok) throw new Error(await r.text());
    const j = await r.json();
    const rows = j.submissions || [];
    if (st) {
      st.textContent = rows.length
        ? `${rows.length} pending · ${j.path}`
        : `Empty · ${j.path}`;
    }
    renderTable(rows, "#queue-thead", "#queue-tbody");
  } catch (e) {
    if (st) st.textContent = `Error: ${e.message}`;
  }
}

async function loadModelInfo() {
  try {
    const r = await fetch("/api/model-info");
    const j = await r.json();
    let t = j.description || "";
    if (j.meta && j.meta.train_rows) {
      t += ` Training rows (Faulkner): ${j.meta.train_rows}.`;
    }
    if (
      j.meta &&
      j.meta.non_faulkner_rows_excluded != null &&
      j.meta.non_faulkner_rows_excluded !== undefined
    ) {
      t += ` Non-Faulkner excluded: ${j.meta.non_faulkner_rows_excluded}.`;
      if (j.meta.non_faulkner_rows_excluded === 0) {
        t += " (Same rows as all-strain post-exclusions.)";
      }
    }
    if (j.meta && j.meta.training_scope) {
      t += ` ${j.meta.training_scope}`;
    }
    $("#model-desc").textContent = t;
    const ext = $("#model-future");
    if (ext) {
      ext.textContent = j.future_extensions || "";
    }
  } catch {
    $("#model-desc").textContent = "Could not load model info.";
    const ext = $("#model-future");
    if (ext) ext.textContent = "";
  }
}

async function submitStudy() {
  const body = {
    submitter_name: $("#sub-name").value.trim() || null,
    email: $("#sub-email").value.trim() || null,
    citation: $("#sub-citation").value.trim() || null,
    strain: $("#sub-strain").value.trim() || null,
    ph: $("#sub-ph").value === "" ? null : parseFloat($("#sub-ph").value),
    temperature: $("#sub-temp").value === "" ? null : parseFloat($("#sub-temp").value),
    constant: $("#sub-k").value === "" ? null : parseFloat($("#sub-k").value),
    notes: $("#sub-notes").value.trim() || null,
  };
  $("#submit-feedback").textContent = "Sending…";
  try {
    const r = await fetch("/api/submit", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    const j = await r.json();
    if (!r.ok) throw new Error(j.detail || "Failed");
    $("#submit-feedback").textContent = `Saved to ${j.path}`;
  } catch (e) {
    $("#submit-feedback").textContent = String(e.message || e);
  }
}

function syncFiltersFromEstimator() {
  $("#filter-ph").value = $("#ph").value;
  $("#filter-temp").value = $("#temp").value;
}

document.addEventListener("DOMContentLoaded", () => {
  tabInit();
  health();
  loadModelInfo();
  loadBenchmark();
  $("#btn-estimate").addEventListener("click", estimate);
  $("#btn-load-table").addEventListener("click", () => {
    loadTable();
  });
  const syncEst = $("#btn-sync-estimator-filters");
  if (syncEst) {
    syncEst.addEventListener("click", () => {
      syncFiltersFromEstimator();
    });
  }
  $("#btn-submit").addEventListener("click", submitStudy);
  const qr = $("#btn-queue-refresh");
  if (qr) qr.addEventListener("click", () => loadQueue());
});
