# PRBar

PRBar is a macOS 13+ menubar app (Swift + SwiftUI/AppKit) that shows your GitHub pull requests and their GitHub Actions/check status.

## Features

- Menubar status item + popover list of your PRs.
- Split popover workflow: click PR in left list, inspect rich details in right panel.
- Search + quick scope filters (`All`, `Personal`, `Org:<name>`).
- Per selected PR details in popover: metadata, labels/assignees/reviewers, merge state (when available), checks, workflow runs, jobs/steps, copy/open actions.
- Pin selected PR into floating always-on-top monitor window with multi-PR cards.
- Monitor controls: remove PR, refresh now, pause/resume auto-refresh.
- Settings window:
  - GitHub PAT save + validate
  - refresh interval
  - open/draft/closed options
  - fetch limit
  - scope configuration (personal/org + org multi-select)
  - tokenized repo allowlist (`owner/repo`) override
- Background refresh (default 60s) + manual refresh.
- Shared refresh scheduler coalesces concurrent refresh requests between popover/monitor.
- Keychain token storage (token is never written to defaults/cache).
- Local cache (PR data, org list, selected PRs, settings, etags) for fast startup.
- Pinned monitor PR IDs are persisted in user defaults.

## Build and Run

1. Open `/Users/bisegni/dev/github/bisegni/prbar/PRBar.xcodeproj` in Xcode.
2. Select the `PRBar` target.
3. Build and run on macOS.
4. Click the menubar icon to open the popover.

## GitHub PAT

Use either:

- Classic PAT: `repo` + `read:org` + `workflow`.
- Fine-grained PAT: read access to Pull Requests, Actions, Checks, and org metadata for your selected repos/orgs.

In PRBar Settings, paste token and click `Save + Validate`.

## Releases

Tag-based releases are automated with GitHub Actions.

- Trigger: push a tag like `v1.2.3`.
- Workflow builds `PRBar` on `macos-latest` and publishes:
  - `PRBar-1.2.3.dmg`
  - `PRBar.app.zip`

Install:
1. Download `.dmg` (preferred) or `.zip`.
2. Move `PRBar.app` to `/Applications`.
3. Launch from Applications.

Signing/notarization modes:
- Mode A (no Apple secrets): unsigned artifacts are still published; macOS may require right-click -> Open.
- Mode B (Apple secrets configured): app is signed, notarized, stapled, and DMG is notarized/stapled for cleaner Gatekeeper UX.

Required secrets for Mode B:
- `MACOS_CERT_P12` (base64-encoded Developer ID Application `.p12`)
- `MACOS_CERT_PASSWORD`
- `MACOS_SIGNING_IDENTITY`
- `APPLE_TEAM_ID`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

## API Notes / TODO

- PR list uses GitHub Search Issues API with scope-aware query strategy.
- Search requests are paginated (up to configured limit) and merged/deduplicated across scope units.
- PR details include review-state resolution (`approved`, `changes requested`, `review requested`, `pending`) from PR reviews + requested reviewers.
- Actions/check list state is loaded during refresh; workflow job/step details are loaded lazily only for selected PRs in the floating window.
- Full workflow log archive download is not implemented in-app yet; PRBar currently shows best-available check summaries/job-step state and provides `Open in Browser` links.
