# claude-code-statusline — Claude Pro/Max usage variant (Windows)
# Shows: cwd | branch | model | context | rate limits | cost | effort
#
# Usage: Set in ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "pwsh -NoProfile -File /path/to/claude-pro-usage.ps1" }

$ErrorActionPreference = 'SilentlyContinue'
$ESC = [char]27

$input = @($Input) -join "`n"
try { $json = $input | ConvertFrom-Json } catch { Write-Host ""; exit 0 }

$cwd = if ($json.cwd) { $json.cwd } else { "" }
$parts = @()
$Sep = " $ESC[90m|$ESC[0m "

# CWD basename (white)
if ($cwd) {
    $basename = Split-Path $cwd -Leaf
    $folder = [char]::ConvertFromUtf32(0x1F4C2)
    $parts += "$ESC[37m$folder $basename$ESC[0m"
}

# Git branch — 🏠 (green) for main/master, ⎇ (cyan) for everything else
if ($cwd) {
    $branch = & git --no-optional-locks -C $cwd symbolic-ref --short HEAD 2>$null
    if ($branch) {
        if ($branch -eq "main" -or $branch -eq "master") {
            $icon = [char]::ConvertFromUtf32(0x1F3E0)
            $parts += "$ESC[32m$icon $branch$ESC[0m"
        } else {
            $icon = [char]::ConvertFromUtf32(0x2387)
            $parts += "$ESC[36m$icon $branch$ESC[0m"
        }
    }
}

# Model (light purple)
$model_name = $json.model.display_name
if ($model_name) {
    $brain = [char]::ConvertFromUtf32(0x1F9E0)
    $parts += "$ESC[38;5;147m$brain $model_name$ESC[0m"
}

# Context window — progress bar + % (color-coded green/yellow/red)
$used_pct = $json.context_window.used_percentage
if ($null -ne $used_pct) {
    $pct_int = [math]::Round($used_pct)
    if ($pct_int -ge 80) { $ctx_color = "$ESC[31m" }
    elseif ($pct_int -ge 50) { $ctx_color = "$ESC[33m" }
    else { $ctx_color = "$ESC[32m" }
    $bar_width = 10
    $filled = [math]::Floor($pct_int * $bar_width / 100)
    $empty = $bar_width - $filled
    $full_block = [char]::ConvertFromUtf32(0x2588)
    $light_block = [char]::ConvertFromUtf32(0x2592)
    $filled_bar = $full_block * $filled
    $empty_bar = $light_block * $empty
    $battery = [char]::ConvertFromUtf32(0x1F50B)
    $parts += "${ctx_color}$battery $filled_bar$ESC[90m$empty_bar${ctx_color} ${pct_int}%$ESC[0m"
}

# Rate limits — % + bar + window label + reset time (Claude.ai Pro/Max only)
# Format: 🚦 16% ██▒▒▒▒▒▒▒▒ 5h ↺4h24m | 1% █▒▒▒▒▒▒▒▒▒ 7d ↺4d9h
function Get-RateLimitSegment($label, $val, $resets_at, $now_ts) {
    if ($null -eq $val) { return "" }
    $val_int = [math]::Round([double]$val)
    if ($val_int -ge 80) { $rl_color = "$ESC[31m" }
    elseif ($val_int -ge 50) { $rl_color = "$ESC[33m" }
    else { $rl_color = "$ESC[32m" }
    $bar_width = 10
    $filled = [math]::Floor(($val_int * $bar_width + 50) / 100)
    if ($val_int -gt 0 -and $filled -eq 0) { $filled = 1 }
    $empty = $bar_width - $filled
    $full_block = [char]::ConvertFromUtf32(0x2588)
    $light_block = [char]::ConvertFromUtf32(0x2592)
    $filled_bar = $full_block * $filled
    $empty_bar = $light_block * $empty
    $reset_str = ""
    $resets_long = $resets_at -as [long]
    if ($resets_long -and $resets_long -gt $now_ts) {
        $remaining = $resets_long - $now_ts
        $r_d = [math]::Floor($remaining / 86400)
        $r_h = [math]::Floor(($remaining % 86400) / 3600)
        $r_m = [math]::Floor(($remaining % 3600) / 60)
        $recycle = [char]::ConvertFromUtf32(0x21BA)
        if ($r_d -gt 0) { $reset_str = " $recycle${r_d}d${r_h}h" }
        elseif ($r_h -gt 0) { $reset_str = " $recycle${r_h}h${r_m}m" }
        else { $reset_str = " $recycle${r_m}m" }
    }
    return "${rl_color}${val_int}% $filled_bar$ESC[90m$empty_bar${rl_color} ${label}${reset_str}$ESC[0m"
}

$five_h = $json.rate_limits.five_hour.used_percentage
$five_h_resets = $json.rate_limits.five_hour.resets_at
$seven_d = $json.rate_limits.seven_day.used_percentage
$seven_d_resets = $json.rate_limits.seven_day.resets_at

if ($null -ne $five_h -or $null -ne $seven_d) {
    $now_ts = [long][double]::Parse((Get-Date -UFormat %s))
    $seg5 = Get-RateLimitSegment "5h" $five_h $five_h_resets $now_ts
    $seg7 = Get-RateLimitSegment "7d" $seven_d $seven_d_resets $now_ts
    $rl_out = ""
    if ($seg5) { $rl_out = $seg5 }
    if ($seg5 -and $seg7) { $rl_out += " $ESC[90m|$ESC[0m " }
    if ($seg7) { $rl_out += $seg7 }
    if ($rl_out) {
        $traffic = [char]::ConvertFromUtf32(0x1F6A6)
        $parts += "$traffic $rl_out"
    }
}

# Cost (magenta)
$total_cost = $json.cost.total_cost_usd
if ($null -ne $total_cost) {
    $formatted = "{0:F3}" -f [double]$total_cost
    $money = [char]::ConvertFromUtf32(0x1F4B0)
    $parts += "$ESC[35m$money `$$formatted$ESC[0m"
}

# Effort level — color-coded by intensity (💭 low=green … max=red)
$effort_level = $json.effort.level
if ($effort_level) {
    switch ($effort_level) {
        "low"    { $eff_color = "$ESC[32m" }
        "medium" { $eff_color = "$ESC[36m" }
        "high"   { $eff_color = "$ESC[33m" }
        "xhigh"  { $eff_color = "$ESC[35m" }
        "max"    { $eff_color = "$ESC[31m" }
        default  { $eff_color = "$ESC[37m" }
    }
    $thought = [char]::ConvertFromUtf32(0x1F4AD)
    $parts += "${eff_color}$thought $effort_level$ESC[0m"
}

# Output
Write-Host -NoNewline ($parts -join $Sep)
