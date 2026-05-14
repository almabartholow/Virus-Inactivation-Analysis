"""FastAPI server: estimator, Lit_Review table, submissions, model description."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from app.modeling import (
    ARTIFACTS,
    find_xlsx,
    load_bundle,
    load_full_table,
    predict_row,
    rscript_path,
)

STATIC = Path(__file__).resolve().parents[1] / "static"
TOOL_ROOT = Path(__file__).resolve().parents[1]
SUBMISSIONS_PATH = TOOL_ROOT / "data" / "submissions.jsonl"
BENCHMARK_PATH = ARTIFACTS / "model_benchmark.json"
BENCHMARK_EXAMPLE = TOOL_ROOT / "model_benchmark.example.json"

app = FastAPI(title="Chlorine virus inactivation estimator")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class PredictRequest(BaseModel):
    ph: float = Field(..., ge=0, le=14)
    temperature: float = Field(..., description="Temperature (°C)")


class SubmissionBody(BaseModel):
    submitter_name: str | None = None
    email: str | None = None
    citation: str | None = None
    strain: str | None = None
    ph: float | None = None
    temperature: float | None = None
    constant: float | None = None
    notes: str | None = None


@app.on_event("startup")
def startup() -> None:
    SUBMISSIONS_PATH.parent.mkdir(parents=True, exist_ok=True)
    if not SUBMISSIONS_PATH.is_file():
        SUBMISSIONS_PATH.write_text("", encoding="utf-8")


@app.get("/api/health")
def health() -> dict:
    bundle = load_bundle()
    xlsx = find_xlsx()
    lit_rows: int | None = None
    xlsx_resolved: str | None = None
    if xlsx is not None:
        xlsx_resolved = str(xlsx.resolve())
        try:
            lit_rows = len(load_full_table(xlsx))
        except Exception:
            lit_rows = None
    return {
        "ok": True,
        "model_loaded": bundle is not None,
        "data_xlsx": xlsx is not None,
        "virus_xlsx_path": xlsx_resolved,
        "lit_review_rows": lit_rows,
        "rscript_available": rscript_path() is not None,
    }


@app.post("/api/predict")
def api_predict(req: PredictRequest) -> dict:
    bundle = load_bundle()
    if bundle is None:
        raise HTTPException(
            status_code=503,
            detail=(
                "Model not trained. Install R + packages (see chlorine_tool/r/install_deps.R), "
                "add Rscript to PATH, place Virus.xlsx in the repo root, then: python train_model.py"
            ),
        )
    out = predict_row(bundle, req.ph, req.temperature)
    return {
        "ph": req.ph,
        "temperature": req.temperature,
        "prediction": out["mean"],
        "ci_95_low": out["ci_low"],
        "ci_95_high": out["ci_high"],
        "units": out["units"],
        "log_numerator_4log": out["log_numerator_4log"],
        "ct_4log_mean": out["ct_4log_mean"],
        "ct_4log_conservative": out["ct_4log_conservative"],
        "ct_4log_95_low": out["ct_4log_95_low"],
        "ct_4log_95_high": out["ct_4log_95_high"],
        "ct_units": out["ct_units"],
        "study_effects_source": bundle.get("study_effects_source"),
    }


@app.get("/api/data")
def api_data(
    strain: str | None = None,
    ph: float | None = None,
    temp: float | None = None,
    ph_tol: float = 0.51,
    temp_tol: float = 2.51,
) -> dict:
    """Lit_Review rows; optional filters match estimator inputs (within tolerance)."""
    try:
        df = load_full_table()
    except FileNotFoundError as e:
        raise HTTPException(status_code=503, detail=str(e)) from e
    df = df.copy()
    lit_review_total_rows = len(df)
    filters_applied = bool(
        (strain and strain.strip())
        or ph is not None
        or temp is not None
    )
    if strain:
        s = strain.strip().lower()
        if "Strain" in df.columns:
            mask = df["Strain"].astype(str).str.lower().str.contains(s, na=False)
            df = df.loc[mask]
    if ph is not None and "pH" in df.columns:
        df = df.loc[df["pH"].sub(float(ph)).abs() <= ph_tol]
    if temp is not None and "Temperature" in df.columns:
        df = df.loc[df["Temperature"].sub(float(temp)).abs() <= temp_tol]
    # Replace NaN for JSON
    records = json.loads(df.astype(object).where(df.notna(), None).to_json(orient="records"))
    n = len(records)
    return {
        "rows": records,
        "count": n,
        "lit_review_total_rows": lit_review_total_rows,
        "sheet": "Lit_Review",
        "filters_applied": filters_applied,
    }


def _read_submissions_list() -> tuple[list[dict], str]:
    """Parse JSONL; each record includes _line (1-based file line)."""
    path = str(SUBMISSIONS_PATH.resolve())
    if not SUBMISSIONS_PATH.is_file():
        return [], path
    out: list[dict] = []
    with open(SUBMISSIONS_PATH, encoding="utf-8") as f:
        for i, raw in enumerate(f, start=1):
            line = raw.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(rec, dict):
                rec["_line"] = i
                out.append(rec)
    return out, path


@app.get("/api/submissions")
def api_submissions() -> dict:
    rows, path = _read_submissions_list()
    return {"submissions": rows, "count": len(rows), "path": path}


@app.get("/api/submissions/download")
def api_submissions_download() -> FileResponse:
    if not SUBMISSIONS_PATH.is_file():
        raise HTTPException(status_code=404, detail="No submissions file yet.")
    return FileResponse(
        path=str(SUBMISSIONS_PATH.resolve()),
        filename="submissions.jsonl",
        media_type="application/x-ndjson",
    )


@app.post("/api/submit")
def api_submit(body: SubmissionBody) -> dict:
    rec = {
        "received_at": datetime.now(timezone.utc).isoformat(),
        **body.model_dump(),
    }
    with open(SUBMISSIONS_PATH, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    return {"saved": True, "path": str(SUBMISSIONS_PATH)}


@app.get("/api/benchmark")
def api_benchmark() -> dict:
    """Optional comparison table: copy model_benchmark.example.json → artifacts/model_benchmark.json."""
    if not BENCHMARK_PATH.is_file():
        return {
            "loaded": False,
            "benchmark": None,
            "example_path": str(BENCHMARK_EXAMPLE.resolve()) if BENCHMARK_EXAMPLE.is_file() else None,
            "hint": "No model_benchmark.json — copy model_benchmark.example.json to artifacts/ and edit.",
        }
    try:
        with open(BENCHMARK_PATH, encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid model_benchmark.json: {e}",
        ) from e
    return {
        "loaded": True,
        "benchmark": data,
        "path": str(BENCHMARK_PATH.resolve()),
    }


@app.get("/api/model-info")
def model_info() -> dict:
    meta_path = ARTIFACTS / "model_meta.json"
    if meta_path.is_file():
        with open(meta_path, encoding="utf-8") as f:
            meta = json.load(f)
    else:
        meta = {}
    return {
        "meta": meta,
        "source_code_url": "https://github.com/almabartholow/Virus-Inactivation-Analysis",
        "description": (
            "Training and prediction run in R (lme4 mixed model + ranger), matching Virus_Analysis.ipynb. "
            "Training uses Lit_Review rows after exclusions with Strain == Faulkner only (multi-study pooling). "
            "Python serves the UI/API and invokes Rscript. Install packages via chlorine_tool/r/install_deps.R. "
            "Uncertainty on k is summarized by percentiles of tree predictions (ensemble spread), not a classical CI."
        ),
        "notebook_reference": (
            "Same as notebook: lmer(Constant ~ pH + Temperature + (pH + Temperature | Paper)); "
            "ranger(..., num.trees = 5000, seed = 111); predict with StudyEffect_* = 0."
        ),
        "future_extensions": (
            "Queue: review JSONL; merge to Lit_Review. Benchmarks: fill artifacts/model_benchmark.json "
            "(see model_benchmark.example.json) to show the Model tab comparison table."
        ),
    }


app.mount("/", StaticFiles(directory=str(STATIC), html=True), name="static")
