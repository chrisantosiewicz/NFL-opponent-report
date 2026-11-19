"""Copy W2's weekly predictions from the betting repo into config/w2_predictions.csv.

Run on the laptop after `betting predict week`, from this repo's root:

    python3 -I _tools/w2_to_csv.py C:/Betting_Algorithm/data/predictions/2026-week11/w2_<run>.json

Each game's row is replaced by the newest run's (rows for other games are
kept). Only the win chance, the model's margin and total, and the run id are
copied: no data hashes, no file paths, no cover or over chances.
"""

import csv
import json
import sys
from pathlib import Path

CSV = Path(__file__).resolve().parent.parent / "config" / "w2_predictions.csv"
COLUMNS = ["season", "week", "game_id", "home_team", "away_team",
           "w2_home_win", "w2_home_margin", "w2_total", "fit_run_id", "run_at"]


def read_existing():
    if not CSV.exists():
        return [], {}
    header, rows = [], {}
    with CSV.open(newline="", encoding="utf-8") as f:
        lines = f.read().splitlines()
    header = [ln for ln in lines if ln.startswith("#")]
    body = [ln for ln in lines if not ln.startswith("#")]
    for row in csv.DictReader(body):
        rows[row["game_id"]] = row
    return header, rows


def rows_from(path):
    run = json.loads(Path(path).read_text(encoding="utf-8"))
    run_at = run["run_at"][:16].replace("T", " ") + " UTC"
    for g in run["games"]:
        yield {
            "season": run["season"], "week": run["week"], "game_id": g["game_id"],
            "home_team": g["home_team"], "away_team": g["away_team"],
            "w2_home_win": round(g["p_home"], 4),
            "w2_home_margin": round(g["model_spread_home"] * -1, 2),
            "w2_total": round(g["model_total"], 2),
            "fit_run_id": run["fit_run_id"], "run_at": run_at,
        }


def main(paths):
    if not paths:
        sys.exit(__doc__)
    header, rows = read_existing()
    for p in paths:
        for r in rows_from(p):
            old = rows.get(r["game_id"])
            if old is None or old["run_at"] <= r["run_at"]:
                rows[r["game_id"]] = r
    ordered = sorted(rows.values(), key=lambda r: (int(r["season"]), int(r["week"]), r["game_id"]))
    with CSV.open("w", newline="", encoding="utf-8") as f:
        for ln in header:
            f.write(ln + "\n")
        w = csv.DictWriter(f, fieldnames=COLUMNS, lineterminator="\n")
        w.writeheader()
        w.writerows(ordered)
    print(f"{CSV.name}: {len(ordered)} games")


if __name__ == "__main__":
    main(sys.argv[1:])
