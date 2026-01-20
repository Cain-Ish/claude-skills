---
description: "Analyze session and propose skill improvements based on learnings"
argument-hint: "[skill] | on | off | status | stats | validate | analyze-effectiveness | improve"
---

# /reflect Command

Analyze the current session and propose skill improvements based on learnings.

## Usage

```
/reflect                    # Analyze session, auto-detect skill
/reflect [skill]            # Analyze session for specific skill
/reflect on                 # Enable automatic reflection
/reflect off                # Disable automatic reflection
/reflect status             # Check auto-reflect status
/reflect stats [skill]      # Show effectiveness metrics
/reflect validate [skill]   # Check if recent improvements helped
/reflect analyze-effectiveness  # Analyze metrics and propose meta-improvements
/reflect reflect            # Meta-improvement: improve reflect itself
/reflect improve            # Systematic self-improvement: analyze + reflect + apply
```

## Argument: $ARGUMENTS

First, run the reflect script to handle subcommands:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/reflect.sh $ARGUMENTS
```

- If output starts with `REFLECT_SKILL:` → Run the reflection workflow below
- Otherwise → The script handled the command, display its output to the user

## Reflection Workflow

When running reflection (no subcommand or skill name):

1. Read the skill definition from `${CLAUDE_PLUGIN_ROOT}/skills/reflect/SKILL.md`
2. Follow the workflow defined there:
   - Identify the target skill (ask if not specified)
   - Analyze the conversation for signals (corrections, successes, edge cases)
   - Propose changes with confidence levels (🔴 HIGH, 🟡 MED, 🔵 LOW)
   - Get user approval
   - Apply changes to the skill file
   - Optionally commit and push if git is configured

## Notes

- The reflect skill learns from corrections and successes in the conversation
- All skill modifications require explicit user approval
- Use git versioning to track how skills evolve over time