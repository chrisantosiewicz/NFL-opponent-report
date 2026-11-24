"""Pull this week's NFL player prop lines into config/prop_lines.csv (runs on the laptop).

Uses the betting repo's Odds API key, client and credit ledger, so the key never
leaves the laptop and every credit is counted against the same monthly budget as
the game-line logger. Run it with the betting repo's environment, from this
repo's root:

    uv run --project C:/Betting_Algorithm python _tools/props_to_csv.py --season 2026 --week 12

Each game costs about one credit per market that has lines (4 markets, one
bookmaker group): roughly 50-65 credits for a full week. The run stops before
spending past --max-credits or past the betting repo's budget rules (cycle cap,
reserve floor). Raw responses are kept in the betting repo's data folder
(odds/props/, gitignored); only the median line per player and market is written
here, never prices.

Offline check (no API call): --from-dir <folder of saved event-odds JSON>.
"""

import argparse
import csv
import json
import re
import statistics
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

CSV = Path(__file__).resolve().parent.parent / "config" / "prop_lines.csv"
COLUMNS = ["season", "week", "game_id", "player", "market", "line", "books", "fetched_at"]
SPORT = "americanfootball_nfl"
MARKETS = {  # Odds API market key -> our name
    "player_pass_yds": "pass_yds",
    "player_rush_yds": "rush_yds",
    "player_reception_yds": "rec_yds",
    "player_receptions": "receptions",
}
CREDITS_PER_GAME = len(MARKETS)  # upper bound: one per market returned, one bookmaker group
LEDGER_PRIORITY = "nfl_props"
# The Tuesday of week 1 (weeks turn over on Tuesdays), as in w2_refresh.ps1.
WEEK1_TUESDAY = {2026: datetime(2026, 9, 8, tzinfo=UTC)}

# The Odds API's team names -> nflverse abbreviations (game_id is season_week_away_home).
TEAMS = {
    "Arizona Cardinals": "ARI", "Atlanta Falcons": "ATL", "Baltimore Ravens": "BAL",
    "Buffalo Bills": "BUF", "Carolina Panthers": "CAR", "Chicago Bears": "CHI",
    "Cincinnati Bengals": "CIN", "Cleveland Browns": "CLE", "Dallas Cowboys": "DAL",
    "Denver Broncos": "DEN", "Detroit Lions": "DET", "Green Bay Packers": "GB",
    "Houston Texans": "HOU", "Indianapolis Colts": "IND", "Jacksonville Jaguars": "JAX",
    "Kansas City Chiefs": "KC", "Las Vegas Raiders": "LV", "Los Angeles Chargers": "LAC",
    "Los Angeles Rams": "LA", "Miami Dolphins": "MIA", "Minnesota Vikings": "MIN",
    "New England Patriots": "NE", "New Orleans Saints": "NO", "New York Giants": "NYG",
    "New York Jets": "NYJ", "Philadelphia Eagles": "PHI", "Pittsburgh Steelers": "PIT",
    "San Francisco 49ers": "SF", "Seattle Seahawks": "SEA", "Tampa Bay Buccaneers": "TB",
    "Tennessee Titans": "TEN", "Washington Commanders": "WAS",
}


def game_id(season, week, event):
    away, home = TEAMS.get(event["away_team"]), TEAMS.get(event["home_team"])
    if not away or not home:
        raise ValueError(f"unknown team in {event['away_team']} @ {event['home_team']}")
    return f"{season}_{week:02d}_{away}_{home}"


def week_window(season, week):
    start = WEEK1_TUESDAY[season] + timedelta(weeks=week - 1)
    return start, start + timedelta(weeks=1)


def median_lines(event):
    """{(player, market): (median line, books)} from one event-odds response body."""
    points = {}
    for book in event.get("bookmakers", []):
        for m in book.get("markets", []):
            ours = MARKETS.get(m.get("key"))
            if not ours:
                continue
            seen = set()
            for o in m.get("outcomes", []):
                player, point = o.get("description"), o.get("point")
                if not player or point is None or o.get("name") not in ("Over", "Under"):
                    continue
                if (player, ours) in seen:  # Over and Under share the line; count the book once
                    continue
                seen.add((player, ours))
                points.setdefault((player, ours), []).append(float(point))
    return {k: (statistics.median(v), len(v)) for k, v in points.items()}


def rows_for(season, week, event, fetched_at):
    gid = game_id(season, week, event)
    stamp = fetched_at.astimezone(UTC).strftime("%Y-%m-%d %H:%M UTC")
    for (player, market), (line, books) in sorted(median_lines(event).items()):
        yield {"season": season, "week": week, "game_id": gid, "player": player,
               "market": market, "line": line, "books": books, "fetched_at": stamp}


def write_csv(new_rows):
    lines = CSV.read_text(encoding="utf-8").splitlines() if CSV.exists() else []
    header = [ln for ln in lines if ln.startswith("#")]
    body = [ln for ln in lines if not ln.startswith("#")]
    rows = list(csv.DictReader(body)) if body else []
    pulled = {r["game_id"] for r in new_rows}
    rows = [r for r in rows if r["game_id"] not in pulled] + new_rows  # newest pull per game
    rows.sort(key=lambda r: (int(r["season"]), int(r["week"]), r["game_id"], r["player"], r["market"]))
    with CSV.open("w", newline="", encoding="utf-8") as f:
        for ln in header:
            f.write(ln + "\n")
        w = csv.DictWriter(f, fieldnames=COLUMNS, lineterminator="\n")
        w.writeheader()
        w.writerows(rows)
    print(f"{CSV.name}: {len(rows)} lines ({len(new_rows)} from this pull, {len(pulled)} games)")


def from_dir(season, week, folder):
    out = []
    for p in sorted(Path(folder).glob("*.json")):
        event = json.loads(p.read_text(encoding="utf-8"))
        out += rows_for(season, week, event, datetime.fromtimestamp(p.stat().st_mtime, UTC))
    return out


def pull(season, week, max_credits):
    # The betting repo's own modules: settings (.env), client, ledger and spend rules.
    from betting.config import load_settings
    from betting.odds.books import REQUESTED_BOOKS
    from betting.odds.budget import LedgerEntry, Priority, check_spend, cycle_of
    from betting.odds.client import OddsApiError, OddsClient
    from betting.odds.snapshot import ledger_for

    settings = load_settings()
    client = OddsClient(settings.require_odds_api_key())
    ledger = ledger_for(settings.data_dir)
    raw_dir = settings.data_dir / "odds" / "props"
    raw_dir.mkdir(parents=True, exist_ok=True)

    now = client.now()
    start, end = week_window(season, week)
    events = client.get_events(SPORT, start=max(start, now), end=end).json()  # free
    print(f"{len(events)} games left in {season} week {week}")
    spent, out = 0, []
    for ev in sorted(events, key=lambda e: e["commence_time"]):
        if spent + CREDITS_PER_GAME > max_credits:
            print(f"stopping: --max-credits {max_credits} reached ({spent} spent)")
            break
        used, remaining = ledger.latest_usage(cycle_of(now))
        ok = check_spend(Priority.NFL_DECISION, CREDITS_PER_GAME, remaining=remaining, used=used)
        base = {"sport": SPORT, "priority": LEDGER_PRIORITY}
        if not ok.allowed:
            ledger.append(LedgerEntry(ts_utc=client.now(), event="skip", reason=ok.reason, **base))
            print(f"stopping: budget rule ({ok.reason})")
            break
        params = {"apiKey": client._key.reveal(), "regions": "us",
                  "bookmakers": ",".join(REQUESTED_BOOKS), "markets": ",".join(MARKETS),
                  "oddsFormat": "american", "dateFormat": "iso"}
        try:
            resp = client._get(f"/v4/sports/{SPORT}/events/{ev['id']}/odds", params)
        except OddsApiError as exc:
            u = exc.usage
            ledger.append(LedgerEntry(ts_utc=client.now(), event="error", reason=str(exc),
                                      cost=u and u.last, used=u and u.used,
                                      remaining=u and u.remaining, **base))
            print(f"{ev['away_team']} @ {ev['home_team']}: {exc}")
            continue
        ledger.append(LedgerEntry(ts_utc=resp.fetched_at, event="spend", redacted_url=resp.redacted_url,
                                  cost=resp.usage.last, used=resp.usage.used,
                                  remaining=resp.usage.remaining, **base))
        spent += resp.usage.last or CREDITS_PER_GAME
        name = re.sub(r"[^0-9A-Za-z_]", "", f"{resp.fetched_at:%Y%m%dT%H%MZ}_{ev['id']}")
        (raw_dir / f"{name}.json").write_bytes(resp.body)
        rows = list(rows_for(season, week, resp.json(), resp.fetched_at))
        print(f"{ev['away_team']} @ {ev['home_team']}: {len(rows)} lines, "
              f"{resp.usage.last} credits ({resp.usage.remaining} left)")
        out += rows
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--season", type=int, required=True)
    ap.add_argument("--week", type=int, required=True)
    ap.add_argument("--max-credits", type=int, default=70)
    ap.add_argument("--from-dir", help="saved event-odds JSON files; no API call")
    a = ap.parse_args()
    rows = from_dir(a.season, a.week, a.from_dir) if a.from_dir else pull(a.season, a.week, a.max_credits)
    if not rows:
        sys.exit("no prop lines pulled; config/prop_lines.csv left as is")
    write_csv(rows)


if __name__ == "__main__":
    main()
