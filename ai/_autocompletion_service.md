# Autocompletion service

add a service to call llms to generate autocompletion, it must be openai compatiible, it must have some configs based on @ai/app_config.md: base url and api key to be allowed to be changed for vllm or ollama as well as open ai ones or antrhopic in the future. this configs must be global.

check how the logger is implemented, but please do not add it to core, logger and autocompletion must not be core concepts, they must be just services, create a folder for that and move logger and config to there.