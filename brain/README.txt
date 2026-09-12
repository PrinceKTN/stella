STELLA BRAIN
============

This directory is reserved for Stella's brain runtime.

The brain is intentionally separated from the agents.

Agents communicate through:
    ~/stella/state/
    ~/stella/events/

Provider credentials must NEVER be committed to GitHub.

Use environment variables or the protected secrets directory.

The brain should select providers according to:

1. Device capability
2. Provider availability
3. Reliability
4. Latency
5. Context capability
6. Token efficiency
7. Cost
8. User-selected preferences

On low-resource devices, remote AI is preferred.
Heavy local models must remain disabled unless the device profile
explicitly allows them.
