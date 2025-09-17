#!/usr/bin/env python3
import os
from transformers import AutoTokenizer, AutoModel
from huggingface_hub import snapshot_download

def download_dotsocr_model():
    model_name = "rednote-hilab/dots.ocr"
    weights_dir = "/workspace/weights/DotsOCR"

    print(f"Downloading DotsOCR model: {model_name} to {weights_dir}")

    try:
        # Temporarily disable offline mode for downloading
        os.environ['HF_HUB_OFFLINE'] = '0'
        os.environ['TRANSFORMERS_OFFLINE'] = '0'

        # Create weights directory
        os.makedirs(weights_dir, exist_ok=True)

        # Download model with trust_remote_code for DotsOCR
        print("Downloading model files...")
        snapshot_download(
            model_name,
            cache_dir="/root/.cache/huggingface",
            local_dir=weights_dir,
            trust_remote_code=True
        )

        print(f"✓ DotsOCR model downloaded to {weights_dir}")

        # Re-enable offline mode
        os.environ['HF_HUB_OFFLINE'] = '1'
        os.environ['TRANSFORMERS_OFFLINE'] = '1'

    except Exception as e:
        print(f"✗ Failed to download DotsOCR model: {e}")
        os.environ['HF_HUB_OFFLINE'] = '1'
        os.environ['TRANSFORMERS_OFFLINE'] = '1'
        raise

if __name__ == "__main__":
    download_dotsocr_model()