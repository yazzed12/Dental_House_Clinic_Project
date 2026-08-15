from langchain_ollama import ChatOllama


OLLAMA_MODEL = "llama3.2:3b"
OLLAMA_BASE_URL = "http://127.0.0.1:11434"


def create_ollama_client(temperature=0.2, format=None):
    """Create the async-capable local Ollama client used by common AI services."""
    return ChatOllama(
        model=OLLAMA_MODEL,
        base_url=OLLAMA_BASE_URL,
        temperature=temperature,
        num_predict=1024,
        format=format,
    )
