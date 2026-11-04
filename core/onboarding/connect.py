"""
connect.py - Stella's guided setup pages ("/connect").

Plain words: a friendly guide that walks a person, one small step at a time, through getting a key or token
from a website: where to click, what they will see, what to do. At the end the person pastes the secret
(hidden while typing), Stella shows only its first and last few letters, checks that it works, and locks it in
the vault. The AI brain never sees the secret.

Every service is a small JSON file in recipes/ (gemini.json, telegram.json). To add WhatsApp, Discord or any
other service later, add one more file there. No code changes.

Recipe fields: id, name, kind, secret_name, why, needs_human, minutes, steps[{title, open, you_see, do}],
format_hint, regex, verify{url, header, json_path, show}, after, if_leaked, status_note
"""
import getpass
import json
import os
import re
import urllib.error
import urllib.request
import webbrowser
from pathlib import Path

from vault import mask

RECIPES = Path(__file__).resolve().parent / "recipes"
BOLD, DIM, RESET = "\x1b[1m", "\x1b[2m", "\x1b[0m"


def load_recipes():
    out = {}
    for f in sorted(RECIPES.glob("*.json")):
        try:
            r = json.loads(f.read_text(encoding="utf-8"))
            if all(k in r for k in ("id", "name", "secret_name", "steps", "regex")):
                re.compile(r["regex"])
                out[r["id"]] = r
        except (OSError, ValueError, re.error):
            continue                               # a broken recipe is skipped, never fatal
    return out


def verify(recipe, secret):
    """(True, detail) works / (False, reason) rejected / (None, reason) could not check. Never prints the secret."""
    v = recipe.get("verify")
    if not v:
        return None, "no automatic check for this one"
    url = v["url"]
    if os.environ.get("STELLA_TEST_MODE") == "1" and os.environ.get("STELLA_TEST_VERIFY_URL"):
        url = os.environ["STELLA_TEST_VERIFY_URL"]  # lets automatic tests use a local fake server
    url = url.replace("{secret}", secret)
    headers = {"User-Agent": "stella-onboarding"}
    if v.get("header"):
        headers[v["header"]] = secret
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=20) as r:
            data = json.load(r)
    except urllib.error.HTTPError as e:
        if e.code in (400, 401, 403, 404):
            return False, "the service did not accept it"
        return None, f"the service answered with an error ({e.code})"
    except Exception:                               # deliberately vague: the message must never contain the URL
        return None, "I could not reach the service (offline?)"
    detail = ""
    for key in v.get("json_path", []):
        data = data.get(key) if isinstance(data, dict) else None
    if v.get("json_path"):
        detail = str(data or "")
        if not detail:
            return False, "the service did not accept it"
    return True, detail


def _say(text="", style=""):
    print(f"{style}{text}{RESET if style else ''}")


def _ask(prompt):
    try:
        return input(prompt).strip()
    except EOFError:
        return "q"


def run(recipe, vault, assume_online=True):
    """Guide the person. Returns (ok, message). The message never contains the secret."""
    name = recipe["name"]
    steps = recipe["steps"]
    _say()
    _say(f"Setting up: {name}", BOLD)
    _say(f"  {recipe.get('why', '')}")
    _say(f"  Time needed: about {recipe.get('minutes', 2)} minutes. The only part I cannot do for you:")
    _say(f"  {recipe.get('needs_human', 'You must do the sign-in yourself.')}")
    _say("  At any step: Enter = done, b = go back, o = open the page for me, q = stop.", DIM)
    i = 0
    while i < len(steps):
        s = steps[i]
        _say()
        _say(f"Step {i + 1} of {len(steps)}: {s['title']}", BOLD)
        if s.get("open"):
            _say(f"  Open:       {s['open']}")
        if s.get("you_see"):
            _say(f"  You'll see: {s['you_see']}")
        if s.get("do"):
            _say(f"  Do this:    {s['do']}")
        ans = _ask("  > ").lower()
        if ans == "q":
            return False, "Stopped. Nothing was saved. Run /connect " + recipe["id"] + " to start again."
        if ans == "b":
            i = max(0, i - 1)
            continue
        if ans == "o" and s.get("open"):
            try:
                webbrowser.open(s["open"])
            except Exception:
                _say("  I could not open a browser. Please open the address above yourself.")
            continue
        i += 1

    pattern = re.compile(recipe["regex"])
    secret = ""
    for attempt in range(3):
        _say()
        _say("Last step: paste it here.", BOLD)
        _say("  Nothing will show while you paste. That is normal and it is for your safety.")
        _say("  Right-click or Ctrl+V to paste, then press Enter.  (Type q and Enter to stop.)")
        try:
            secret = getpass.getpass("  Paste here: ").strip().strip("\"'")
        except (EOFError, KeyboardInterrupt):
            return False, "Stopped. Nothing was saved."
        if secret.lower() == "q":
            return False, "Stopped. Nothing was saved."
        if pattern.match(secret):
            break
        secret = ""
        left = 2 - attempt
        _say(f"  That does not look right: {recipe.get('format_hint', 'check that you copied all of it')}.", DIM)
        _say(f"  {'Try again.' if left else 'No more tries this time.'}")
    if not secret:
        return False, "I did not receive a usable one, so nothing was saved. Run /connect " + recipe["id"] + " to try again."

    _say()
    _say(f"  I received: {mask(secret)}   ({len(secret)} characters)")
    _say("  (Only the first and last few letters are shown. The middle stays hidden from everyone, including me.)", DIM)
    ok, detail = verify(recipe, secret) if assume_online else (None, "check skipped")
    if ok is True:
        _say("  Check: it works." + (f" {recipe['verify']['show'].replace('{detail}', detail)}"
                                     if recipe.get("verify", {}).get("show") and detail else ""))
    elif ok is False:
        secret = ""
        return False, f"The check failed: {detail}. Nothing was saved. Try copying it again with /connect {recipe['id']}."
    else:
        _say(f"  Check: skipped ({detail}).")
        if _ask("  Save it anyway? Type yes to save, anything else cancels: ").lower() != "yes":
            secret = ""
            return False, "Cancelled. Nothing was saved."
    try:
        where, note = vault.save(recipe["secret_name"], secret)
    except (OSError, ValueError) as e:
        return False, f"I could not save it ({type(e).__name__}). Nothing was changed."
    finally:
        secret = ""
    _say()
    _say(f"Saved in {vault.describe(where)}.", BOLD)
    if note:
        _say(f"  Note: {note}")
    for key in ("status_note", "after", "if_leaked"):
        if recipe.get(key):
            _say(f"  {recipe[key]}")
    return True, f"{name} is connected."
