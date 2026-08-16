# Contributing

## Most wanted

**1. Detection rules for other stacks.** The rules in `audit-rules.md` were built and field-tested on React / Vite / Capacitor / Supabase / Firebase. Django, Rails, Go, .NET, Next.js server actions, React Native and Flutter are all uncovered. A new stack section is the highest-value contribution.

**2. False positive reports.** If a pattern fires on correct code, that is a bug. Open an issue with the snippet and the rule that matched. Narrowing a rule helps everyone — a tool that cries wolf gets ignored.

**3. Findings the skill missed.** If you ran a pass and it walked past something real, say what it was and where. That usually becomes a new pattern.

## What makes a good rule

Every rule in `audit-rules.md` follows the same shape:

- **A search that produces suspicion** — a grep/rg command
- **A confirming step** — a second search, or "open this file and read it"
- **What to check** — the actual judgment, in plain sentences
- **A false-positive warning** where the pattern is known to over-fire

Rules that only do the first part will not be merged. The skill's credibility depends on findings being real, so a rule without a verification step is worse than no rule.

Rules must also respect the over-engineering filter: do not add a check that pushes infrastructure nobody at that scale needs.

## Testing a change

There is no test suite — this is a prompt, not a program. To validate a change:

1. Install locally (`./install.sh`)
2. Run `/kontrolg` on a real project, ideally one you know well
3. Check whether your new rule fired, and whether it fired *correctly*
4. Note the false positive rate in the PR description

Reports from real projects are welcome in the PR (redact anything sensitive — never paste secrets, even expired ones).

## Style

- English in all files under `skills/`
- Imperative, second person: "Check whether...", not "One should check..."
- No emoji in the skill files
- Keep `SKILL.md` lean; detail belongs in `references/`, which load on demand

## License

By contributing you agree your work is released under the MIT License.
