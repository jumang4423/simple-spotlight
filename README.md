# Simple Spotlight

Minimal macOS app launcher and calculator.

## Build

```sh
chmod +x scripts/build_app.sh
scripts/build_app.sh release
```

The app bundle is created at:

```text
build/Simple Spotlight.app
```

## Run

```sh
open "build/Simple Spotlight.app"
```

Press `Option + Space` to toggle the launcher.

macOS Spotlight must not be using the same shortcut. Change or disable Spotlight's shortcut in System Settings if needed.

## Scope

- Searches `.app` bundles in `/Applications` and `~/Applications`.
- Evaluates arithmetic and basic scientific expressions.
- No file search, web search, history, plugins, or settings UI.
