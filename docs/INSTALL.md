# Installing Stella

Folder name: keep it `stella` so it is easy to remember.

| Device | Steps |
|---|---|
| Windows (PowerShell) | `git clone https://github.com/PrinceKTN/stella` → `cd stella` → `.\install.cmd` |
| WSL Ubuntu/Debian | `git clone ...` → `cd stella` → `sh install.sh` |
| Termux (Android) | `pkg install git python` → `git clone ...` → `cd stella` → `sh install.sh` |

After that, open a **new** terminal and type `stella` from any folder.

First run: Stella walks you through the free Gemini key (typed hidden, stored in the system vault or a locked
file, never shown to the AI). `/connect telegram` does the same for a Telegram bot token.

## Everyday commands
`/help` · `/new` · `/sessions` · `/resume` · `/theme` · `/colors` · `/color think yellow` · `/config` · `/connect`

## Look and feel
Themes: `dark`, `gold` (yellow + white, lighter color for her thinking), `ocean`, `light`, `mono`.
Every part (you, name, reply, think, step, ask, dim, err, rule, title) can be recolored with
`/color <part> <name or #hex>`; `/colors reset` undoes your tweaks.

## Size
Stella's own code is under 200 KB. The only optional extra is `prompt_toolkit` (~5 MB) for the live `/` menu;
skip it on tiny phones and Stella still works (type `/help`).

## Undo
`stella` word: `python3 core/interfaces/terminal/stella-launcher.py --uninstall-command`. Delete the Desktop icon by hand.
Your chats, settings and keys live in `data/` and are never pushed to GitHub.
