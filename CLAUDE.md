# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Before Committing

1. Run the status line and show the output so the user can visually confirm it looks correct:
   ```bash
   echo '{"cwd":"/tmp","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":65},"cost":{"total_cost_usd":0.042,"total_duration_ms":90000,"total_lines_added":12,"total_lines_removed":3},"effort":{"level":"high"}}' | bash statusline.sh
   ```
   Ask the user to confirm the output looks correct before proceeding.

2. Update docs if the change affects user-visible behavior or architecture:
   - **`README.md`** — segments reference table, features list, troubleshooting
   - **`CLAUDE.md`** — key implementation details, icons, segment logic

## Testing

There is no build system or test runner. Test by piping JSON to the scripts directly:

```bash
# Minimal — no git, no cost data
echo '{}' | bash statusline.sh

# Full — simulate Claude Code's JSON payload
echo '{"cwd":"/tmp","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":65},"cost":{"total_cost_usd":0.042,"total_duration_ms":90000,"total_lines_added":12,"total_lines_removed":3},"effort":{"level":"high"}}' | bash statusline.sh

# PowerShell (Windows)
'{}' | pwsh -NoProfile -File statusline.ps1
```

Verify ANSI colors render correctly in a real terminal (not just check stdout text).

## Architecture

The project has two parallel implementations of the same status line:

- **`statusline.sh`** — Bash, for macOS/Linux. Uses `jq` to parse JSON.
- **`statusline.ps1`** — PowerShell, for Windows. Uses built-in `ConvertFrom-Json`; writes raw UTF-8 bytes to stdout to preserve emoji.

Both follow an identical structure:

1. **`ENABLED_SEGMENTS` array** at the top — the user controls which segments appear by commenting/uncommenting entries.
2. **One section per segment** — each segment reads from `$input` (the JSON from stdin) or runs a git/shell command, then sets a `seg_<name>` variable containing a pre-colored ANSI string. Segments that have nothing to show leave `seg_<name>` empty.
3. **Assembly block** at the bottom — checks each `seg_*` in declaration order; non-empty ones are pushed to a `parts` array and joined with `$SEP`.

### Adding a segment

1. Add the segment name to `ENABLED_SEGMENTS`.
2. Add a section that sets `seg_yourname` — guard it with `segment_enabled "yourname"` (bash) or `Test-SegmentEnabled "yourname"` (PowerShell). Leave the variable empty if there is nothing to display.
3. Add `[[ -n "$seg_yourname" ]] && parts+=("$seg_yourname")` in the assembly block (bash), or `if ($seg_yourname) { $parts += $seg_yourname }` (PowerShell).
4. Add the segment to the reference table in `README.md`.

Both files must stay in sync — every new segment needs to be implemented in both `statusline.sh` and `statusline.ps1`.

### Key implementation details

- **`segment_enabled`** (bash) / **`Test-SegmentEnabled`** (PowerShell) — linear scan of `ENABLED_SEGMENTS`; only segments listed there are computed.
- **`file_mtime` / `portable_md5`** (bash only) — cross-platform helpers abstracting macOS vs. Linux `stat` and `md5`/`md5sum` differences.
- **`ts_errors` segment** — reads a cache file at `/tmp/tsc-errors-<md5-of-cwd>.txt` (or `$TEMP` on Windows) written by an external watcher; cache is ignored if older than 5 minutes. The script never runs `tsc` itself.
- **`git_branch` segment** — uses branch-specific icons: `🏠` (U+1F3E0, green) for `main`/`master`, `⎇` (U+2387, cyan) for all other branches. Both are standard Unicode — no Nerd Font required.
- **Git commands** always use `--no-optional-locks -C "$cwd"` to avoid interfering with the user's active git operations and to run against the correct working directory regardless of where the script is installed.
- **ANSI color codes** are constructed with `printf '\033[Nm...\033[0m'` in bash and `"$ESC[Nm...$ESC[0m"` in PowerShell where `$ESC = [char]27`.

### Examples

`examples/` contains self-contained minimal scripts (not wrappers around `statusline.sh`). They demonstrate how to build a stripped-down status line from scratch using the same pattern, useful as a reference for users who want to write their own.
