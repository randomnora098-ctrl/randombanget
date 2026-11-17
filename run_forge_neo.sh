#!/usr/bin/env bash
set -e

# ==========================================================
# KONFIGURASI DEFAULT (Otomatis terisi Civitai API Key)
# ==========================================================
CIVITAI_API_KEY="${CIVITAI_API_KEY:-916ff2c247a9be5f8f3b0d3974af7863}"
CKPT_URLS="${CKPT_URLS:-}"   # Bisa diisi link Civitai/HF, pisahkan dengan koma
LORA_URLS="${LORA_URLS:-}"   # Bisa diisi link LoRA Civitai/HF, pisahkan dengan koma

echo "🔍 [1/5] Mengecek dependensi sistem & uv..."
if ! command -v aria2c >/dev/null 2>&1 || ! command -v python3.11 >/dev/null 2>&1 || ! command -v ffmpeg >/dev/null 2>&1; then
    echo "⏳ Menginstal aria2, python3.11, dan ffmpeg..."
    apt-get update -qq
    apt-get install -y aria2 git python3.11 python3.11-venv ffmpeg > /dev/null
else
    echo "✅ [Skip] Paket sistem (aria2, python3.11, ffmpeg) sudah terinstal."
fi

if ! command -v uv >/dev/null 2>&1; then
    echo "⏳ Menginstal uv..."
    pip install -q uv
else
    echo "✅ [Skip] uv sudah terinstal."
fi

echo "🔍 [2/5] Mengecek repository WebUI Forge Neo & Ekstensi (MOSS + SD-Hub)..."
WEBUI_DIR="/content/forge-neo"

clone_if_missing() {
    local repo_url="$1"
    local target_dir="$2"
    local branch="$3"

    if [ -d "$target_dir/.git" ]; then
        echo "✅ [Skip] Repo sudah ada: $target_dir"
    else
        echo "⏳ Meng-clone $repo_url ke $target_dir..."
        if [ -n "$branch" ]; then
            git clone -b "$branch" "$repo_url" "$target_dir"
        else
            git clone "$repo_url" "$target_dir"
        fi
    fi
}

clone_if_missing "https://github.com/Haoming02/sd-webui-forge-classic.git" "$WEBUI_DIR" "neo"
clone_if_missing "https://github.com/eduardoabreu81/moss-image-forge-neo.git" "$WEBUI_DIR/extensions/moss-image-forge-neo" ""
clone_if_missing "https://github.com/gutris1/sd-hub.git" "$WEBUI_DIR/extensions/sd-hub" ""

echo "🔍 [3/5] Mengonfigurasi Civitai API Key otomatis untuk SD-Hub..."
cat <<EOF > "$WEBUI_DIR/extensions/sd-hub/.sd-hub-config.json"
{
    "Token": {
        "civitai-api-key": "$CIVITAI_API_KEY",
        "huggingface-read": "",
        "huggingface-write": ""
    },
    "civitai-api-key": "$CIVITAI_API_KEY"
}
EOF
cp "$WEBUI_DIR/extensions/sd-hub/.sd-hub-config.json" "$WEBUI_DIR/sd-hub-token.json"
echo "✅ Civitai API Key berhasil dipasang otomatis ke SD-Hub!"

cd "$WEBUI_DIR"
if [ ! -f "$WEBUI_DIR/venv/bin/python" ]; then
    echo "⏳ Membuat virtual environment Python 3.11..."
    uv venv venv --python 3.11 --seed
else
    echo "✅ [Skip] Virtual environment (venv) sudah ada."
fi

CKPT_DIR="$WEBUI_DIR/models/Stable-diffusion"
LORA_DIR="$WEBUI_DIR/models/Lora"
TE_DIR="$WEBUI_DIR/models/text_encoder"
VAE_DIR="$WEBUI_DIR/models/VAE"
mkdir -p "$CKPT_DIR" "$LORA_DIR" "$TE_DIR" "$VAE_DIR"

smart_dl() {
    local raw_url="$1"
    local folder="$2"
    local filename="$3"

    # Gunakan Python untuk mendeteksi link Civitai (baik link halaman model maupun API download),
    # mengambil nama file asli dari API Civitai, dan menginjeksi ?token=CIVITAI_API_KEY otomatis
    read -r resolved_url resolved_name < <(python3 - "$raw_url" "$CIVITAI_API_KEY" "$filename" << 'PYEOF'
import sys, re, json, urllib.request
from urllib.parse import urlparse, unquote, urlencode, parse_qsl, urlunparse

url = sys.argv[1].strip()
api_key = sys.argv[2].strip()
fname = sys.argv[3].strip() if len(sys.argv) > 3 else ""

if "civitai.com" in url:
    m_ver = re.search(r"modelVersionId=(\d+)", url)
    m_mod = re.search(r"civitai\.com/models/(\d+)", url)
    try:
        if m_ver:
            ver_id = m_ver.group(1)
            req = urllib.request.Request(f"https://civitai.com/api/v1/model-versions/{ver_id}", headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=15) as resp:
                info = json.loads(resp.read().decode())
                if not fname: fname = info["files"][0]["name"]
                url = info["files"][0]["downloadUrl"]
        elif m_mod and "/api/download/" not in url:
            mod_id = m_mod.group(1)
            req = urllib.request.Request(f"https://civitai.com/api/v1/models/{mod_id}", headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=15) as resp:
                info = json.loads(resp.read().decode())
                ver_info = info["modelVersions"][0]
                if not fname: fname = ver_info["files"][0]["name"]
                url = ver_info["files"][0]["downloadUrl"]
    except Exception:
        pass
    if api_key:
        parsed = urlparse(url)
        qs = dict(parse_qsl(parsed.query))
        if "token" not in qs:
            qs["token"] = api_key
        url = urlunparse(parsed._replace(query=urlencode(qs)))
elif not fname:
    fname = unquote(urlparse(url).path.split("/")[-1])

print(f"{url} {fname or 'AUTO'}")
PYEOF
)

    if [ "$resolved_name" != "AUTO" ] && [ -n "$resolved_name" ]; then
        local target_path="$folder/$resolved_name"
        local aria2_ctrl="$target_path.aria2"

        if [ -f "$target_path" ] && [ ! -f "$aria2_ctrl" ]; then
            local filesize
            filesize=$(stat -c%s "$target_path" 2>/dev/null || echo 0)
            if [ "$filesize" -gt 1048576 ]; then
                local size_mb=$((filesize / 1048576))
                echo "✅ [Skip] $resolved_name sudah terunduh (${size_mb} MB)."
                return 0
            fi
        fi

        if [ -f "$aria2_ctrl" ]; then
            echo "🔄 Melanjutkan download yang sempat terputus: $resolved_name..."
        else
            echo "⬇️ Mengunduh $resolved_name..."
        fi

        aria2c --console-log-level=error -c -x 16 -s 16 -k 1M --allow-overwrite=false --auto-file-renaming=false "$resolved_url" -d "$folder" -o "$resolved_name"
    else
        echo "⬇️ Mengunduh dari link Civitai/Custom..."
        aria2c --console-log-level=error -c -x 16 -s 16 -k 1M --content-disposition=true --allow-overwrite=false --auto-file-renaming=false "$resolved_url" -d "$folder"
    fi
}

echo "🔍 [4/5] Mengecek & mengunduh model sesuai pilihan..."

# 1. Z-Image-Turbo AIO (1-File tanpa perlu VAE/TE terpisah)
if [ "${DL_Z_IMAGE_AIO:-true}" = "true" ]; then
    smart_dl "https://huggingface.co/SeeSee21/Z-Image-Turbo-AIO/resolve/main/z-image-turbo-fp8-aio.safetensors" "$CKPT_DIR" "z-image-turbo-fp8-aio.safetensors"
fi

# 2. Anima Pencil XL (1-File SDXL Anime)
if [ "${DL_ANIMA_PENCIL_XL:-false}" = "true" ]; then
    smart_dl "https://huggingface.co/bluepen5805/anima_pencil-XL/resolve/main/anima_pencil-XL_v500.safetensors" "$CKPT_DIR" "anima_pencil-XL_v500.safetensors"
fi

# 3. Anima 2B Base (Split)
if [ "${DL_ANIMA_2B:-false}" = "true" ]; then
    smart_dl "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/diffusion_models/anima-base-v1.0.safetensors" "$CKPT_DIR" "anima-base-v1.0.safetensors"
    smart_dl "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/text_encoders/qwen_3_06b_base.safetensors" "$TE_DIR" "qwen_3_06b_base.safetensors"
    smart_dl "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/vae/qwen_image_vae.safetensors" "$VAE_DIR" "qwen_image_vae.safetensors"
fi

# 4. MOSS-Image INT8 (Split)
if [ "${DL_MOSS_INT8:-false}" = "true" ]; then
    smart_dl "https://huggingface.co/Comfy-Org/MOSS-Image/resolve/main/diffusion_models/moss_image_sft_int8_convrot.safetensors" "$CKPT_DIR" "moss_image_sft_int8_convrot.safetensors"
    smart_dl "https://huggingface.co/Comfy-Org/MOSS-Image/resolve/main/text_encoders/qwen3.5_9b_int8_convrot.safetensors" "$TE_DIR" "qwen3.5_9b_int8_convrot.safetensors"
    smart_dl "https://huggingface.co/Comfy-Org/MOSS-Image/resolve/main/vae/flux2-vae.safetensors" "$VAE_DIR" "flux2-vae.safetensors"
fi

# 5. FLUX.2-Klein 4B (Split)
if [ "${DL_FLUX2_KLEIN:-false}" = "true" ]; then
    smart_dl "https://huggingface.co/Comfy-Org/Flux-2-Klein-4B/resolve/main/split_files/diffusion_models/flux-2-klein-4b.safetensors" "$CKPT_DIR" "flux-2-klein-4b.safetensors"
    smart_dl "https://huggingface.co/Comfy-Org/Flux-2-Klein-4B/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors" "$TE_DIR" "qwen_3_4b.safetensors"
    smart_dl "https://huggingface.co/Comfy-Org/MOSS-Image/resolve/main/vae/flux2-vae.safetensors" "$VAE_DIR" "flux2-vae.safetensors"
fi

# 6. Custom Link Civitai / HuggingFace (Otomatis pakai Civitai API Key)
if [ -n "$CKPT_URLS" ]; then
    IFS=',' read -ra ADDR <<< "$CKPT_URLS"
    for u in "${ADDR[@]}"; do
        [ -n "$u" ] && smart_dl "$u" "$CKPT_DIR" ""
    done
fi

if [ -n "$LORA_URLS" ]; then
    IFS=',' read -ra ADDR <<< "$LORA_URLS"
    for u in "${ADDR[@]}"; do
        [ -n "$u" ] && smart_dl "$u" "$LORA_DIR" ""
    done
fi

echo "🚀 [5/5] Menjalankan WebUI Forge Neo..."
export COMMANDLINE_ARGS="--uv --share --enable-insecure-extension-access --always-offload-from-vram ${EXTRA_ARGS:-}"
echo "export COMMANDLINE_ARGS=\"$COMMANDLINE_ARGS\"" > webui-user.sh
bash webui.sh -f
