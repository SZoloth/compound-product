# Pastey Project Journal

## Overview
Pastey is a macOS clipboard history app inspired by Raycast's clipboard history. It runs as a menu bar app with a global hotkey and stores clipboard items (text, images, files, URLs) for fast search and reuse. It includes a local HTTP API for tooling and a CLI client for local search.

## Architecture Summary
- App: Swift + AppKit, built via SwiftPM (executable target `Pastey`).
- Storage: SQLite (with a plaintext fallback if SQLCipher is unavailable). Image blobs are stored on disk; metadata and text are stored in the DB.
- UI: Menu bar status item, search field, list with grouping (Today/Yesterday/etc.), preview panel, details panel, and actions (paste/copy/delete).
- Background capture: Debounced clipboard monitor with item deduping and retention policy.
- API: Local HTTP server bound to `127.0.0.1` (Network.framework), with `/health`, `/recent`, `/search`, `/item` endpoints.
- CLI: `PasteyCLI` SwiftPM executable that queries the local API and prints results.

## Work Log (Condensed)
- Reverse-engineered Raycast clipboard history UX and behaviors; captured desired layout and metadata display expectations.
- Built core clipboard history app (menu bar + hotkey). Implemented:
  - Clipboard capture for text/images/files, item preview and metadata panel.
  - Persistence with SQLite; on-disk storage for images; retention pruning.
  - Search + filtering by content type.
  - Pinned items and a Pinned section.
  - Ignore list for noisy sources.
  - Preferences window for retention, ignore list, and Local API.
- Updated app identity and naming to "Pastey".
- Added Local API:
  - `GET /health` -> health status.
  - `GET /recent?limit=N` -> latest items.
  - `GET /search?q=...&limit=N&type=...&pinned=1` -> filtered search.
  - `GET /item?id=...` -> item by ID.
- Implemented `PasteyCLI`:
  - `search`, `recent`, `health` commands.
  - `--limit`, `--type`, `--pinned`, `--port`, `--json` flags.
- Added tests:
  - Unit tests for CLI arg parsing and URL generation.
  - Integration tests that spin up a mock HTTP server and verify CLI fetch behavior.
  - E2E tests that hit a running Pastey Local API (skipped unless `PASTEY_E2E=1`).
- Added E2E runner script:
  - `scripts/run-e2e.sh` starts Pastey, waits for `/health`, runs E2E tests, then stops the app.

## Notable Decisions
- Local API is bound to `127.0.0.1` only for privacy and safety.
- E2E tests are opt-in (env guarded) to avoid failures on CI or systems without Pastey running.
- Images are stored on disk rather than in SQLite to avoid DB bloat and improve performance.

## How to Run
- App (debug):
  - `swift run Pastey`
- CLI (debug):
  - `swift run PasteyCLI search "query"`
- E2E test runner:
  - `/Users/samuelz/Pastey/scripts/run-e2e.sh`
  - Optional: `PASTEY_PORT=8899` to override default.

## Testing Summary
- `swift test` covers unit and integration tests.
- `PASTEY_E2E=1 swift test` runs live E2E tests against a running Pastey instance.
- `scripts/run-e2e.sh` automates the live E2E flow.

## Known Gaps / Future Work
- UX polish: spacing, preview layout, and empty states could be refined further.
- Deep linking from CLI results to open Pastey and focus an item.
- Background performance tuning for large histories (pagination and virtualized list).
- Optional secure storage (full SQLCipher integration) if required.

## Repository Notes
- Primary repo: `/Users/samuelz/Pastey` (GitHub: https://github.com/SZoloth/Pastey).
- Working dev tree: `/Users/samuelz/compound-product/clipboard-history` (kept in sync).
