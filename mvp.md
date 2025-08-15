## MVP: Build a branded VSCodium with a bundled .vsix

### Use this script
- Prefer `dev/build.sh` for MVP. It handles fetch → patch → build → package with simple flags.
- Reserve root `build.sh` for CI later.

### Branding
- Icons you should replace:
  - Windows: `src/stable/resources/win32/code.ico` (optionally other type icons in same folder) and `icons\stable`
  - macOS: `src/stable/resources/darwin/code.icns`
- Product name/IDs: edit once in `prepare_vscode.sh` (in the “product.json” section) to set:
  - `nameShort`, `nameLong`, `applicationName`, `win32DirName`, `win32NameVersion`, `win32RegValueName`, `win32ShellNameShort`
  - macOS/Windows identifiers where relevant (e.g., `darwinBundleIdentifier`, `win32AppUserModelId`)
- For easier rebases later, move these edits into `patches/user/branding.patch` when you’re ready.

### Bundle your .vsix as a built‑in extension (simple MVP)
- Place your `.vsix` files in `extensions-extra/` at the repo root.
- During build, after the app folder is created, `build.sh` injects your `.vsix` into `resources/app/extensions` so they ship in the final ZIP/EXE/MSI.
- By default, the normal built‑in extensions are also compiled. To exclude specific built‑ins from the final app, set `BUILTIN_EXTENSIONS_EXCLUDE` to a comma‑separated list of extension IDs (e.g., `publisher.name`):
  - PowerShell: `$env:BUILTIN_EXTENSIONS_EXCLUDE = 'ms-python.python,ms-vscode.cpptools'`
  - Bash: `$env:BUILTIN_EXTENSIONS_EXCLUDE="ms-python.python,ms-vscode.cpptools"`
  - The build now also temporarily removes matching local folders in `vscode/extensions` so they are not compiled (faster builds). Folders are restored automatically after packaging.
  - Alternatively, you can specify an allow‑list of local extensions to keep by setting `BUILTIN_EXTENSIONS_KEEP` with short folder names (e.g., `markdown-basics,markdown-language-features`).
  - Optional size reduction: set `**PRUNE_EXTENSION_SHARED_NODE_MODULES**=yes` (or `DISABLE_EXTENSION_SHARED_NODE_MODULES=yes`) to remove `resources/app/extensions/node_modules` after packaging. This reduces bundle size but may break extensions that rely on shared deps. Safe for minimal sets like only Markdown.
  - How to use:
    - Keep only Markdown built-ins and prune shared deps:
      - `$env:BUILTIN_EXTENSIONS_KEEP="markdown-basics,markdown-language-features,markdown-math,notebook-renderers,simple-browser,media-preview,ipynb,diff,theme-seti"`
      - `$env:DISABLE_EXTENSION_SHARED_NODE_MODULES="yes"`
    - Keep your exclude list and prune shared deps:
      - `$env:BUILTIN_EXTENSIONS_KEEP="ms-vscode.js-debug,ms-vscode.js-debug-companion,ms-vscode.vscode-js-profile-table,vscode.typescript-language-features,vscode.emmet,github,github-authentication,git,git-base,docker,python,go,cpp,csharp,java,rust,php,powershell,swift,groovy,julia,lua,ruby,r,perl,dart,typescript-basics,javascript,html,html-language-features,css,css-language-features,scss,less,xml,yaml,json,json-language-features,sql,shaderlab,hlsl,handlebars,pug,make,grunt,gulp,jake,restructuredtext,latex,terminal-suggest,tunnel-forwarding,objective-c,coffeescript,clojure,bat,ini,prompt-basics,razor,vb,types"`
      - `$env:PRUNE_EXTENSION_SHARED_NODE_MODULES="yes"`

Environment examples to enable this flow:
```powershell
# Set WiX path
$env:WIX = 'C:\Program Files (x86)\WiX Toolset v3.14\'
[Environment]::SetEnvironmentVariable('WIX', $env:WIX, 'User')

# Optionally exclude specific default built‑ins (comma‑separated IDs)
$env:BUILTIN_EXTENSIONS_EXCLUDE = 'ms-vscode.js-debug,ms-vscode.js-debug-companion,ms-vscode.vscode-js-profile-table,vscode.typescript-language-features,vscode.emmet,github,github-authentication,git,git-base,docker,python,go,cpp,csharp,java,rust,php,powershell,swift,groovy,julia,lua,ruby,r,perl,dart,typescript-basics,javascript,html,html-language-features,css,css-language-features,scss,less,xml,yaml,json,json-language-features,sql,shaderlab,hlsl,handlebars,pug,make,grunt,gulp,jake,restructuredtext,latex,terminal-suggest,tunnel-forwarding,objective-c,coffeescript,clojure,bat,ini,prompt-basics,razor,vb,types'
# Remove node_modules after packaging (optional size reduction)
$env:PRUNE_EXTENSION_SHARED_NODE_MODULES='yes'

OR

# Keep only (alternative to BUILTIN_EXTENSIONS_EXCLUDE)
$env:BUILTIN_EXTENSIONS_KEEP = 'markdown-basics,markdown-language-features,markdown-math,notebook-renderers,simple-browser,media-preview,ipynb,diff,theme-seti'
# Remove node_modules after packaging (optional size reduction)
$env:DISABLE_EXTENSION_SHARED_NODE_MODULES = 'yes'

# Only build EXE installers; skip zip/msi/cli/reh/reh-web
$env:SHOULD_BUILD_ZIP = 'no'
$env:SHOULD_BUILD_MSI = 'no'
$env:SHOULD_BUILD_MSI_NOUP = 'no'
$env:SHOULD_BUILD_CLI = 'no'
$env:SHOULD_BUILD_REH = 'no'
$env:SHOULD_BUILD_REH_WEB = 'no'

# Skip system installer .exe
$env:SHOULD_BUILD_EXE_SYS = 'no'

# Build
& "C:\Program Files\Git\bin\bash.exe" ./dev/build.sh -p
```

```bash
# Bash / Git Bash
./dev/build.sh -p
```

Notes:
- Any `.vsix` placed in `extensions-extra/` is bundled as a built‑in.
- Default built‑ins are included unless you exclude specific IDs via `BUILTIN_EXTENSIONS_EXCLUDE`.

### Ship default settings via a bundled “defaults” extension
- Edit `extensions-defaults/vsrat-defaults/extension/package.json` → `contributes.configurationDefaults` with your desired keys/values.
- The build packs and stages this extension automatically before compiling the app, so it gets injected like any other built‑in.
- To test or pack manually before a full build:
  - PowerShell (from repo root):
    ```powershell
    # Create VSIX and copy it into extensions-extra/
    node extensions-defaults\tools\pack-vsix.js
    Get-ChildItem extensions-extra\*.vsix
    ```
  - Or directly from the extension folder:
    ```powershell
    cd extensions-defaults\vsrat-defaults\extension
    npx --yes @vscode/vsce package
    Copy-Item *.vsix ..\..\..\extensions-extra\ -Force
    ```
- Verify after build: the folder `resources/app/extensions/vsrat.vsrat-defaults/` exists in the final app and contains `package.json`.
- Tip: This is the reliable way to provide runtime defaults. A `configurationDefaults` block in root `product.json` is merged at build time but is not honored by the runtime configuration service; use the bundled defaults extension for user‑visible defaults on first run.

#### Default settings (`extensions-defaults\vsrat-defaults\extension\package.json`)
```json
{
  "configurationDefaults": {
    "window.zoomLevel": 1,
    "window.menuBarVisibility": "compact",
    "window.commandCenter": false,

    "workbench.colorTheme": "Markdown Writer - light",
    "editor.fontWeight": "normal",
    // Controls the font family.
    "editor.fontFamily": "Input Mono Narrow,Calibri,Helvetica",
    // Configures font ligatures or font features. Can be either a boolean to enable/disable ligatures or a string for the value of the CSS 'font-feature-settings' property.
    "editor.fontLigatures": false,
    // Controls the font size in pixels.
    "editor.fontSize": 15,
    // Configures font variations. Can be either a boolean to enable/disable the translation from font-weight to font-variation-settings or a string for the value of the CSS 'font-variation-settings' property.
    "editor.fontVariations": false,
    "editor.lineNumbers": "on",
    "editor.glyphMargin": false,

    // Controls how lines should wrap.
    //  - off: Lines will never wrap.
    //  - on: Lines will wrap at the viewport width.
    //  - wordWrapColumn: Lines will wrap at `editor.wordWrapColumn`.
    //  - bounded: Lines will wrap at the minimum of viewport and `editor.wordWrapColumn`.
    "editor.wordWrap": "on",

    // Controls which editor is shown at startup, if none are restored from the previous session.
    //  - none: Start without an editor.
    //  - welcomePage: Open the Welcome page, with content to aid in getting started with VS Code and extensions.
    //  - readme: Open the README when opening a folder that contains one, fallback to 'welcomePage' otherwise. Note: This is only observed as a global configuration, it will be ignored if set in a workspace or folder configuration.
    //  - newUntitledFile: Open a new untitled text file (only applies when opening an empty window).
    //  - welcomePageInEmptyWorkbench: Open the Welcome page when opening an empty workbench.
    //  - terminal: Open a new terminal in the editor area.
    "workbench.startupEditor": "none",

    "workbench.statusBar.visible": false,
    "editor.unicodeHighlight.ambiguousCharacters": false,
    "security.workspace.trust.enabled": true,
    "security.workspace.trust.emptyWindow": true,
    "extensions.ignoreRecommendations": true,
    "extensions.autoCheckUpdates": false,
    "extensions.autoUpdate": false,
    "workbench.enableExperiments": false,
    "telemetry.telemetryLevel": "off",
    "update.mode": "none",
    "workbench.editor.empty.hint": "hidden",
    "workbench.startupEditor": "newUntitledFile",
    "workbench.tips.enabled": false,
    "editor.mouseWheelZoom": true,
    "editor.minimap.size": "proportional",
    "editor.minimap.scale": 2,
    "editor.minimap.autohide": "mouseover",
    "files.defaultLanguage": "markdown"

  }
}
```

### Build commands (Windows)
- Full build and package (first run):
```powershell
& "C:\Program Files\Git\bin\bash.exe" ./dev/build.sh -p
```
- Iterate quickly (skip re‑fetching sources, skip rebuild, package only):
```powershell
& "C:\Program Files\Git\bin\bash.exe" ./dev/build.sh -sop
```

### Use local ./vscode without fetching
- If you already have a local `./vscode` with your changes and a previous build output, you can package only (no fetch, no rebuild):
```powershell
& "C:\Program Files\Git\bin\bash.exe" ./dev/build.sh -sop
```

- If you changed code and need to rebuild using your local `./vscode` (no fetch):
  1) Build VS Code directly from your local tree
  ```powershell
  # From repo root
  cd .\vscode
  npm ci
  npm run gulp compile-build-without-mangling
  npm run gulp "vscode-win32-x64-min-ci"   # adjust arch if needed
  cd ..
  ```
  2) Package installers only (no fetch, no rebuild)
  ```powershell
  $env:SHOULD_BUILD_ZIP = 'no'
  $env:SHOULD_BUILD_MSI = 'no'
  $env:SHOULD_BUILD_MSI_NOUP = 'no'
  $env:SHOULD_BUILD_CLI = 'no'
  $env:SHOULD_BUILD_REH = 'no'
  $env:SHOULD_BUILD_REH_WEB = 'no'
  $env:SHOULD_BUILD_EXE_SYS = 'no'   # set 'yes' if you also want System Setup
  $env:SHOULD_BUILD_EXE_USR = 'yes'

  & "C:\Program Files\Git\bin\bash.exe" ./prepare_assets.sh
  ```

Notes:
- The package-only path (`-sop`) requires that a previous build exists (e.g., you ran a full build once). If missing, use the rebuild + package path above.
- All `.sh` commands must be run via Git Bash on Windows.

### Outputs
- Artifacts land in `assets\`, e.g.:
  - `assets\VSRAT-win32-x64-<version>.zip`
  - `assets\VSRATx64-<version>.msi` and/or `...updates-disabled-<version>.msi`
  - EXE installers (user/system) if enabled

### Dependencies (Windows)
- Windows SDK 10
- PowerShell
- Node 22.15.1
- Python 11.x
- Git Bash
- jq 1.8.1 (https://jqlang.org/download/)
- 7‑Zip (https://www.7-zip.org/download.html)
- WiX Toolset 3.14.1 (https://github.com/wixtoolset/wix3/releases)
- Inno Setup 6.5.0 (https://jrsoftware.org/isdl.php#stable)

See `docs/howto-build.md`.
