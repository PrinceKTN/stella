#!/usr/bin/env python3
"""
Stella Token Tracker — Live token usage monitoring across providers
"""
import json
import os
import sys
import argparse
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Any, Optional

# ── Path Resolution ──────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
STELLA_ROOT = Path(os.environ.get('STELLA_ROOT') or SCRIPT_DIR.parents[3]).resolve()

STATE_DIR = STELLA_ROOT / "state"
EVENT_DIR = STELLA_ROOT / "events"
LOG_DIR = STELLA_ROOT / "logs"
CONFIG_DIR = STELLA_ROOT / "config"
SKILL_DIR = STELLA_ROOT / "core" / "skills" / "token-tracker"
SKILL_CONFIG = SKILL_DIR / "config"

TOKEN_DB = STATE_DIR / "token-usage.jsonl"
TOKEN_SUMMARY = STATE_DIR / "token-summary.json"
TOKEN_ALERTS = STATE_DIR / "token-alerts.jsonl"
PROVIDER_REGISTRY = CONFIG_DIR / "provider-registry.json"
TOKEN_CONFIG = SKILL_CONFIG / "token-tracker.json"
TOKEN_SCHEMA = CONFIG_DIR / "schemas" / "token-tracker.schema.json"

for d in [STATE_DIR, EVENT_DIR, LOG_DIR, CONFIG_DIR / "schemas", SKILL_CONFIG]:
    d.mkdir(parents=True, exist_ok=True)

# ── Utilities ────────────────────────────────────────────────
def timestamp() -> str:
    return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

def date_key() -> str:
    return datetime.now(timezone.utc).strftime('%Y-%m-%d')

def log(msg: str):
    print(f"[{timestamp()}] {msg}")

def load_config() -> Dict[str, Any]:
    if TOKEN_CONFIG.exists():
        with open(TOKEN_CONFIG) as f:
            return json.load(f)
    return default_config()

def default_config() -> Dict[str, Any]:
    return {
        "schema_version": 1,
        "enabled": True,
        "tracking": {
            "live_monitoring": True,
            "per_provider_daily_limits": {
                "gemini": {"requests_per_minute": 15, "requests_per_day": 1500, "tokens_per_minute": 1000000, "tokens_per_day": 50000000},
                "openrouter": {"requests_per_minute": 20, "requests_per_day": 1000, "tokens_per_minute": 200000, "tokens_per_day": 10000000},
                "groq": {"requests_per_minute": 30, "requests_per_day": 14400, "tokens_per_minute": 500000, "tokens_per_day": 30000000},
                "ollama": {"requests_per_minute": 999, "requests_per_day": 999999, "tokens_per_minute": 999999999, "tokens_per_day": 999999999},
                "openai": {"requests_per_minute": 500, "requests_per_day": 10000, "tokens_per_minute": 200000, "tokens_per_day": 10000000},
                "anthropic": {"requests_per_minute": 50, "requests_per_day": 1000, "tokens_per_minute": 40000, "tokens_per_day": 2000000}
            },
            "alert_thresholds": {"warning_percent": 70, "critical_percent": 90, "near_limit_minutes": 60},
            "smart_splitting": {"enabled": True, "max_tokens_per_task": 4000, "prefer_free_providers": True, "auto_fallback": True, "split_strategy": "by_context_window"},
            "persistence": {"retention_days": 30, "aggregate_hourly": True}
        },
        "display": {"show_in_prompt": True, "compact_mode": False, "color_alerts": True}
    }

def save_config(config: Dict[str, Any]):
    with open(TOKEN_CONFIG, 'w') as f:
        json.dump(config, f, indent=2)

# ── Core Functions ───────────────────────────────────────────
def record_usage(provider: str, model: str, input_tokens: int, output_tokens: int,
                 operation: str = "chat", session_id: str = "", task_id: str = ""):
    date = date_key()
    total = input_tokens + output_tokens
    entry = {
        "timestamp": timestamp(),
        "date": date,
        "provider": provider,
        "model": model,
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "total_tokens": total,
        "operation": operation,
        "session_id": session_id,
        "task_id": task_id
    }
    
    with open(TOKEN_DB, 'a') as f:
        f.write(json.dumps(entry) + '\n')
    
    update_summary(provider, model, input_tokens, output_tokens, date)
    check_alerts(provider, date)
    
    print(f"Recorded: {provider}/{model} — {input_tokens}+{output_tokens}={total} tokens")

def update_summary(provider: str, model: str, input_tokens: int, output_tokens: int, date: str):
    summary = {}
    if TOKEN_SUMMARY.exists():
        with open(TOKEN_SUMMARY) as f:
            summary = json.load(f)
    
    key = f"{date}:{provider}:{model}"
    if key not in summary:
        summary[key] = {
            "date": date, "provider": provider, "model": model,
            "requests": 0, "input_tokens": 0, "output_tokens": 0, "total_tokens": 0
        }
    
    summary[key]["requests"] += 1
    summary[key]["input_tokens"] += input_tokens
    summary[key]["output_tokens"] += output_tokens
    summary[key]["total_tokens"] += input_tokens + output_tokens
    
    with open(TOKEN_SUMMARY, 'w') as f:
        json.dump(summary, f, indent=2)

def check_alerts(provider: str, date: str):
    config = load_config()
    limits = config.get("tracking", {}).get("per_provider_daily_limits", {}).get(provider, {})
    thresholds = config.get("tracking", {}).get("alert_thresholds", {})
    warn_pct = thresholds.get("warning_percent", 70)
    crit_pct = thresholds.get("critical_percent", 90)
    
    if not limits:
        return
    
    summary = {}
    if TOKEN_SUMMARY.exists():
        with open(TOKEN_SUMMARY) as f:
            summary = json.load(f)
    
    total_today = sum(d.get("total_tokens", 0) for k, d in summary.items() 
                      if d.get("date") == date and d.get("provider") == provider)
    
    max_tokens = limits.get("tokens_per_day", 0)
    if max_tokens == 0:
        return
    
    pct = (total_today / max_tokens) * 100
    
    alert = None
    if pct >= crit_pct:
        alert = {"level": "critical", "provider": provider, "date": date, "used": total_today, "limit": max_tokens, "percent": round(pct, 1)}
    elif pct >= warn_pct:
        alert = {"level": "warning", "provider": provider, "date": date, "used": total_today, "limit": max_tokens, "percent": round(pct, 1)}
    
    if alert:
        alert["timestamp"] = timestamp()
        alert["message"] = f"{alert['level'].upper()}: {provider} at {pct:.1f}% of daily token limit ({total_today:,}/{max_tokens:,})"
        
        # Check if already alerted
        already = False
        if TOKEN_ALERTS.exists():
            with open(TOKEN_ALERTS) as f:
                for line in f:
                    try:
                        a = json.loads(line.strip())
                        if a.get("provider") == provider and a.get("date") == date and a.get("level") == alert["level"]:
                            already = True
                            break
                    except:
                        pass
        
        if not already:
            with open(TOKEN_ALERTS, 'a') as f:
                f.write(json.dumps(alert) + '\n')
            print(f"🔔 {alert['message']}", file=sys.stderr)

def usage_report(date: Optional[str] = None, provider_filter: Optional[str] = None):
    date = date or date_key()
    config = load_config()
    limits = config.get("tracking", {}).get("per_provider_daily_limits", {})
    
    summary = {}
    if TOKEN_SUMMARY.exists():
        with open(TOKEN_SUMMARY) as f:
            summary = json.load(f)
    
    print(f"╔═════════════════════════════════════════════════════════════╗")
    print(f"║  TOKEN USAGE REPORT — {date}                                    ║")
    print(f"╚═════════════════════════════════════════════════════════════╝")
    print()
    
    providers = set()
    for key in summary:
        parts = key.split(":")
        if len(parts) >= 2:
            providers.add(parts[1])
    
    any_data = False
    for p in sorted(providers):
        if provider_filter and p != provider_filter:
            continue
        
        provider_data = [d for k, d in summary.items() if d.get("date") == date and d.get("provider") == p]
        if not provider_data:
            continue
        
        any_data = True
        total_requests = sum(d.get("requests", 0) for d in provider_data)
        total_input = sum(d.get("input_tokens", 0) for d in provider_data)
        total_output = sum(d.get("output_tokens", 0) for d in provider_data)
        total_tokens = sum(d.get("total_tokens", 0) for d in provider_data)
        
        limit = limits.get(p, {}).get("tokens_per_day", 0)
        req_limit = limits.get(p, {}).get("requests_per_day", 0)
        
        pct_tokens = (total_tokens / limit * 100) if limit > 0 else 0
        pct_requests = (total_requests / req_limit * 100) if req_limit > 0 else 0
        
        bar_len = 30
        filled = int(bar_len * pct_tokens / 100)
        bar = "█" * filled + "░" * (bar_len - filled)
        
        status = "🟢"
        if pct_tokens >= 90: status = "🔴"
        elif pct_tokens >= 70: status = "🟡"
        
        print(f"  {status} {p.upper()}")
        print(f"     Tokens: {total_tokens:,} / {limit:,} ({pct_tokens:.1f}%) [{bar}]")
        print(f"     Requests: {total_requests:,} / {req_limit:,} ({pct_requests:.1f}%)")
        print(f"     Input: {total_input:,} | Output: {total_output:,}")
        print()
    
    if not any_data:
        print("  No usage data for this date.")
        print()
    
    # Alerts
    if TOKEN_ALERTS.exists():
        print("  Recent Alerts:")
        with open(TOKEN_ALERTS) as f:
            for line in f:
                try:
                    a = json.loads(line.strip())
                    if a.get("date") == date:
                        icon = "🔴" if a.get("level") == "critical" else "🟡"
                        print(f"    {icon} {a.get('message')}")
                except:
                    pass

def smart_split(estimated_tokens: int, preferred_provider: str = ""):
    config = load_config()
    limits = config.get("tracking", {}).get("per_provider_daily_limits", {})
    smart = config.get("tracking", {}).get("smart_splitting", {})
    max_per_task = smart.get("max_tokens_per_task", 4000)
    prefer_free = smart.get("prefer_free_providers", True)
    
    today = date_key()
    
    summary = {}
    if TOKEN_SUMMARY.exists():
        with open(TOKEN_SUMMARY) as f:
            summary = json.load(f)
    
    registry = {}
    if PROVIDER_REGISTRY.exists():
        with open(PROVIDER_REGISTRY) as f:
            registry = json.load(f)
    
    providers = registry.get("providers", {})
    
    print("╔═════════════════════════════════════════════════════════════╗")
    print("║  SMART TASK SPLIT RECOMMENDATION                            ║")
    print("╚═════════════════════════════════════════════════════════════╝")
    print()
    print(f"  Estimated task tokens: {estimated_tokens:,}")
    print(f"  Max per task (config): {max_per_task:,}")
    print()
    
    candidates = []
    for name, prov in providers.items():
        if not prov.get("enabled", True):
            continue
        
        limit = limits.get(name, {}).get("tokens_per_day", 0)
        if limit == 0:
            continue
        
        used = sum(d.get("total_tokens", 0) for k, d in summary.items() 
                   if d.get("date") == today and d.get("provider") == name)
        available = max(0, limit - used)
        pct_used = (used / limit * 100) if limit > 0 else 0
        
        models = prov.get("models", {})
        max_ctx = max((m.get("context_window", 0) for m in models.values()), default=0)
        free_model = next((m for m, d in models.items() if d.get("free") or prov.get("cost_mode") in ["free_tier", "local"]), None)
        
        can_handle = available >= estimated_tokens and max_ctx >= estimated_tokens
        
        score = 0
        if prov.get("cost_mode") in ["free_tier", "local", "free_or_paid"]: score += 100
        if free_model: score += 50
        score += (available / 1000000) * 10
        score += (max_ctx / 100000) * 5
        if preferred_provider and name == preferred_provider: score += 1000
        
        candidates.append({
            "name": name, "cost_mode": prov.get("cost_mode"),
            "limit": limit, "used": used, "available": available,
            "pct_used": pct_used, "max_context": max_ctx,
            "free_model": free_model, "can_handle": can_handle,
            "score": score, "models": list(models.keys())[:3]
        })
    
    candidates.sort(key=lambda x: -x["score"])
    
    print("  PROVIDER RECOMMENDATIONS:")
    print()
    for i, c in enumerate(candidates[:5]):
        status = "✅" if c["can_handle"] else "⚠️"
        free_badge = " 🆓" if c["free_model"] else ""
        print(f"  {i+1}. {status} {c['name'].upper()}{free_badge}")
        print(f"     Available: {c['available']:,} / {c['limit']:,} tokens ({c['pct_used']:.1f}% used)")
        print(f"     Max context: {c['max_context']:,} | Free model: {c['free_model'] or 'none'}")
        print(f"     Models: {', '.join(c['models'])}")
        print()
    
    if estimated_tokens > max_per_task:
        parts = (estimated_tokens + max_per_task - 1) // max_per_task
        print(f"  📐 SPLITTING NEEDED: Task exceeds {max_per_task:,} token limit")
        print(f"     Recommended: Split into {parts} parts of ~{estimated_tokens//parts:,} tokens each")
        print()
        print("  Splitting strategy:")
        print("    1. Divide by logical sections (files, functions, topics)")
        print("    2. Process each part with best available provider")
        print("    3. Use provider with largest context for biggest chunk")
        print("    4. Aggregate results at the end")
    else:
        print("  ✅ Task fits within single chunk limit")
        best = candidates[0] if candidates else None
        if best:
            print(f"     Best provider: {best['name'].upper()} ({best['available']:,} tokens available)")

def show_alerts():
    if TOKEN_ALERTS.exists():
        with open(TOKEN_ALERTS) as f:
            for line in f:
                try:
                    a = json.loads(line.strip())
                    icon = "🔴" if a.get("level") == "critical" else "🟡"
                    print(f"{icon} [{a.get('timestamp')}] {a.get('message')}")
                except:
                    pass
    else:
        print("No alerts recorded yet")

def export_data(format: str = "json", date: Optional[str] = None):
    date = date or date_key()
    summary = {}
    if TOKEN_SUMMARY.exists():
        with open(TOKEN_SUMMARY) as f:
            summary = json.load(f)
    
    result = {k: v for k, v in summary.items() if v.get("date") == date}
    
    if format == "json":
        print(json.dumps(result, indent=2))
    elif format == "csv":
        print("date,provider,model,requests,input_tokens,output_tokens,total_tokens")
        for k, v in result.items():
            print(f"{v['date']},{v['provider']},{v['model']},{v['requests']},{v['input_tokens']},{v['output_tokens']},{v['total_tokens']}")

def cleanup(retention_days: int = 30):
    from datetime import timedelta
    cutoff = (datetime.now(timezone.utc) - timedelta(days=retention_days)).strftime('%Y-%m-%d')
    
    for f in [TOKEN_DB, TOKEN_SUMMARY, TOKEN_ALERTS]:
        if not f.exists():
            continue
        backup = f.with_suffix(f.suffix + ".bak")
        f.rename(backup)
        
        with open(backup) as inf, open(f, 'w') as outf:
            for line in inf:
                try:
                    d = json.loads(line)
                    if d.get('date', '9999-99-99') >= cutoff:
                        outf.write(line)
                except:
                    pass
        print(f"Cleaned {f} (kept entries from {cutoff} onwards)")

# ── CLI ──────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="Stella Token Tracker")
    sub = parser.add_subparsers(dest="cmd", required=True)
    
    p = sub.add_parser("record", help="Record token usage")
    p.add_argument("provider")
    p.add_argument("model")
    p.add_argument("input_tokens", type=int)
    p.add_argument("output_tokens", type=int)
    p.add_argument("--operation", default="chat")
    p.add_argument("--session-id", default="")
    p.add_argument("--task-id", default="")
    
    p = sub.add_parser("report", help="Show daily usage report")
    p.add_argument("--date", default=None)
    p.add_argument("--provider", default=None)
    
    p = sub.add_parser("split", help="Smart task split recommendation")
    p.add_argument("estimated_tokens", type=int)
    p.add_argument("--provider", default="")
    
    p = sub.add_parser("monitor", help="Live monitoring (not implemented in Python)")
    p.add_argument("--interval", type=int, default=30)
    
    p = sub.add_parser("alerts", help="Show recent alerts")
    
    p = sub.add_parser("export", help="Export usage data")
    p.add_argument("--format", choices=["json", "csv"], default="json")
    p.add_argument("--date", default=None)
    
    p = sub.add_parser("cleanup", help="Clean old data")
    p.add_argument("--days", type=int, default=30)
    
    p = sub.add_parser("config", help="Show configuration")
    
    p = sub.add_parser("init", help="Initialize skill")
    
    args = parser.parse_args()
    
    if args.cmd == "record":
        record_usage(args.provider, args.model, args.input_tokens, args.output_tokens,
                     args.operation, args.session_id, args.task_id)
    elif args.cmd == "report":
        usage_report(args.date, args.provider)
    elif args.cmd == "split":
        smart_split(args.estimated_tokens, args.provider)
    elif args.cmd == "monitor":
        print("Live monitor not implemented in Python version. Use bash wrapper.")
    elif args.cmd == "alerts":
        show_alerts()
    elif args.cmd == "export":
        export_data(args.format, args.date)
    elif args.cmd == "cleanup":
        cleanup(args.days)
    elif args.cmd == "config":
        config = load_config()
        print(json.dumps(config, indent=2))
    elif args.cmd == "init":
        save_config(default_config())
        print("Token tracker initialized")

if __name__ == "__main__":
    main()