#!/usr/bin/env python3
import os
from transformers import AutoTokenizer, AutoModelForCausalLM, AutoModel
import torch

def download_model(model_name, model_type="llm"):
    print(f"Downloading {model_type} model: {model_name}")
    try:
        # Temporarily disable offline mode for downloading
        os.environ['HF_HUB_OFFLINE'] = '0'

        if model_type == "embedding":
            AutoModel.from_pretrained(model_name, torch_dtype=torch.float16)
            AutoTokenizer.from_pretrained(model_name)
        else:  # llm
            AutoModelForCausalLM.from_pretrained(model_name, torch_dtype=torch.float16)
            AutoTokenizer.from_pretrained(model_name)
        print(f"✓ {model_name} downloaded successfully")

        # Re-enable offline mode
        os.environ['HF_HUB_OFFLINE'] = '1'
    except Exception as e:
        print(f"✗ Failed to download {model_name}: {e}")
        os.environ['HF_HUB_OFFLINE'] = '1'

if __name__ == "__main__":
    # Primary models for production
    download_model("openai/gpt-oss-20b", "llm")
    download_model("Qwen/Qwen3-Embedding-4B", "embedding")

    # Fallback models
    download_model("Qwen/Qwen2-0.5B-Instruct", "llm")
    download_model("BAAI/bge-small-en-v1.5", "embedding")