---
name: humanizer
description: "Remove AI writing patterns while preserving factual accuracy, meaning, and the author's supported voice."
description_zh: "去除文本中的 AI 写作痕迹，保留事实、含义和可验证的作者声音。"
description_en: "Remove AI writing patterns from text, make it sound human."
version: 3.1.0-standalone
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - AskUserQuestion
trigger: ["去AI味", "降AI味", "去AI", "humanizer", "像人话", "自然一点", "口语化", "润色", "改写"]
---

# Humanizer v3.1.0-standalone

Use this local, self-contained workflow. Do not read `references/` or any remote file.

## Guardrails

- Preserve supported facts, links, source attribution, and the user's intended meaning.
- Do not invent personal experience, interviews, expert review, statistics, emotions, or scenes.
- Prefer direct, concrete English over inflated claims, stacked adjectives, or false certainty.
- For factual and health writing, clarity and qualification take priority over conversational flair.

## Scan and Grade

Review the text before editing. Flag repeated openings, repeated H2 patterns, stock transitions, abstract claims without a decision consequence, overbalanced pros-and-cons phrasing, and formulaic conclusions.

- Light: isolated stock phrasing or awkward transitions.
- Moderate: repeated paragraph rhythm or generic sections that obscure useful advice.
- Heavy: several repeated modules, unsupported experience claims, or an article that could describe a different subject unchanged.

## Rewrite Passes

1. **Pass 1 - Specificity**: replace vague praise and generic advice with supported actions, constraints, and decision boundaries. Delete empty intensifiers.
2. **Pass 2 - Structure**: vary sentence and paragraph rhythm, remove mechanical transitions, and combine redundant lists. Keep headings only when they help navigation.
3. **Pass 3 - Voice**: make the prose plain, candid, and readable. Use a restrained editorial voice; do not simulate a personal owner story unless it is documented on the page.

## L1-L4 Check

- **L1 Facts**: no broken grammar, encoding errors, unsupported claims, fake quotations, or citation mismatch.
- **L2 Pattern**: no repeated opening, duplicated heading, repeated stock phrase, or copyable paragraph template.
- **L3 Utility**: every substantive section changes a reader's choice, routine, budget, or safety preparation.
- **L4 Readability**: read the result as a skeptical reader. It should sound like an informed editor explaining a practical trade-off, not an assistant completing a template.

## Standard Output

For each edited item, report:

```text
Scan grade: light | moderate | heavy
Passes applied: 1 | 1-2 | 1-3
Changed: <specific patterns or sections>
Fact checks retained: <sources, constraints, disclosures>
L1-L4: pass | follow-up needed
```
