# Review questions for GPT‑5.2 Pro

Please review for:
- Performance implications (CPU/GPU usage, runloop churn, repeated UI redraws, XPC chatty calls, SMC IO cost).
- Battery-health implications (charge cycling, hysteresis, timer cadence, charging toggle behavior, MagSafe LED writes).
- Any hidden background work (timers, notifications, logging) that could keep the system active.
- Risks on Intel vs Apple Silicon if you can infer.
- Suggestions for reducing work while preserving charging behavior.

Output format requested:
- Findings ordered by severity.
- For each: impact, why, and a low-risk mitigation.
- Highlight any assumptions.

