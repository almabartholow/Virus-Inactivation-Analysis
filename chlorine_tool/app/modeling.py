"""
Training and prediction use R (lme4 + ranger) to match Virus_Analysis.ipynb `rf_nonlinear`.
Python only orchestrates: reads Excel for the data table API, calls Rscript for train/predict.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any

import pandas as pd

# Project root = parent of chlorine_tool/
ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parents[1] / "artifacts"
R_DIR = Path(__file__).resolve().parents[1] / "r"
DEFAULT_XLSX_NAMES = ("Virus.xlsx", "virus.xlsx")


def find_xlsx(base: Path | None = None) -> Path | None:
    base = base or ROOT
    for name in DEFAULT_XLSX_NAMES:
        p = base / name
        if p.is_file():
            return p
    return None


def rscript_path() -> str | None:
    return shutil.which("Rscript")


def load_lit_review(path: Path) -> pd.DataFrame:
    df = pd.read_excel(path, sheet_name="Lit_Review")
    df.columns = [str(c).strip() for c in df.columns]
    return df


def train_and_save(
    xlsx_path: Path,
    out_dir: Path | None = None,
    random_state: int = 111,
) -> Path:
    """Train via R script (lme4 + ranger); writes rf_nonlinear.rds + model_meta.json."""
    del random_state  # fixed in R (seed = 111)
    rs = rscript_path()
    if rs is None:
        raise RuntimeError(
            "Rscript not found on PATH. Install R and ensure Rscript.exe is available "
            "(Windows: add C:\\Program Files\\R\\R-x.y.z\\bin to PATH)."
        )
    script = R_DIR / "train_rf_nonlinear.R"
    if not script.is_file():
        raise FileNotFoundError(f"Missing R training script: {script}")

    out_dir = out_dir or ARTIFACTS
    out_dir.mkdir(parents=True, exist_ok=True)
    xlsx_abs = xlsx_path.resolve()
    out_abs = out_dir.resolve()

    cmd = [rs, str(script), str(xlsx_abs), str(out_abs)]
    proc = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        cwd=str(R_DIR),
    )
    if proc.returncode != 0:
        msg = proc.stderr or proc.stdout or "R training failed"
        raise RuntimeError(msg)
    if proc.stdout:
        print(proc.stdout, end="")
    if proc.stderr:
        print(proc.stderr, end="")
    rds = out_dir / "rf_nonlinear.rds"
    if not rds.is_file():
        raise RuntimeError(f"R training did not write {rds}")
    return rds


def load_bundle(path: Path | None = None) -> dict[str, Any] | None:
    """Load R model metadata; prediction uses rf_nonlinear.rds via Rscript."""
    out = path or (ARTIFACTS / "rf_nonlinear.rds")
    if not out.is_file():
        return None
    meta_path = ARTIFACTS / "model_meta.json"
    meta: dict[str, Any] = {}
    if meta_path.is_file():
        with open(meta_path, encoding="utf-8") as f:
            meta = json.load(f)
    return {
        "backend": "r_ranger",
        "rds_path": out,
        "meta": meta,
        "strains": meta.get("strains_in_training", meta.get("strains", [])),
        "study_effects_source": meta.get("study_effects_source", "lme4_r"),
    }


def predict_row(
    bundle: dict[str, Any],
    ph: float,
    temperature: float,
) -> dict[str, Any]:
    """Call R predict_rf_nonlinear.R; study effects are 0 in the R script (newdata)."""
    rs = rscript_path()
    if rs is None:
        raise RuntimeError("Rscript not on PATH; cannot run R predictions.")

    rds = bundle.get("rds_path")
    if rds is None or not Path(rds).is_file():
        raise FileNotFoundError("rf_nonlinear.rds missing — run: python train_model.py")

    script = R_DIR / "predict_rf_nonlinear.R"
    if not script.is_file():
        raise FileNotFoundError(f"Missing R script: {script}")

    req = {"ph": float(ph), "temperature": float(temperature)}
    tmp = tempfile.NamedTemporaryFile(
        mode="w", suffix=".json", delete=False, encoding="utf-8"
    )
    try:
        json.dump(req, tmp)
        tmp.flush()
        tmp.close()
        proc = subprocess.run(
            [rs, str(script), str(Path(rds).resolve()), tmp.name],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            cwd=str(R_DIR),
        )
        if proc.returncode != 0:
            raise RuntimeError(proc.stderr or proc.stdout or "R predict failed")
        raw_out = proc.stdout
        if raw_out is None:
            raw_out = ""
        text_out = raw_out.strip()
        if not text_out:
            raise RuntimeError(
                proc.stderr.strip()
                or "R predict produced no output on stdout (check R script and rf_nonlinear.rds)."
            )
        # If R printed warnings before JSON, take substring from first '{' to last '}'
        if not text_out.startswith("{"):
            i0 = text_out.find("{")
            i1 = text_out.rfind("}")
            if i0 >= 0 and i1 > i0:
                text_out = text_out[i0 : i1 + 1]
        out = json.loads(text_out)
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass

    # Normalize keys expected by FastAPI (ensure floats where needed)
    return {
        "mean": float(out["mean"]),
        "mean_trees": float(out["mean_trees"]),
        "ci_low": float(out["ci_low"]),
        "ci_high": float(out["ci_high"]),
        "units": str(out["units"]),
        "log_numerator_4log": float(out["log_numerator_4log"]),
        "k_conservative_5pct": float(out["k_conservative_5pct"]),
        "ct_4log_mean": _maybe_float(out.get("ct_4log_mean")),
        "ct_4log_conservative": _maybe_float(out.get("ct_4log_conservative")),
        "ct_4log_95_low": _maybe_float(out.get("ct_4log_95_low")),
        "ct_4log_95_high": _maybe_float(out.get("ct_4log_95_high")),
        "ct_units": str(out["ct_units"]),
    }


def _maybe_float(x: Any) -> float | None:
    if x is None:
        return None
    if isinstance(x, (int, float)):
        if isinstance(x, float) and pd.isna(x):
            return None
        return float(x)
    return None


def load_full_table(xlsx_path: Path | None = None) -> pd.DataFrame:
    path = xlsx_path or find_xlsx()
    if path is None:
        raise FileNotFoundError("Virus.xlsx or virus.xlsx not found in project root.")
    return load_lit_review(path)
