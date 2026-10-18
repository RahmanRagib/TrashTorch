# TrashTorch

A vibecoded Windows cleanup tool that runs in an elevated console, creates a
System Restore point, then clears junk/temp files and reclaims disk space.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](#license)
![Platform: Windows](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-blue)

## Features

- Creates a **System Restore point** before touching anything.
- Cleans per-user temp, `INetCache`, thumbnail/icon cache, WER reports,
  crash dumps and browser caches (Edge/Chrome).
- Cleans system temp, Prefetch, Windows Update download cache, CBS logs,
  minidumps, `Downloaded Program Files`, WER archive/queue, orphaned
  `*.etl`/`*.log` files, `MEMORY.DMP` and LiveKernelReports.
- Empties the Recycle Bin.
- Runs **DISM** `/StartComponentCleanup /ResetBase`.
- Removes old restore points (keeps the newest) and caps shadow storage at 5%.
- Prints a before/after free-space summary and writes a per-run log.

## Requirements

- Windows 10 or 11
- PowerShell 5.1+ (ships with Windows)
- Administrator rights (the script requests elevation by itself)
- System Protection enabled for the system drive (for restore points)

## Usage

Clone or download the repo, then double-click `SystemCleanup.cmd` and approve
the UAC prompt. It elevates itself automatically.

```bat
SystemCleanup.cmd
```

### Dry run (recommended first)

Preview every action without deleting anything:

```bat
SystemCleanup.cmd -DryRun
```

You can also call the PowerShell script directly:

```powershell
.\Invoke-SystemCleanup.ps1 -DryRun   # preview
.\Invoke-SystemCleanup.ps1 -Yes      # run, skip the confirmation prompt
```

## Parameters

| Parameter | Description                                              |
| --------- | -------------------------------------------------------- |
| `-DryRun` | Show what would be cleaned without changing anything.    |
| `-Yes`    | Skip the interactive "Continue? (y/N)" prompt.           |

## Logs

A log is written to `C:\clean-logs\cleanup_<timestamp>.log`. The previous run's
log in that folder is deleted on each run, so only the latest one is kept.

## What it does NOT touch

- Personal files, Documents, Pictures, Downloads, etc.
- Installed programs or drivers
- Your registry

## Warning

- `/ResetBase` makes already-installed Windows updates non-uninstallable.
- Prefetch is cleared; the first boot after cleaning may be slightly slower.
- Always review the `-DryRun` output first if you are unsure.

## License

Released under the [MIT License](LICENSE).
