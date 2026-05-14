"""Train rf_nonlinear via R (lme4 + ranger); writes artifacts/rf_nonlinear.rds. Requires Rscript on PATH."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Allow running as script
sys.path.insert(0, str(Path(__file__).resolve().parent))

from app.modeling import find_xlsx, train_and_save


def main() -> None:
    p = argparse.ArgumentParser(description="Train chlorine RF from Lit_Review sheet.")
    p.add_argument(
        "--xlsx",
        type=Path,
        default=None,
        help="Path to Virus.xlsx (default: Virus.xlsx or virus.xlsx in repo root)",
    )
    p.add_argument("--out", type=Path, default=None, help="Output directory for joblib")
    args = p.parse_args()
    xlsx = args.xlsx or find_xlsx()
    if xlsx is None:
        print("Could not find Virus.xlsx or virus.xlsx. Place it in the repository root.", file=sys.stderr)
        sys.exit(1)
    out = train_and_save(xlsx, out_dir=args.out)
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
