# Stella's body: how the parts fit (read me first when resuming)

Faces talk to people. Hands (skills) do jobs. body.py joins them to Stella's own rules.
Nothing here edits an existing Stella file. New abilities are NEW folders.

## Layout
- core/agent/stella_agent.py   the thinking loop + 4 built-in tools (device, find/archive ChatGPT export)
- core/agent/body.py           loads hands from core/skills/<id>/ ONLY if registry.json says ENABLED;
                               approvals (files / cloud-privacy / heavy+governor); sandbox = data/ folder
- core/interfaces/terminal/stella-live.py   the face: original banner + panels + conversation
                               (your original stella-chat.sh is untouched)
- core/skills/chat-bank/       first hand: private searchable library of ChatGPT history (SQLite+FTS5),
                               secrets redacted before storing, streams big files (small memory)

## Add a new hand (never edit old files)
1. Make core/skills/<id>/config/skill.json (fields as in chat-bank; risk MEDIUM+ needs
   requires_approval + sandbox_required; native/autonomous must be false) and config/permissions.json
2. Put tools in bin/tools.py: def tools(ctx) -> {name: {fn, label, description, params, approve, egress, heavy}}
   egress=True when the result is shown to the cloud model (asks first); heavy=True for big jobs
3. In Stella type /enable <id> (needs a typed yes; a backup of registry.json is saved first)

## Rules baked in
- Writes only inside data/ (git-ignored). Refuses if a folder could be pushed to GitHub.
- Gemini FREE tier: Google's terms say people may read inputs/outputs and use them to improve products.
  So chat text reaches Gemini only after approval, in small pieces. A local brain later removes this.
- Enabling a skill = trusting its code (plain text, readable).

## Not built yet (next, in order)
1. Memory proposals: pick durable facts from the chat library, ask approval, then write to
   core/memory/data/oracle-memory.db using the memories table (retention long_term, user_confirmed=1).
2. Telegram face (same body.py), 3. scheduler hand, 4. more providers via llm_router.py, 5. sub-agents.
