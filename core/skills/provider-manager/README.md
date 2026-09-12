# Stella Provider Manager

Secure management of external AI provider credentials.

## Providers

- Gemini
- Groq
- OpenRouter
- Ollama

## Security

Credentials are stored locally in:

config/providers.env

The file is excluded from Git and restricted to mode 600.

Raw credentials must never be:

- printed
- logged
- written to events
- placed in JSON state
- sent to an AI model
- committed to Git

## Commands

stella-provider status
stella-provider list
stella-provider set gemini
stella-provider set groq
stella-provider set openrouter
stella-provider remove gemini
stella-provider test gemini
