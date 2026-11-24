# Refresh W2's predictions on the live site (runs on Chris's laptop).
#
#   1. in the betting repo: refreshes the 2026 game data (schedule, live pbp),
#      rebuilds W2's features (`betting predict build-features`), then runs W2
#      for this NFL week (`betting predict week`). Predict only: never refits.
#   2. copies the newest run into config/w2_predictions.csv (_tools/w2_to_csv.py),
#   3. on Thursday and Saturday mornings, pulls NFL prop lines into
#      config/prop_lines.csv (_tools/props_to_csv.py, the betting repo's Odds API
#      key and budget): Thursday for the Thu/Fri games, Saturday for the rest,
#   4. commits and pushes the CSVs to main. That push starts an update run of the
#      site (.github/workflows/weekly-report.yml), so the page shows the new
#      numbers a few minutes later. W2's last run before each kickoff is the one
#      graded.
#
# Run by hand:      powershell -ExecutionPolicy Bypass -File _tools\w2_refresh.ps1
# Run on schedule:  _tools\install_w2_schedule.ps1 (once)
# Log:              <this repo>\data\w2_refresh.log (data\ is not committed)

param(
    [string]$BettingDir = "C:\Betting_Algorithm",
    [int]$Season = 2026,
    # The Tuesday of week 1 (weeks turn over on Tuesdays). 2026: Thu Sep 10 opener.
    [datetime]$Week1Tuesday = "2026-09-08",
    [int]$Week = 0,  # 0 = work it out from today's date
    # Override the betting repo's data refresh with another command (run from
    # $BettingDir). Blank = the default below.
    [string]$DataRefresh = "",
    [switch]$SkipDataRefresh,
    # Prop lines: auto = Thursday (Thu/Fri games) and Saturday (the rest).
    [ValidateSet("auto", "always", "never")] [string]$Props = "auto",
    [int]$PropCredits = 60
)

# The betting repo's weekly data refresh (from its "Add predictions" thread,
# as run on Nov 19): download ONLY the 2026 schedule, rebuild games.parquet
# from the stored raw schedules, pull 2026 live play-by-play and weekly player
# stats. Nothing for 2025 (the held-out season), no Odds API. Do not swap in
# `betting build` (reads raw 2025 pbp), `betting insights refresh` or
# `betting nfl fetch-pbp`.
$DefaultRefresh = 'uv run python -c "from datetime import UTC, datetime; from pathlib import Path; from betting.nfl import pipeline; from betting.insights.live_data import fetch_live; d=Path(''data''); now=datetime.now(UTC); print(pipeline.fetch_schedules(d,[2026],now)); g=pipeline.build(d); print(pipeline.games_report(g,[2026])[1]); print(fetch_live(d,2026,now))"'
if (-not $DataRefresh) { $DataRefresh = $DefaultRefresh }

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force -Path (Join-Path $repo "data") | Out-Null
$log = Join-Path $repo "data\w2_refresh.log"
function Log($msg) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg" | Tee-Object -FilePath $log -Append }

try {
    if ($Week -le 0) { $Week = [math]::Floor(((Get-Date).Date - $Week1Tuesday.Date).TotalDays / 7) + 1 }
    if ($Week -lt 1 -or $Week -gt 22) { Log "Week $Week is outside the season; nothing to do."; exit 0 }
    Log "W2 refresh: $Season week $Week"

    Push-Location $BettingDir
    try {
        $data = Join-Path $BettingDir "data"
        $env:UV_CACHE_DIR = Join-Path $BettingDir ".venv\uv-cache"
        if ($SkipDataRefresh) {
            Log "Skipping the data refresh: using the betting repo's current game data."
        } else {
            Log "Data refresh (2026 schedule, live play-by-play)"
            Invoke-Expression $DataRefresh
            if ($LASTEXITCODE -ne 0) { throw "data refresh exited $LASTEXITCODE" }
        }
        uv run betting predict build-features --data-dir $data
        if ($LASTEXITCODE -ne 0) { throw "betting predict build-features exited $LASTEXITCODE" }
        uv run betting predict week --season $Season --week $Week --data-dir $data
        if ($LASTEXITCODE -ne 0) { throw "betting predict week exited $LASTEXITCODE" }
    } finally { Pop-Location }

    $dir = Join-Path $BettingDir ("data\predictions\{0}-week{1:D2}" -f $Season, $Week)
    $json = Get-ChildItem -Path $dir -Filter "w2_*.json" | Sort-Object Name | Select-Object -Last 1
    if (-not $json) { throw "No w2_*.json in $dir" }
    Log "Newest run: $($json.Name)"

    Push-Location $repo
    try {
        git pull --rebase --quiet origin main
        if ($LASTEXITCODE -ne 0) { throw "git pull failed" }
        python -I _tools/w2_to_csv.py $json.FullName
        if ($LASTEXITCODE -ne 0) { throw "w2_to_csv.py exited $LASTEXITCODE" }
        git add config/w2_predictions.csv
        $msg = "W2: $Season week $Week ($($json.BaseName))"
        $day = (Get-Date).DayOfWeek
        if ($Props -eq "always" -or ($Props -eq "auto" -and ($day -eq "Thursday" -or $day -eq "Saturday"))) {
            $propArgs = @("--season", $Season, "--week", $Week, "--max-credits", $PropCredits)
            if ($day -eq "Thursday") { $propArgs += "--through-friday" }
            Log "Prop lines: $($propArgs -join ' ')"
            uv run --project $BettingDir python -I _tools/props_to_csv.py @propArgs
            if ($LASTEXITCODE -eq 0) { git add config/prop_lines.csv; $msg += " + prop lines" }
            else { Log "Prop pull exited $LASTEXITCODE; pushing W2 without new prop lines." }
        }
        git diff --cached --quiet
        if ($LASTEXITCODE -eq 0) { Log "No change in W2's numbers or prop lines; nothing to push."; exit 0 }
        git commit --quiet -m $msg
        git push --quiet origin HEAD:main
        if ($LASTEXITCODE -ne 0) { throw "git push failed" }
        Log "Pushed; the site's update run starts now."
    } finally { Pop-Location }
} catch {
    Log "FAILED: $_"
    exit 1
}
