import os
from openai import OpenAI
from transformers.utils.versions import require_version
from PIL import Image
import io
import base64
from file_parser.utils.prompts import prompt_map
from file_parser.dots_ocr.vllm import vllm
import yaml

with open('config.yaml', 'r') as file:
    config = yaml.safe_load(file)

IP = config.get("ip", "localhost")
PORT = config.get("port", "8000")
MODEL_NAME = config.get("model_name", "TBD")  # TODO: set default model
PROMPT_MODE = config.get("prompt_mode", "prompt_layout_all")
API_ADDRESS = f"http://{IP}:{PORT}/v1"
PROMPT = prompt_map[PROMPT_MODE]





def ocr(input_path, prompt=None):
    _prompt = PROMPT
    if prompt:
        if os.path.exists(prompt):
            pass
        else:
            _prompt = prompt

    _input = load_input(input_path)
    response = inference_with_vllm(
        _input,
        _prompt,
        ip=IP,
        port=PORT,
        temperature=0.1,
        top_p=0.9,
        model_name=MODEL_NAME,
    )


def main():
    addr = f"http://{IP}:{PORT}/v1"
    image_path = "demo/demo_image1.jpg"
    prompt = dict_promptmode_to_prompt[PROMPT_MODE]
    image = Image.open(image_path)
    response = inference_with_vllm(
        image,
        prompt,
        ip=IP,
        port=PORT,
        temperature=0.1,
        top_p=0.9,
        model_name=MODEL_NAME,
    )


if __name__ == "__main__":
    main()
