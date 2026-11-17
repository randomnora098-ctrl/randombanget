#!/usr/bin/env bash
# ==========================================================
# Forge Neo Colab Launcher
# - Daftar ekstensi : config/extensions.txt
# - Daftar model    : config/models/*.txt (1 file per jenis model)
# ==========================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
WEBUI_DIR="${WEBUI_DIR:-/content/forge-neo}"

CIVITAI_API_KEY="${CIVITAI_API_KEY:-916ff2c247a9be5f8f3b0d3974af7863}"
HF_TOKEN="${HF_TOKEN:-}"

# ----------------------------------------------------------
# 1. Dependensi sistem
# ----------------------------------------------------------
echo "🔍 [1/5] Mengecek dependensi sistem & uv..."
if ! command -v aria2c >/dev/null 2>&1 || ! command -v python3.11 >/dev/null 2>&1 || ! command -v ffmpeg >/dev/null 2>&1; then
    echo "⏳ Menginstal aria2, python3.11, dan ffmpeg..."
    apt-get update -qq
    apt-get install -y aria2 git python3.11 python3.11-venv ffmpeg > /dev/null
else
    echo "✅ [Skip] Paket sistem sudah terinstal."
fi

if ! command -v uv >/dev/null 2>&1; then
    echo "⏳ Menginstal uv..."
    pip install -q uv
else
    echo "✅ [Skip] uv sudah terinstal."
fi

# ----------------------------------------------------------
# 2. Forge Neo + ekstensi (dari config/extensions.txt)
# ----------------------------------------------------------
clone_if_missing() {
    local repo_url="$1" target_dir="$2" branch="$3"
    if [ -d "$target_dir/.git" ]; then
        echo "✅ [Skip] Sudah ada: $(basename "$target_dir")"
    else
        echo "⏳ Clone $repo_url ..."
        if [ -n "$branch" ]; then
            git clone --depth 1 -b "$branch" "$repo_url" "$target_dir"
        else
            git clone --depth 1 "$repo_url" "$target_dir"
        fi
    fi
}

# Baca file list: abaikan baris kosong & komentar (#), hapus CR
read_list() {
    [ -f "$1" ] || return 0
    sed -e 's/\r$//' -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' || true
}

echo "🔍 [2/5] Mengecek Forge Neo & ekstensi..."
clone_if_missing "https://github.com/Haoming02/sd-webui-forge-classic.git" "$WEBUI_DIR" "neo"
mkdir -p "$WEBUI_DIR/extensions"

while read -r ext_url ext_branch; do
    [ -z "$ext_url" ] && continue
    ext_name="$(basename "$ext_url" .git)"
    clone_if_missing "$ext_url" "$WEBUI_DIR/extensions/$ext_name" "$ext_branch"
done < <(read_list "$CONFIG_DIR/extensions.txt")

# ----------------------------------------------------------
# 3. Token otomatis untuk SD-Hub
# ----------------------------------------------------------
echo "🔍 [3/5] Konfigurasi token SD-Hub..."
SD_HUB_DIR="$WEBUI_DIR/extensions/sd-hub"
if [ -d "$SD_HUB_DIR" ]; then
    python3 - "$SD_HUB_DIR/.sd-hub-config.json" "$WEBUI_DIR/sd-hub-token.json" "$CIVITAI_API_KEY" "$HF_TOKEN" << 'PYEOF'
import json, os, sys
civit, hf = sys.argv[3], sys.argv[4]
for path in sys.argv[1:3]:
    data = {}
    if os.path.exists(path):
        try:
            data = json.load(open(path))
        except Exception:
            data = {}
    tok = data.setdefault("Token", {})
    tok["civitai-api-key"] = civit
    if hf:
        tok["huggingface-read"] = hf
    data["civitai-api-key"] = civit
    json.dump(data, open(path, "w"), indent=4)
PYEOF
    echo "✅ Civitai API Key terpasang di SD-Hub."
else
    echo "⚠️ SD-Hub tidak ada di extensions.txt, dilewati."
fi

cd "$WEBUI_DIR"
if [ ! -f "$WEBUI_DIR/venv/bin/python" ]; then
    echo "⏳ Membuat virtual environment Python 3.11..."
    uv venv venv --python 3.11 --seed
else
    echo "✅ [Skip] venv sudah ada."
fi

# ----------------------------------------------------------
# 4. Download model (dari config/models/*.txt)
# ----------------------------------------------------------
# Nama file list -> folder tujuan di dalam WebUI
model_dir_for() {
    case "$1" in
        checkpoints)  echo "$WEBUI_DIR/models/Stable-diffusion" ;;
        lora)         echo "$WEBUI_DIR/models/Lora" ;;
        vae)          echo "$WEBUI_DIR/models/VAE" ;;
        text_encoder) echo "$WEBUI_DIR/models/text_encoder" ;;
        embeddings)   echo "$WEBUI_DIR/embeddings" ;;
        upscaler)     echo "$WEBUI_DIR/models/ESRGAN" ;;
        controlnet)   echo "$WEBUI_DIR/models/ControlNet" ;;
        *)            echo "$WEBUI_DIR/models/$1" ;;
    esac
}

# Resolve link Civitai (halaman model / API) -> direct link + token + nama file asli
resolve_url() {
    python3 - "$1" "$CIVITAI_API_KEY" "$2" << 'PYEOF'
import sys, re, json, urllib.request
from urllib.parse import urlparse, unquote, urlencode, parse_qsl, urlunparse

url, api_key = sys.argv[1].strip(), sys.argv[2].strip()
fname = sys.argv[3].strip() if len(sys.argv) > 3 else ""

def get_json(u):
    h = {"User-Agent": "Mozilla/5.0"}
    if api_key:
        h["Authorization"] = f"Bearer {api_key}"
    with urllib.request.urlopen(urllib.request.Request(u, headers=h), timeout=20) as r:
        return json.loads(r.read().decode())

if "civitai.com" in url:
    try:
        m_ver = re.search(r"modelVersionId=(\d+)", url)
        m_dl = re.search(r"/api/download/models/(\d+)", url)
        m_mod = re.search(r"civitai\.com/models/(\d+)", url)
        if m_ver or m_dl:
            info = get_json(f"https://civitai.com/api/v1/model-versions/{(m_ver or m_dl).group(1)}")
        elif m_mod:
            info = get_json(f"https://civitai.com/api/v1/models/{m_mod.group(1)}")["modelVersions"][0]
        else:
            info = None
        if info:
            files = info["files"]
            f = next((x for x in files if x.get("primary")), files[0])
            fname = fname or f["name"]
            if not m_dl:
                url = f["downloadUrl"]
    except Exception as e:
        print(f"⚠️ Gagal baca info Civitai ({e}), pakai link langsung.", file=sys.stderr)
    if api_key:
        p = urlparse(url)
        qs = dict(parse_qsl(p.query))
        qs.setdefault("token", api_key)
        url = urlunparse(p._replace(query=urlencode(qs)))
elif not fname:
    fname = unquote(urlparse(url).path.rsplit("/", 1)[-1].split("?")[0])

print(f"{url}\t{fname or 'AUTO'}")
PYEOF
}

smart_dl() {
    local raw_url="$1" folder="$2" filename="$3"
    local resolved_url resolved_name
    IFS=$'\t' read -r resolved_url resolved_name < <(resolve_url "$raw_url" "$filename")

    local hf_header=()
    if [ -n "$HF_TOKEN" ] && [[ "$resolved_url" == *huggingface.co* ]]; then
        hf_header=(--header="Authorization: Bearer $HF_TOKEN")
    fi

    if [ -n "$resolved_name" ] && [ "$resolved_name" != "AUTO" ]; then
        local target="$folder/$resolved_name"
        if [ -f "$target" ] && [ ! -f "$target.aria2" ] && [ "$(stat -c%s "$target" 2>/dev/null || echo 0)" -gt 1048576 ]; then
            echo "✅ [Skip] $resolved_name ($(( $(stat -c%s "$target") / 1048576 )) MB)"
            return 0
        fi
        [ -f "$target.aria2" ] && echo "🔄 Lanjutkan: $resolved_name" || echo "⬇️ Download: $resolved_name"
        aria2c --console-log-level=error --summary-interval=0 -c -x 16 -s 16 -k 1M \
            --allow-overwrite=false --auto-file-renaming=false "${hf_header[@]}" \
            "$resolved_url" -d "$folder" -o "$resolved_name" || echo "❌ Gagal: $resolved_name"
    else
        echo "⬇️ Download: ${raw_url}"
        aria2c --console-log-level=error --summary-interval=0 -c -x 16 -s 16 -k 1M \
            --content-disposition=true --allow-overwrite=false --auto-file-renaming=false "${hf_header[@]}" \
            "$resolved_url" -d "$folder" || echo "❌ Gagal: $raw_url"
    fi
}

echo "🔍 [4/5] Mengecek & mengunduh model..."
shopt -s nullglob
for list in "$CONFIG_DIR"/models/*.txt; do
    kind="$(basename "$list" .txt)"
    dest="$(model_dir_for "$kind")"
    mkdir -p "$dest"
    entries="$(read_list "$list")"
    [ -z "$entries" ] && continue
    echo "📂 [$kind] -> $dest"
    while read -r url name; do
        [ -n "$url" ] && smart_dl "$url" "$dest" "$name"
    done <<< "$entries"
done

# Link tambahan via variabel (opsional, pisah koma)
add_from_env() {
    local urls="$1" dest="$2"
    [ -z "$urls" ] && return 0
    mkdir -p "$dest"
    IFS=',' read -ra arr <<< "$urls"
    for u in "${arr[@]}"; do
        u="$(echo "$u" | xargs)"
        [ -n "$u" ] && smart_dl "$u" "$dest" ""
    done
}
add_from_env "${CKPT_URLS:-}" "$(model_dir_for checkpoints)"
add_from_env "${LORA_URLS:-}" "$(model_dir_for lora)"
add_from_env "${VAE_URLS:-}"  "$(model_dir_for vae)"

# ----------------------------------------------------------
# 5. Jalankan WebUI
# ----------------------------------------------------------
echo "🚀 [5/5] Menjalankan WebUI Forge Neo..."
COMMANDLINE_ARGS="--uv --share --enable-insecure-extension-access --always-offload-from-vram ${EXTRA_ARGS:-}"
echo "export COMMANDLINE_ARGS=\"$COMMANDLINE_ARGS\"" > webui-user.sh
bash webui.sh -f
