# One-time setup on Chris's laptop: run _tools\w2_refresh.ps1 on a schedule
# (Windows Task Scheduler, task "NFL W2 refresh", as the signed-in user).
# Times are the laptop's clock (US Central):
#   Tuesday   8:00 AM  first post for the week, after Monday night's game
#   Thursday  9:30 AM  after the Thursday-morning site update (new forecast)
#   Saturday  9:30 AM  final injury statuses, newer forecast
#   Sunday    7:00 AM  game-day forecast, before the noon kickoffs
#   Monday    9:30 AM  for Monday night
# The laptop must be on (or wake) at those times; a missed run starts when it
# comes back on. Remove with: Unregister-ScheduledTask -TaskName "NFL W2 refresh"
#
#   powershell -ExecutionPolicy Bypass -File _tools\install_w2_schedule.ps1 [-DataRefresh "uv run betting ..."]
#
# -DataRefresh: the betting repo's 2026 schedule + play-by-play fetch command,
# passed through to w2_refresh.ps1 (see there). Re-run this script to change it.

param([string]$DataRefresh = "")

$script = Join-Path $PSScriptRoot "w2_refresh.ps1"
$extra = if ($DataRefresh) { " -DataRefresh `"$($DataRefresh -replace '"', '\"')`"" } else { "" }
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument ("-NoProfile -ExecutionPolicy Bypass -File `"$script`"" + $extra) `
    -WorkingDirectory (Split-Path -Parent $PSScriptRoot)
$triggers = @(
    New-ScheduledTaskTrigger -Weekly -DaysOfWeek Tuesday  -At "8:00AM"
    New-ScheduledTaskTrigger -Weekly -DaysOfWeek Thursday -At "9:30AM"
    New-ScheduledTaskTrigger -Weekly -DaysOfWeek Saturday -At "9:30AM"
    New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday   -At "7:00AM"
    New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday   -At "9:30AM"
)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -WakeToRun `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
Register-ScheduledTask -TaskName "NFL W2 refresh" -Action $action -Trigger $triggers `
    -Settings $settings -Description "Run W2 and push its predictions to the NFL opponent report site" -Force
Write-Host "Scheduled. Test it now with: Start-ScheduledTask -TaskName 'NFL W2 refresh'"
