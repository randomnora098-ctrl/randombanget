# Forge Neo Colab (Anima • MOSS • Z-Image • FLUX.2-Klein + SD-Hub)

Stable Diffusion WebUI **Forge Neo** untuk Google Colab:
- Support **Anima 2B**, **MOSS-Image INT8**, **Z-Image-Turbo AIO**, **FLUX.2-Klein 4B**, SDXL, dll
- **SD-Hub** dengan Civitai API Key otomatis
- Link Civitai (halaman model / API) otomatis diberi token & nama file asli
- Smart check: skip clone / install / download yang sudah ada, resume download yang putus

## Cara pakai di Colab (Runtime → T4 GPU)

```python
!git clone https://github.com/randomnora098-ctrl/randombanget.git /content/randombanget 2>/dev/null || git -C /content/randombanget pull
!bash /content/randombanget/run_forge_neo.sh
```

## Struktur

```
run_forge_neo.sh            # launcher
config/
├── extensions.txt          # daftar ekstensi:  URL_GIT [branch]
└── models/                 # 1 file per jenis model:  URL [nama_file]
    ├── checkpoints.txt     -> models/Stable-diffusion
    ├── text_encoder.txt    -> models/text_encoder
    ├── vae.txt             -> models/VAE
    ├── lora.txt            -> models/Lora
    ├── embeddings.txt      -> embeddings
    └── upscaler.txt        -> models/ESRGAN
```

- Baris diawali `#` = nonaktif. Hapus `#` untuk mengaktifkan.
- Mau jenis baru? Buat file baru, mis. `config/models/controlnet.txt` → otomatis ke `models/ControlNet`
  (nama lain otomatis ke `models/<nama_file>`).
- Model split (Anima / MOSS / FLUX.2-Klein): aktifkan baris yang sesuai di `checkpoints.txt`, `text_encoder.txt`, dan `vae.txt`.

## Variabel opsional

```python
!CKPT_URLS="https://civitai.com/models/xxxx" LORA_URLS="https://civitai.com/models/yyyy" \
 bash /content/randombanget/run_forge_neo.sh
```

| Variabel | Fungsi |
|---|---|
| `CKPT_URLS` / `LORA_URLS` / `VAE_URLS` | Link tambahan sekali pakai (pisah koma) |
| `CIVITAI_API_KEY` | Override Civitai API key |
| `HF_TOKEN` | Token HuggingFace untuk repo gated/private |
| `EXTRA_ARGS` | Argumen tambahan WebUI |
| `WEBUI_DIR` | Lokasi instalasi (default `/content/forge-neo`) |
