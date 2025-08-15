#!/usr/bin/env bash
# shellcheck disable=SC1091

set -e

# DEBUG
# set -o xtrace

QUALITY="stable"
COLOR="blue1"
LOGO_PATH="icons/${QUALITY}/codium_cnl.svg"
LOGO_BORDER_PATH="icons/${QUALITY}/codium_cnl_w80_b8.svg"

while getopts ":il:" opt; do
  case "$opt" in
    i)
      export QUALITY="insider"
      export COLOR="orange1"
      ;;
    l)
      # Allow overriding the source logo (PNG or SVG)
      LOGO_PATH="${OPTARG}"
      LOGO_BORDER_PATH="${OPTARG}"
      ;;
    *)
      ;;
  esac
done

check_programs() { # {{{
  for arg in "$@"; do
    if ! command -v "${arg}" &> /dev/null; then
      echo "${arg} could not be found"
      exit 0
    fi
  done
} # }}}

check_programs "icns2png" "composite" "convert" "png2icns" "icotool" "rsvg-convert" "sed"

. ./utils.sh

log_info() { # {{{
  # Usage: log_info <message>
  # Emit debug/info messages to stderr for easier troubleshooting
  echo "[build_icons] $*" >&2
} # }}}

SRC_PREFIX=""
VSCODE_PREFIX=""

generate_logo_png() { # {{{
  # Usage: generate_logo_png <source> <width> <height> <output> [background]
  local SRC_FILE WIDTH HEIGHT OUT_FILE BGCOLOR EXT
  SRC_FILE="$1"
  WIDTH="$2"
  HEIGHT="$3"
  OUT_FILE="$4"
  BGCOLOR="${5:-}"
  EXT="${SRC_FILE##*.}"

  log_info "generate_logo_png: src=${SRC_FILE} ${WIDTH}x${HEIGHT} out=${OUT_FILE} bg='${BGCOLOR}'"
  if [[ "${EXT}" == "svg" ]]; then
    log_info "render SVG via rsvg-convert"
    if [[ -n "${BGCOLOR}" ]]; then
      rsvg-convert -b "${BGCOLOR}" -w "${WIDTH}" -h "${HEIGHT}" "${SRC_FILE}" -o "${OUT_FILE}"
    else
      rsvg-convert -w "${WIDTH}" -h "${HEIGHT}" "${SRC_FILE}" -o "${OUT_FILE}"
    fi
  else
    # Assume raster (e.g., PNG). Resize, preserve aspect ratio.
    log_info "resize raster via convert"
    convert "${SRC_FILE}" -resize "${WIDTH}x${HEIGHT}" "${OUT_FILE}"
  fi
}
 # }}}

build_darwin_main() { # {{{
  log_info "build_darwin_main"
  if [[ ! -f "${SRC_PREFIX}src/${QUALITY}/resources/darwin/code.icns" ]]; then
    log_info "creating darwin/code.icns"
    generate_logo_png "${LOGO_PATH}" 655 655 "code_logo.png"
    composite "code_logo.png" -gravity center "icons/template_macos.png" "code_1024.png"
    convert "code_1024.png" -resize 512x512 code_512.png
    convert "code_1024.png" -resize 256x256 code_256.png
    convert "code_1024.png" -resize 128x128 code_128.png

    png2icns "${SRC_PREFIX}src/${QUALITY}/resources/darwin/code.icns" code_512.png code_256.png code_128.png

    rm code_1024.png code_512.png code_256.png code_128.png code_logo.png
  else
    log_info "darwin/code.icns exists, skipping"
  fi
} # }}}

build_darwin_types() { # {{{
  log_info "build_darwin_types"
  generate_logo_png "${LOGO_BORDER_PATH}" 128 128 "code_logo.png"

  for file in "${VSCODE_PREFIX}"vscode/resources/darwin/*; do
    if [[ -f "${file}" ]]; then
      name=$(basename "${file}" '.icns')

      if [[ "${name}" != 'code' ]] && [[ ! -f "${SRC_PREFIX}src/${QUALITY}/resources/darwin/${name}.icns" ]]; then
        log_info "patching darwin type icon: ${name}.icns"
        icns2png -x -s 512x512 "${file}" -o .

        composite -blend 100% -geometry +323+365 "icons/corner_512.png" "${name}_512x512x32.png" "${name}.png"
        composite -geometry +359+374 "code_logo.png" "${name}.png" "${name}.png"

        convert "${name}.png" -resize 256x256 "${name}_256.png"

        png2icns "${SRC_PREFIX}src/${QUALITY}/resources/darwin/${name}.icns" "${name}.png" "${name}_256.png"

        rm "${name}_512x512x32.png" "${name}.png" "${name}_256.png"
      elif [[ "${name}" != 'code' ]]; then
        log_info "darwin type ${name}.icns exists, skipping"
      fi
    fi
  done

  rm "code_logo.png"
} # }}}

build_linux_main() { # {{{
  log_info "build_linux_main"
  if [[ ! -f "${SRC_PREFIX}src/${QUALITY}/resources/linux/code.png" ]]; then
    log_info "fetching linux/code.png"
    wget "https://raw.githubusercontent.com/VSCodium/icons/main/icons/linux/circle1/${COLOR}/paulo22s.png" -O "${SRC_PREFIX}src/${QUALITY}/resources/linux/code.png"
  else
    log_info "linux/code.png exists, skipping"
  fi

  mkdir -p "${SRC_PREFIX}src/${QUALITY}/resources/linux/rpm"

  if [[ ! -f "${SRC_PREFIX}src/${QUALITY}/resources/linux/rpm/code.xpm" ]]; then
    log_info "generating linux/rpm/code.xpm"
    convert "${SRC_PREFIX}src/${QUALITY}/resources/linux/code.png" "${SRC_PREFIX}src/${QUALITY}/resources/linux/rpm/code.xpm"
  else
    log_info "linux/rpm/code.xpm exists, skipping"
  fi

  # Also manage resources/linux/code.svg from provided logo (overwrite to keep in sync)
  local LINUX_SVG_DEST
  local LINUX_SVG_FALLBACK
  local EXT
  LINUX_SVG_DEST="${SRC_PREFIX}src/${QUALITY}/resources/linux/code.svg"
  LINUX_SVG_FALLBACK="icons/${QUALITY}/codium_clt.svg"

  mkdir -p "$(dirname "${LINUX_SVG_DEST}")"
  EXT="${LOGO_PATH##*.}"

  if [[ -f "${LINUX_SVG_DEST}" ]]; then
    log_info "will overwrite existing ${LINUX_SVG_DEST}"
  else
    log_info "will create ${LINUX_SVG_DEST}"
  fi

  if [[ -f "${LOGO_PATH}" && "${EXT}" == "svg" ]]; then
    log_info "using provided SVG logo for linux: ${LOGO_PATH} -> ${LINUX_SVG_DEST}"
    cp "${LOGO_PATH}" "${LINUX_SVG_DEST}" || cp "${LINUX_SVG_FALLBACK}" "${LINUX_SVG_DEST}"
    gsed -i \
      -e 's/\<width="[^"]*"/width="1024"/' \
      -e 's/\<height="[^"]*"/height="1024"/' \
      "${LINUX_SVG_DEST}" || true
  elif [[ -f "${LOGO_PATH}" ]]; then
    log_info "embedding raster logo into linux SVG: ${LOGO_PATH} -> ${LINUX_SVG_DEST}"
    generate_logo_png "${LOGO_PATH}" 1024 1024 "linux_code_1024.png" || true
    if [[ -f "linux_code_1024.png" ]]; then
      local DATAURI
      DATAURI=$(base64 -w 0 "linux_code_1024.png" 2>/dev/null || base64 "linux_code_1024.png" | tr -d '\n' || true)
      if [[ -n "${DATAURI}" ]]; then
        log_info "writing linux code.svg"
        cat > "${LINUX_SVG_DEST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024" version="1.1">
  <image width="1024" height="1024" href="data:image/png;base64,${DATAURI}"/>
</svg>
EOF
      else
        log_info "base64 encode failed; falling back to stock linux SVG"
        cp "${LINUX_SVG_FALLBACK}" "${LINUX_SVG_DEST}" || true
      fi
      rm -f "linux_code_1024.png"
    else
      log_info "failed to generate 1024px raster for linux; falling back to stock linux SVG"
      cp "${LINUX_SVG_FALLBACK}" "${LINUX_SVG_DEST}" || true
    fi
  else
    log_info "no provided logo; using stock linux SVG"
    cp "${LINUX_SVG_FALLBACK}" "${LINUX_SVG_DEST}" || true
  fi
} # }}}

build_media() { # {{{
  log_info "build_media (workbench code-icon.svg)"
  local DEST
  local EXT
  local FALLBACK
  DEST="${SRC_PREFIX}src/${QUALITY}/src/vs/workbench/browser/media/code-icon.svg"
  FALLBACK="icons/${QUALITY}/codium_clt.svg"

  mkdir -p "$(dirname "${DEST}")"

  EXT="${LOGO_PATH##*.}"

  if [[ -f "${DEST}" ]]; then
    log_info "will overwrite existing ${DEST}"
  else
    log_info "will create ${DEST}"
  fi

  if [[ -f "${LOGO_PATH}" && "${EXT}" == "svg" ]]; then
    log_info "using provided SVG logo: ${LOGO_PATH} -> ${DEST}"
    # Use provided SVG directly; normalize dimensions to 1024x1024
    cp "${LOGO_PATH}" "${DEST}" || cp "${FALLBACK}" "${DEST}"
    # Best-effort: ensure width/height are set to 1024 (ignore errors if attributes differ)
    gsed -i \
      -e 's/\<width="[^"]*"/width="1024"/' \
      -e 's/\<height="[^"]*"/height="1024"/' \
      "${DEST}" || true
  elif [[ -f "${LOGO_PATH}" ]]; then
    # Raster input: embed a 1024x1024 PNG into a simple SVG wrapper. If anything fails, fall back.
    log_info "embedding raster logo into SVG: ${LOGO_PATH} -> ${DEST}"
    generate_logo_png "${LOGO_PATH}" 1024 1024 "code_logo_1024.png" || true

    if [[ -f "code_logo_1024.png" ]]; then
      # Base64-encode without line breaks; try GNU base64 first, fallback to POSIX with tr
      local DATAURI
      DATAURI=$(base64 -w 0 "code_logo_1024.png" 2>/dev/null || base64 "code_logo_1024.png" | tr -d '\n' || true)

      if [[ -n "${DATAURI}" ]]; then
        log_info "writing data URI SVG to ${DEST}"
        cat > "${DEST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024" version="1.1">
  <image width="1024" height="1024" href="data:image/png;base64,${DATAURI}"/>
</svg>
EOF
      else
        log_info "base64 encode failed; falling back to stock SVG"
        cp "${FALLBACK}" "${DEST}"
        gsed -i 's|width="100" height="100"|width="1024" height="1024"|' "${DEST}" || true
      fi

      rm -f "code_logo_1024.png"
    else
      log_info "failed to generate raster 1024px image; falling back to stock SVG"
      cp "${FALLBACK}" "${DEST}"
      gsed -i 's|width="100" height="100"|width="1024" height="1024"|' "${DEST}" || true
    fi
  else
    # No provided logo; fall back to stock asset
    log_info "no provided logo found; using stock SVG"
    cp "${FALLBACK}" "${DEST}"
    gsed -i 's|width="100" height="100"|width="1024" height="1024"|' "${DEST}" || true
  fi
} # }}}

build_server() { # {{{
  log_info "build_server"
  if [[ ! -f "${SRC_PREFIX}src/${QUALITY}/resources/server/favicon.ico" ]]; then
    log_info "fetching server/favicon.ico"
    wget "https://raw.githubusercontent.com/VSCodium/icons/main/icons/win32/nobg/${COLOR}/paulo22s.ico" -O "${SRC_PREFIX}src/${QUALITY}/resources/server/favicon.ico"
  else
    log_info "server/favicon.ico exists, skipping"
  fi

  if [[ ! -f "${SRC_PREFIX}src/${QUALITY}/resources/server/code-192.png" ]]; then
    log_info "generating server/code-192.png"
    convert -size "192x192" "${SRC_PREFIX}src/${QUALITY}/resources/linux/code.png" "${SRC_PREFIX}src/${QUALITY}/resources/server/code-192.png"
  else
    log_info "server/code-192.png exists, skipping"
  fi

  if [[ ! -f "${SRC_PREFIX}src/${QUALITY}/resources/server/code-512.png" ]]; then
    log_info "generating server/code-512.png"
    convert -size "512x512" "${SRC_PREFIX}src/${QUALITY}/resources/linux/code.png" "${SRC_PREFIX}src/${QUALITY}/resources/server/code-512.png"
  else
    log_info "server/code-512.png exists, skipping"
  fi
} # }}}

build_windows_main() { # {{{
  log_info "build_windows_main"
  if [[ ! -f "${SRC_PREFIX}src/${QUALITY}/resources/win32/code.ico" ]]; then
    # Prefer generating from provided logo when available
    mkdir -p "${SRC_PREFIX}src/${QUALITY}/resources/win32"
    generate_logo_png "${LOGO_PATH}" 256 256 "code_logo.png"
    log_info "creating win32/code.ico"
    convert "code_logo.png" -define icon:auto-resize=256,128,96,64,48,32,24,20,16 "${SRC_PREFIX}src/${QUALITY}/resources/win32/code.ico" || {
      log_info "convert failed; fetching stock win32 ICO"
      # Fallback to fetching stock icon if generation fails
      wget "https://raw.githubusercontent.com/VSCodium/icons/main/icons/win32/nobg/${COLOR}/paulo22s.ico" -O "${SRC_PREFIX}src/${QUALITY}/resources/win32/code.ico"
    }
    rm -f code_logo.png
  else
    log_info "win32/code.ico exists, skipping"
  fi
} # }}}

build_windows_type() { # {{{
  log_info "build_windows_type file=$1 size=$2 bg=$3 logoSize=$4 gravity=$5"
  local FILE_PATH IMG_SIZE IMG_BG_COLOR LOGO_SIZE GRAVITY

  FILE_PATH="$1"
  IMG_SIZE="$2"
  IMG_BG_COLOR="$3"
  LOGO_SIZE="$4"
  GRAVITY="$5"

  if [[ ! -f "${FILE_PATH}" ]]; then
    log_info "creating ${FILE_PATH}"
    if [[ "${FILE_PATH##*.}" == "png" ]]; then
      convert -size "${IMG_SIZE}" "${IMG_BG_COLOR}" PNG32:"${FILE_PATH}"
    else
      convert -size "${IMG_SIZE}" "${IMG_BG_COLOR}" "${FILE_PATH}"
    fi

    generate_logo_png "${LOGO_PATH}" "${LOGO_SIZE}" "${LOGO_SIZE}" "code_logo.png"

    # If GRAVITY looks like +X+Y offsets, use -geometry; otherwise, use -gravity
    if [[ "${GRAVITY}" =~ ^[+-][0-9]+[+-][0-9]+$ ]]; then
      composite -geometry "${GRAVITY}" "code_logo.png" "${FILE_PATH}" "${FILE_PATH}"
    else
      composite -gravity "${GRAVITY}" "code_logo.png" "${FILE_PATH}" "${FILE_PATH}"
    fi
  else
    log_info "${FILE_PATH} exists, skipping"
  fi
} # }}}

build_windows_types() { # {{{
  log_info "build_windows_types"
  mkdir -p "${SRC_PREFIX}src/${QUALITY}/resources/win32"

  generate_logo_png "${LOGO_PATH}" 64 64 "code_logo.png" "#F5F6F7"

  for file in "${VSCODE_PREFIX}"vscode/resources/win32/*.ico; do
    if [[ -f "${file}" ]]; then
      name=$(basename "${file}" '.ico')

      if [[ "${name}" != 'code' ]] && [[ ! -f "${SRC_PREFIX}src/${QUALITY}/resources/win32/${name}.ico" ]]; then
        log_info "patching win32 type icon: ${name}.ico"
        icotool -x -w 256 "${file}"

        composite -geometry +150+185 "code_logo.png" "${name}_9_256x256x32.png" "${name}.png"

        convert "${name}.png" -define icon:auto-resize=256,128,96,64,48,32,24,20,16 "${SRC_PREFIX}src/${QUALITY}/resources/win32/${name}.ico"

        rm "${name}_9_256x256x32.png" "${name}.png"
      elif [[ "${name}" != 'code' ]]; then
        log_info "win32 type ${name}.ico exists, skipping"
      fi
    fi
  done

  build_windows_type "${SRC_PREFIX}src/${QUALITY}/resources/win32/code_70x70.png" "70x70" "canvas:transparent" "45" "center"
  build_windows_type "${SRC_PREFIX}src/${QUALITY}/resources/win32/code_150x150.png" "150x150" "canvas:transparent" "64" "+44+25"
  build_windows_type "${SRC_PREFIX}src/${QUALITY}/resources/win32/inno-big-100.bmp" "164x314" "xc:white" "126" "center"
  build_windows_type "${SRC_PREFIX}src/${QUALITY}/resources/win32/inno-big-125.bmp" "192x386" "xc:white" "147" "center"
  build_windows_type "${SRC_PREFIX}src/${QUALITY}/resources/win32/inno-big-150.bmp" "246x459" "xc:white" "190" "center"
  build_windows_type "${SRC_PREFIX}src/${QUALITY}/resources/win32/inno-big-175.bmp" "273x556" "xc:white" "211" "center"
  build_windows_type "${SRC_PREFIX}src/${QUALITY}/resources/win32/inno-big-200.bmp" "328x604" "xc:white" "255" "center"
  build_windows_type "${SRC_PREFIX}src/${QUALITY}/resources/win32/inno-big-225.bmp" "355x700" "xc:white" "273" "center"
  build_windows_type "${SRC_PREFIX}src/${QUALITY}/resources/win32/inno-big-250.bmp" "410x797" "xc:white" "317" "center"
  build_windows_type "${SRC_PREFIX}src/${QUALITY}/resources/win32/inno-small-100.bmp" "55x55" "xc:white" "44" "center"
  build_windows_type "${SRC_PREFIX}src/${QUALITY}/resources/win32/inno-small-125.bmp" "64x68" "xc:white" "52" "center"
  build_windows_type "${SRC_PREFIX}src/${QUALITY}/resources/win32/inno-small-150.bmp" "83x80" "xc:white" "63" "center"
  build_windows_type "${SRC_PREFIX}src/${QUALITY}/resources/win32/inno-small-175.bmp" "92x97" "xc:white" "76" "center"
  build_windows_type "${SRC_PREFIX}src/${QUALITY}/resources/win32/inno-small-200.bmp" "110x106" "xc:white" "86" "center"
  build_windows_type "${SRC_PREFIX}src/${QUALITY}/resources/win32/inno-small-225.bmp" "119x123" "xc:white" "103" "center"
  build_windows_type "${SRC_PREFIX}src/${QUALITY}/resources/win32/inno-small-250.bmp" "138x140" "xc:white" "116" "center"
  build_windows_type "${SRC_PREFIX}build/windows/msi/resources/${QUALITY}/wix-banner.bmp" "493x58" "xc:white" "50" "+438+6"
  build_windows_type "${SRC_PREFIX}build/windows/msi/resources/${QUALITY}/wix-dialog.bmp" "493x312" "xc:white" "120" "+22+152"

  rm code_logo.png
} # }}}

if [[ "${0}" == "${BASH_SOURCE[0]}" ]]; then
  log_info "starting build (QUALITY=${QUALITY} COLOR=${COLOR} LOGO_PATH=${LOGO_PATH})"
  build_darwin_main
  build_linux_main
  build_windows_main

  build_darwin_types
  build_windows_types

  build_media
  build_server
  log_info "build completed"
fi
