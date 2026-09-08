# Chromium Font Setup

Automatically install/update Traditional Chinese fonts and configure font settings for Chrome, Brave, and Edge on Windows.

The default profile is tuned for high-DPI displays and Traditional Chinese browsing:

| Setting | Default |
| --- | --- |
| Standard | LINE Seed TW |
| Sans-serif | LINE Seed TW |
| Serif | Noto Serif TC |
| Fixed-width | Sarasa Mono TC |
| Default font size | 17 px |
| Fixed-width size | 16 px |
| Minimum font size | 13 px |
| Chromium scripts | `Hant`, `Zyyy` |

## Font sources

Fonts are downloaded from their upstream sources and are **not vendored in this repository**.

- [LINE Seed TW](https://seed.line.me/index_tw.html) — official LINE download, SIL Open Font License 1.1
- [Noto Serif CJK / Noto Serif TC](https://github.com/notofonts/noto-cjk) — GitHub releases, SIL Open Font License 1.1
- [Sarasa Gothic / Sarasa Mono TC](https://github.com/be5invis/Sarasa-Gothic) — GitHub releases, SIL Open Font License 1.1

For GitHub-hosted fonts, the script scans recent releases for a matching asset instead of assuming that `/releases/latest` belongs to the required font family.

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1+ or PowerShell 7+
- Internet access
- Chrome, Brave, and/or Edge installed for browser configuration

Administrator privileges are **not required**. Fonts are installed for the current Windows user under `%LOCALAPPDATA%\Microsoft\Windows\Fonts`.

## Usage

Clone the repository and run:

```powershell
.\Set-WebFonts.ps1
```

The default action:

1. Downloads the configured fonts.
2. Compares each archive with the previously installed SHA-256 hash.
3. Installs/updates changed fonts for the current Windows user.
4. Finds `Default` and `Profile N` profiles in Chrome, Brave, and Edge.
5. Backs up each `Preferences` file.
6. Configures Chromium font mappings for Traditional Chinese (`Hant`) and the common/default script (`Zyyy`).

### Useful options

```powershell
# Preview changes without writing files, downloading archives, or requiring browsers to be closed
.\Set-WebFonts.ps1 -WhatIf

# Update fonts only
.\Set-WebFonts.ps1 -FontsOnly

# Configure browsers only
.\Set-WebFonts.ps1 -BrowsersOnly

# Configure only Brave
.\Set-WebFonts.ps1 -BrowsersOnly -Browser Brave

# Configure Chrome and Edge
.\Set-WebFonts.ps1 -BrowsersOnly -Browser Chrome,Edge

# Restore the most recent browser Preferences backup
.\Set-WebFonts.ps1 -Restore

# Restore only Brave from the most recent backup
.\Set-WebFonts.ps1 -Restore -Browser Brave
```

`-WhatIf` is a true dry-run: it may query upstream metadata (for example GitHub release information) so it can show which font asset would be used, but it does not create cache/state directories, download font archives, install fonts, create backups, or modify browser preferences.

## Important: close browsers first

Chrome, Brave, and Edge must be fully closed before their `Preferences` files are modified or restored. Chromium may overwrite external edits while it is running, so the script refuses to continue when a selected browser process is detected.

Font-only updates and `-WhatIf` previews do not require browsers to be closed.

## Backups and state

Runtime data is kept outside the repository:

```text
%LOCALAPPDATA%\ChromiumFontSetup\
├─ Backups\
├─ Cache\
└─ state.json
```

Each browser configuration run creates a timestamped backup before changing any profile.

## Customization

Edit `fonts.json` to change font sources or browser defaults.

Example browser configuration:

```json
{
  "browserSettings": {
    "standard": "LINE Seed TW",
    "sansSerif": "LINE Seed TW",
    "serif": "Noto Serif TC",
    "fixed": "Sarasa Mono TC",
    "defaultFontSize": 17,
    "defaultFixedFontSize": 16,
    "minimumFontSize": 13,
    "scripts": ["Hant", "Zyyy"]
  }
}
```

`Hant` targets Traditional Chinese. `Zyyy` supplies the common/default Chromium mapping so pages without a more specific script mapping still use the selected typography.

## Browser profile locations

The script currently detects these standard Windows user-data directories:

```text
Chrome: %LOCALAPPDATA%\Google\Chrome\User Data
Brave:  %LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data
Edge:   %LOCALAPPDATA%\Microsoft\Edge\User Data
```

Within each directory it configures profiles named `Default` and `Profile N` when a `Preferences` file exists.

## Scope and caveats

- A website that explicitly supplies its own web font can still override browser fallback fonts.
- The script intentionally changes only Chromium font-related preferences and font-size preferences.
- Per-user font registration avoids requiring elevation and avoids modifying the system-wide font directory.
- Direct-download sources such as LINE Seed TW are checked by archive SHA-256. GitHub sources additionally record the matched release tag.

## License

The scripts and configuration in this repository are licensed under the MIT License. Downloaded fonts retain their respective upstream licenses.