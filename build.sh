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
  npm run gulp compile-extension-media
  if [[ "${SKIP_MARKETPLACE_EXTENSIONS}" != "yes" ]]; then
    npm run gulp compile-extensions-build || export EXT_BUILD_FAILED=yes
  else
    echo "Skipping compile-extensions-build due to SKIP_MARKETPLACE_EXTENSIONS=yes"
  fi
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

  # Fallback: if marketplace extensions were skipped or failed, inject local VSIX into built app
  if [[ "${SKIP_MARKETPLACE_EXTENSIONS}" == "yes" || "${EXT_BUILD_FAILED}" == "yes" ]]; then
    echo "Using extension injection fallback (SKIP_MARKETPLACE_EXTENSIONS=${SKIP_MARKETPLACE_EXTENSIONS}, EXT_BUILD_FAILED=${EXT_BUILD_FAILED})"
    if compgen -G "../extensions-extra/*.vsix" > /dev/null; then
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
  fi

  if [[ "${SHOULD_BUILD_REH}" != "no" ]]; then
    npm run gulp minify-vscode-reh
    npm run gulp "vscode-reh-${VSCODE_PLATFORM}-${VSCODE_ARCH}-min-ci"
  fi

  if [[ "${SHOULD_BUILD_REH_WEB}" != "no" ]]; then
    npm run gulp minify-vscode-reh-web
    npm run gulp "vscode-reh-web-${VSCODE_PLATFORM}-${VSCODE_ARCH}-min-ci"
  fi

  cd ..
fi
