# Instruction on editing \vscode\build\win32\code.iss:

## 1) Replace the per-user block in [Setup] (remove the old one with `PrivilegesRequired=lowest`):

```
#if "user" == InstallTarget
DefaultDirName={userpf}\{#DirName}
PrivilegesRequired=admin
#else
DefaultDirName={pf}\{#DirName}
#endif
```

## 2) Add the font to the [Files] section (place this entry at the end of the [Files] list, before the [Icons] section starts):

```
Source: "build\win32\fonts\InputMonoNarrow-Regular.ttf"; \
  DestDir: "{autofonts}"; \
  FontInstall: "Input Mono Narrow"; \
  Flags: onlyifdoesntexist uninsneveruninstall; \
  AfterInstall: RefreshFonts
```

## 3) Add this to the [Code] section (put it above your // Updates comment so RefreshFonts exists when the file rule runs):

```
// ---- Fonts: broadcast WM_FONTCHANGE after install ----
const
  WM_FONTCHANGE    = $001D;
  HWND_BROADCAST   = $FFFF;
  SMTO_ABORTIFHUNG = 2;

function SendMessageTimeout(hWnd, Msg, wParam, lParam, fuFlags, uTimeout: Cardinal; var lpdwResult: Cardinal): Cardinal;
  external 'SendMessageTimeoutW@user32.dll stdcall';

procedure RefreshFonts;
var
  R: Cardinal;
begin
  // Notify the system and running apps that fonts changed
  SendMessageTimeout(HWND_BROADCAST, WM_FONTCHANGE, 0, 0, SMTO_ABORTIFHUNG, 5000, R);
end;
```

## Notes:
- Ensure the font file exists at `build\win32\fonts\InputMonoNarrow-Regular.ttf`
- With `PrivilegesRequired=admin` in the user-install branch, `{autofonts}` will resolve to the system fonts directory, and the `WM_FONTCHANGE` broadcast makes the new font available immediately.

