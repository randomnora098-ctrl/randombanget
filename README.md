# Forge Neo Colab (Anima • MOSS • Z-Image • FLUX.2-Klein + SD-Hub)

Stable Diffusion WebUI **Forge Neo** untuk Google Colab, dengan:
- Support **Anima 2B**, **MOSS-Image INT8**, **Z-Image-Turbo AIO**, **FLUX.2-Klein 4B**, **Anima Pencil XL**
- **SD-Hub** dengan Civitai API Key otomatis
- Download cukup pakai link Civitai / HuggingFace
- Smart check: skip clone / install / download yang sudah ada

## Cara pakai di Colab (Runtime → T4 GPU)

```python
!git clone https://github.com/randomnora098-ctrl/randombanget.git /content/randombanget 2>/dev/null || git -C /content/randombanget pull
!bash /content/randombanget/run_forge_neo.sh
```

### Dengan opsi model / link tambahan

```python
!git clone https://github.com/randomnora098-ctrl/randombanget.git /content/randombanget 2>/dev/null || git -C /content/randombanget pull
!DL_Z_IMAGE_AIO=true DL_ANIMA_2B=false DL_MOSS_INT8=false DL_FLUX2_KLEIN=false \
 CKPT_URLS="https://civitai.com/models/xxxx" \
 LORA_URLS="https://civitai.com/models/yyyy,https://civitai.com/models/zzzz" \
 bash /content/randombanget/run_forge_neo.sh
```

| Variabel | Default | Fungsi |
|---|---|---|
| `DL_Z_IMAGE_AIO` | `true` | Z-Image-Turbo FP8 AIO (1 file) |
| `DL_ANIMA_PENCIL_XL` | `false` | Anima Pencil XL (1 file SDXL) |
| `DL_ANIMA_2B` | `false` | Anima 2B + Qwen3 0.6B + VAE |
| `DL_MOSS_INT8` | `false` | MOSS-Image INT8 + Qwen3.5 9B + Flux2 VAE |
| `DL_FLUX2_KLEIN` | `false` | FLUX.2-Klein 4B + Qwen3 4B + Flux2 VAE |
| `CKPT_URLS` | kosong | Link checkpoint (pisah koma) |
| `LORA_URLS` | kosong | Link LoRA (pisah koma) |
| `CIVITAI_API_KEY` | sudah terisi | Override Civitai API key |
| `EXTRA_ARGS` | kosong | Argumen tambahan WebUI |

Atau buka notebook form: `Forge_Neo_Colab.ipynb`.
