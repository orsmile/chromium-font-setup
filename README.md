# Chromium Font Setup

Automatically install/update CJK fonts and configure per-script font mappings for Chrome, Brave, and Edge on Windows.

The default profile is tuned for high-DPI displays and multi-script CJK browsing:

| Setting | Default |
| --- | --- |
| Standard / Sans-serif · `Hant` | LINE Seed TW_TTF |
| Standard / Sans-serif · `Hans` | MiSans |
| Standard / Sans-serif · `Jpan` | LINE Seed JP_TTF |
| Standard / Sans-serif · `Kore` | LINE Seed Sans KR |
| Standard / Sans-serif · `Zyyy` | MiSans |
| Serif (all scripts) | Noto Serif TC |
| Fixed-width (all scripts) | Sarasa Mono TC |
| Default font size | 17 px |
| Fixed-width size | 16 px |
| Minimum font size | 13 px |

`Zyyy` is Chromium's common/default script entry. Pages without a more specific script mapping fall back to MiSans.

## Font sources

Fonts are downloaded from their upstream sources and are **not vendored in this repository**.

- [LINE Seed TW / JP / KR](https://seed.line.me/) — official LINE download, SIL Open Font License 1.1
- [MiSans](https://hyperos.mi.com/font/) — official Xiaomi HyperOS font package, MiSans Font License Agreement
- [Noto Serif CJK / Noto Serif TC](https://github.com/notofonts/noto-cjk) — GitHub releases, SIL Open Font License 1.1
- [Sarasa Gothic / Sarasa Mono TC](https://github.com/be5invis/Sarasa-Gothic) — GitHub releases, SIL Open Font License 1.1

Browser font family names match the Windows-installed font name tables (typically name ID 16 / typographic family):

| Family used in Preferences | Package |
| --- | --- |
| `LINE Seed TW_TTF` | LINE Seed TW desktop TTF |
| `LINE Seed JP_TTF` | LINE Seed JP desktop TTF (not App fonts) |
| `LINE Seed Sans KR` | LINE Seed KR TTF |
| `MiSans` | MiSans static TTF (not MiSans VF) |
| `Noto Serif TC` | Noto Serif TC |
| `Sarasa Mono TC` | Sarasa Mono TC |

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
6. Configures Chromium per-script font mappings (`Hant`, `Hans`, `Jpan`, `Kore`, `Zyyy`).

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

`standard`, `sansSerif`, `serif`, and `fixed` may be either:

- an object mapping Chromium script codes to family names (recommended), or
- a plain string, which is written only to the `Zyyy` common/default script entry.

Example browser configuration:

```json
{
  "browserSettings": {
    "standard": {
      "Hant": "LINE Seed TW_TTF",
      "Hans": "MiSans",
      "Jpan": "LINE Seed JP_TTF",
      "Kore": "LINE Seed Sans KR",
      "Zyyy": "MiSans"
    },
    "sansSerif": {
      "Hant": "LINE Seed TW_TTF",
      "Hans": "MiSans",
      "Jpan": "LINE Seed JP_TTF",
      "Kore": "LINE Seed Sans KR",
      "Zyyy": "MiSans"
    },
    "serif": {
      "Hant": "Noto Serif TC",
      "Hans": "Noto Serif TC",
      "Jpan": "Noto Serif TC",
      "Kore": "Noto Serif TC",
      "Zyyy": "Noto Serif TC"
    },
    "fixed": {
      "Hant": "Sarasa Mono TC",
      "Hans": "Sarasa Mono TC",
      "Jpan": "Sarasa Mono TC",
      "Kore": "Sarasa Mono TC",
      "Zyyy": "Sarasa Mono TC"
    },
    "defaultFontSize": 17,
    "defaultFixedFontSize": 16,
    "minimumFontSize": 13
  }
}
```

Script codes follow Chromium's font script identifiers:

| Code | Script |
| --- | --- |
| `Hant` | Traditional Chinese |
| `Hans` | Simplified Chinese |
| `Jpan` | Japanese |
| `Kore` | Korean |
| `Zyyy` | Common / default fallback |

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
- Direct-download sources such as LINE Seed and MiSans are checked by archive SHA-256. GitHub sources additionally record the matched release tag.
- LINE Seed JP installs desktop TTF only (`LINESeedJP_TTF_*.ttf`), not App fonts. MiSans installs static TTF only (`MiSans-*.ttf`), not `MiSansVF`.

## License

The scripts and configuration in this repository are licensed under the MIT License. Downloaded fonts retain their respective upstream licenses.
