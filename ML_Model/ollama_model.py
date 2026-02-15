import ollama
from typing import Generator, Optional

class OllamaModel:
    def __init__(self, model_name: str = "vicuna:13b"):
        self.model_name = model_name
        try:
            ollama.show(self.model_name)
            print(f"Model '{self.model_name}' is ready.")
        except Exception:
            print(f"Model '{self.model_name}' not found. Pulling...")
            ollama.pull(self.model_name)

    def stream_response(self, prompt: str, system_prompt: Optional[str] = None) -> Generator[str, None, None]:
        messages = []
        if system_prompt:
            messages.append({'role': 'system', 'content': system_prompt})
        messages.append({'role': 'user', 'content': prompt})
        response_stream = ollama.chat(
            model=self.model_name,
            messages=messages,
            stream=True,
        )

        for chunk in response_stream:
            yield chunk['message']['content']