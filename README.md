# Installer Manager

PowerShell-based console utility that helps you keep an organized repository of installer files. It reads metadata from `installers-manifest.json`, lets you add installers by downloading or copying files into section folders, and provides several interactive menus for installing or reviewing the archived installers.

## Requirements

- Windows 10 or later
- PowerShell 7 (automatically detected and installed by `run-installer-manager.cmd` if missing)

## Getting Started

1. Double-click `run-installer-manager.cmd` or execute it from a terminal. It ensures PowerShell 7 is available and launches `installer-manager.ps1` with all paths configured.
2. Use the arrow keys and hotkeys shown in each menu to navigate. Primary options include:
   - Install installers by section
   - Add/update installers (download or local copy)
   - Show installers grouped by section

Installer files are stored under the `installers` directory. The manifest keeps track of names, versions, and section paths so the menus can display and launch the installers.

## Notes

- When adding installers manually, place them inside an appropriate subfolder under `installers` and run the script; it will scan and update the manifest automatically.
- Selective installation lists at most 10 entries per page. Use left/right arrows to switch pages and space/enter to toggle selection before pressing `1` to launch the chosen installers.
