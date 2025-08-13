#!/usr/bin/env bash
# shellcheck disable=SC1091

set -ex

. version.sh

if [[ "${SHOULD_BUILD}" == "yes" ]]; then
  echo "MS_COMMIT=\"${MS_COMMIT}\""

  . prepare_vscode.sh

  cd vscode || { echo "'vscode' dir not found"; exit 1; }

  export NODE_OPTIONS="--max-old-space-size=8192"

  npm run monaco-compile-check
  npm run valid-layers-check

  npm run gulp compile-build-without-mangling
  # Temporarily hide local extensions from the source tree so they are not compiled or included
  # Prefer KEEP mode if provided; otherwise fall back to EXCLUDE mode
  if [[ -n "${BUILTIN_EXTENSIONS_KEEP}" || -n "${BUILTIN_EXTENSIONS_EXCLUDE}" ]]; then
    EXT_OFF_DIR="$(pwd)/../.extensions_off"
    rm -rf "${EXT_OFF_DIR}" && mkdir -p "${EXT_OFF_DIR}"
    : > "${EXT_OFF_DIR}/.moved"

    if [[ -n "${BUILTIN_EXTENSIONS_KEEP}" ]]; then
      echo "Keeping only built-ins: ${BUILTIN_EXTENSIONS_KEEP}"
      pushd extensions >/dev/null
      KEEP_SET=",${BUILTIN_EXTENSIONS_KEEP},"
      shopt -s dotglob nullglob
      for d in */ ; do
        d="${d%/}"
        [[ "${d}" == "node_modules" ]] && continue
        if [[ ",${KEEP_SET}," != *",${d},"* ]]; then
          echo "Temporarily disabling local extension for build: ${d} (KEEP mode)"
          mv "${d}" "${EXT_OFF_DIR}/${d}" 2>/dev/null || true
          echo "${d}" >> "${EXT_OFF_DIR}/.moved"
        fi
      done
      shopt -u dotglob nullglob
      popd >/dev/null
    else
      IFS=',' read -ra _exclude <<< "${BUILTIN_EXTENSIONS_EXCLUDE}"
      for id in "${_exclude[@]}"; do
        id="${id//[[:space:]]/}"
        [[ -z "${id}" ]] && continue
        candidates=()
        if [[ "${id}" == *.* ]]; then
          short_id="${id##*.}"
          candidates+=("${short_id}")
        else
          candidates+=("${id}")
        fi
        moved_once="no"
        for cand in "${candidates[@]}"; do
          if [[ -d "extensions/${cand}" ]]; then
            echo "Temporarily disabling local extension for build: ${cand} (requested: ${id})"
            mv "extensions/${cand}" "${EXT_OFF_DIR}/${cand}" 2>/dev/null || true
            echo "${cand}" >> "${EXT_OFF_DIR}/.moved"
            moved_once="yes"
            break
          fi
        done
        if [[ "${moved_once}" != "yes" ]]; then
          echo "Note: local extension folder not found for exclusion: ${id}"
        fi
      done
    fi
  fi
  npm run gulp compile-extension-media
  # If BUILTIN_EXTENSIONS_EXCLUDE is set, pre-disable those marketplace built-ins
  # so the compile-extensions-build step won't try to download them
  if [[ -n "${BUILTIN_EXTENSIONS_EXCLUDE}" ]]; then
    node -e '
      const fs=require("fs"), path=require("path"), os=require("os");
      const dstDir=path.join(os.homedir(), ".vscode-oss-dev", "extensions");
      fs.mkdirSync(dstDir, { recursive: true });
      const controlPath=path.join(dstDir, "control.json");
      let control={};
      try{ control=JSON.parse(fs.readFileSync(controlPath, "utf8")); }catch{}
      const raw=(process.env.BUILTIN_EXTENSIONS_EXCLUDE||"").split(",").map(s=>s.trim()).filter(Boolean);
      for(const id of raw){
        control[id] = "disabled";
        // If someone passed short folder names like "js-debug", also add ms-vscode.js-debug variants
        if(!id.includes(".") && id === "js-debug") control["ms-vscode.js-debug"] = "disabled";
      }
      fs.writeFileSync(controlPath, JSON.stringify(control, null, 2));
      console.log("Prepared built-in extensions control.json:", controlPath);
    '
  fi
  npm run gulp compile-extensions-build
  npm run gulp minify-vscode

  if [[ "${OS_NAME}" == "osx" ]]; then
    # generate Group Policy definitions
    node build/lib/policies darwin

    npm run gulp "vscode-darwin-${VSCODE_ARCH}-min-ci"

    find "../VSCode-darwin-${VSCODE_ARCH}" -print0 | xargs -0 touch -c

    . ../build_cli.sh

    VSCODE_PLATFORM="darwin"
  elif [[ "${OS_NAME}" == "windows" ]]; then
    # generate Group Policy definitions
    node build/lib/policies win32

    # in CI, packaging will be done by a different job
    if [[ "${CI_BUILD}" == "no" ]]; then
      . ../build/windows/rtf/make.sh

      npm run gulp "vscode-win32-${VSCODE_ARCH}-min-ci"

      if [[ "${VSCODE_ARCH}" != "x64" ]]; then
        SHOULD_BUILD_REH="no"
        SHOULD_BUILD_REH_WEB="no"
      fi

      . ../build_cli.sh
    fi

    VSCODE_PLATFORM="win32"
  else # linux
    # in CI, packaging will be done by a different job
    if [[ "${CI_BUILD}" == "no" ]]; then
      npm run gulp "vscode-linux-${VSCODE_ARCH}-min-ci"

      find "../VSCode-linux-${VSCODE_ARCH}" -print0 | xargs -0 touch -c

      . ../build_cli.sh
    fi

    VSCODE_PLATFORM="linux"
  fi

  # Targeted prune of specific built-in extensions (post-build, Windows-safe)
  # Provide comma-separated IDs in BUILTIN_EXTENSIONS_EXCLUDE, e.g. "ms-python.python,ms-vscode.cpptools"
  if [[ -n "${BUILTIN_EXTENSIONS_EXCLUDE}" ]]; then
    out_dir="../VSCode-${VSCODE_PLATFORM}-${VSCODE_ARCH}/resources/app/extensions"
    if [[ -d "${out_dir}" ]]; then
      IFS=',' read -ra _exclude <<< "${BUILTIN_EXTENSIONS_EXCLUDE}"
      for id in "${_exclude[@]}"; do
        id="${id//[[:space:]]/}"
        [[ -z "$id" ]] && continue
        # Accept both folder names (e.g., "emmet") and publisher.name (e.g., "vscode.emmet" or "ms-vscode.js-debug")
        candidates=("$id")
        if [[ "$id" == *.* ]]; then
          short_id="${id##*.}"
          candidates+=("$short_id")
        fi
        excluded_once="no"
        for cand in "${candidates[@]}"; do
          if [[ -d "${out_dir}/${cand}" ]]; then
            echo "Excluding built-in extension: ${cand} (requested: ${id})"
            tmp_root="$(mktemp -d 2>/dev/null || echo ".")"
            tmp="${tmp_root}/${cand}._trash_$(date +%s)"
            mv "${out_dir}/${cand}" "$tmp" 2>/dev/null || continue
            # Delete synchronously to avoid packaging the renamed folder
            rm -rf "$tmp"
            excluded_once="yes"
            break
          fi
        done
        if [[ "$excluded_once" != "yes" ]]; then
          echo "Warning: requested exclusion not found: ${id}"
        fi
      done
    fi
  fi

  # Optionally prune shared production deps bundle used by extensions to reduce size
  # WARNING: Removing this may break extensions that rely on shared deps. Safe for minimalist sets (e.g., markdown-only).
  if [[ "${PRUNE_EXTENSION_SHARED_NODE_MODULES}" == "yes" || "${DISABLE_EXTENSION_SHARED_NODE_MODULES}" == "yes" ]]; then
    shared_nm_dir="../VSCode-${VSCODE_PLATFORM}-${VSCODE_ARCH}/resources/app/extensions/node_modules"
    if [[ -d "${shared_nm_dir}" ]]; then
      echo "Pruning shared extensions node_modules"
      rm -rf "${shared_nm_dir}"
    fi
  fi

  # Inject any local VSIX into the final app, if provided
  if compgen -G "../extensions-extra/*.vsix" > /dev/null; then
    echo "Injecting local VSIX into built app (EXT_BUILD_FAILED=${EXT_BUILD_FAILED})"
    out_dir="../VSCode-${VSCODE_PLATFORM}-${VSCODE_ARCH}/resources/app/extensions"
    mkdir -p "${out_dir}"
    for vsix in ../extensions-extra/*.vsix; do
      if command -v 7z.exe >/dev/null 2>&1; then
        ext_id=$(7z.exe x -so "$vsix" extension/package.json 2>/dev/null | jq -r '.publisher+"."+.name')
      else
        ext_id=$(unzip -p "$vsix" 'extension/package.json' 2>/dev/null | jq -r '.publisher+"."+.name')
      fi
      [[ -z "$ext_id" || "$ext_id" == "null.null" ]] && continue
      tmpdir=$(mktemp -d)
      if command -v 7z.exe >/dev/null 2>&1; then
        7z.exe x -y "$vsix" -o"$tmpdir" >/dev/null
      else
        unzip -q "$vsix" -d "$tmpdir"
      fi
      if [[ -d "$tmpdir/extension" ]]; then
        shopt -s dotglob nullglob
        mkdir -p "${out_dir}/$ext_id"
        cp -R "$tmpdir/extension/"* "${out_dir}/$ext_id/" || true
        shopt -u dotglob nullglob
      else
        mkdir -p "${out_dir}/$ext_id"
        cp -R "$tmpdir/"* "${out_dir}/$ext_id/" || true
      fi
      rm -rf "$tmpdir"
    done
  fi

  if [[ "${SHOULD_BUILD_REH}" != "no" ]]; then
    npm run gulp minify-vscode-reh
    npm run gulp "vscode-reh-${VSCODE_PLATFORM}-${VSCODE_ARCH}-min-ci"
  fi

  if [[ "${SHOULD_BUILD_REH_WEB}" != "no" ]]; then
    npm run gulp minify-vscode-reh-web
    npm run gulp "vscode-reh-web-${VSCODE_PLATFORM}-${VSCODE_ARCH}-min-ci"
  fi

  # Restore any temporarily disabled local extensions
  if [[ -f "../.extensions_off/.moved" ]]; then
    while IFS= read -r moved || [[ -n "$moved" ]]; do
      [[ -z "$moved" ]] && continue
      if [[ -d "../.extensions_off/${moved}" ]]; then
        echo "Restoring local extension: ${moved}"
        mv "../.extensions_off/${moved}" "extensions/${moved}" 2>/dev/null || true
      fi
    done < "../.extensions_off/.moved"
    rm -rf "../.extensions_off"
  fi

  cd ..
fi
