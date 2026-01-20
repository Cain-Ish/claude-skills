#!/bin/bash
# Reflect Helper: Automate Git Workflow for Skill Changes
# Handles path detection, staging, commit, and push

set -euo pipefail

# Usage information
usage() {
    cat <<EOF
Usage: $0 SKILL_NAME COMMIT_MESSAGE [OPTIONS]

Automate git workflow for skill file changes.

Arguments:
  SKILL_NAME        Name of the skill (e.g., reflect, frontend-design)
  COMMIT_MESSAGE    Summary of changes (will be prefixed with "[skill]:")

Options:
  --dry-run         Show what would be done without making changes
  --no-push         Commit but don't push to remote
  --pull-first      Pull from remote before committing (handles conflicts)

Examples:
  $0 reflect "improve signal detection"
  $0 frontend-design "add dark mode constraints"

This script:
1. Finds the plugin repository
2. Verifies skill file exists and has changes
3. (Optional) Pulls from remote to handle conflicts
4. Stages the skill file
5. Commits with formatted message
6. Pushes to origin main (unless --no-push)

EOF
    exit 1
}

# Parse arguments
if [ $# -lt 2 ]; then
    usage
fi

SKILL_NAME="$1"
COMMIT_MESSAGE="$2"
shift 2

# Parse options
DRY_RUN=false
NO_PUSH=false
PULL_FIRST=false

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-push)
            NO_PUSH=true
            shift
            ;;
        --pull-first)
            PULL_FIRST=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

# Dry-run mode announcement
if [ "$DRY_RUN" = true ]; then
    echo "═══════════════════════════════════════" >&2
    echo "  DRY-RUN MODE (No changes will be made)" >&2
    echo "═══════════════════════════════════════" >&2
    echo "" >&2
fi

# Detect plugin repository
# Strategy: Use CLAUDE_PLUGIN_ROOT or search upwards from current directory
find_repo() {
    # First, try CLAUDE_PLUGIN_ROOT environment variable
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "$CLAUDE_PLUGIN_ROOT" ]; then
        # Find the git root from plugin root
        local current="$CLAUDE_PLUGIN_ROOT"
        while [ "$current" != "/" ]; do
            if [ -d "$current/.git" ]; then
                echo "$current"
                return 0
            fi
            current="$(dirname "$current")"
        done
    fi

    # Search upwards from current directory for .git
    local current="$PWD"
    while [ "$current" != "/" ]; do
        if [ -d "$current/.git" ]; then
            # Check if this looks like a plugin repo (has plugins/ or marketplace.json)
            if [ -d "$current/plugins" ] || [ -f "$current/marketplace.json" ]; then
                echo "$current"
                return 0
            fi
        fi
        current="$(dirname "$current")"
    done

    # Not found
    return 1
}

echo "Searching for plugin repository..." >&2
REPO_PATH=$(find_repo) || true

if [ -z "$REPO_PATH" ]; then
    echo "Error: Could not find plugin repository" >&2
    echo "Please run this from within a plugin workspace or set CLAUDE_PLUGIN_ROOT" >&2
    exit 1
fi

echo "Found repository: $REPO_PATH" >&2

# Build skill file path - check multiple possible locations
SKILL_FILE=""
FULL_PATH=""

# Try plugins/reflect/skills/[skill]/SKILL.md
if [ -f "$REPO_PATH/plugins/reflect/skills/$SKILL_NAME/SKILL.md" ]; then
    SKILL_FILE="plugins/reflect/skills/$SKILL_NAME/SKILL.md"
    FULL_PATH="$REPO_PATH/$SKILL_FILE"
# Try skills/[skill]/SKILL.md
elif [ -f "$REPO_PATH/skills/$SKILL_NAME/SKILL.md" ]; then
    SKILL_FILE="skills/$SKILL_NAME/SKILL.md"
    FULL_PATH="$REPO_PATH/$SKILL_FILE"
fi

# Verify skill file exists
if [ -z "$FULL_PATH" ] || [ ! -f "$FULL_PATH" ]; then
    echo "Error: Skill file not found for: $SKILL_NAME" >&2
    echo "Searched in:" >&2
    echo "  - $REPO_PATH/plugins/reflect/skills/$SKILL_NAME/SKILL.md" >&2
    echo "  - $REPO_PATH/skills/$SKILL_NAME/SKILL.md" >&2
    echo "" >&2
    echo "Available skills:" >&2
    if [ -d "$REPO_PATH/plugins/reflect/skills" ]; then
        ls -1 "$REPO_PATH/plugins/reflect/skills/" 2>/dev/null || echo "(none)" >&2
    elif [ -d "$REPO_PATH/skills" ]; then
        ls -1 "$REPO_PATH/skills/" 2>/dev/null || echo "(none)" >&2
    fi
    exit 1
fi

echo "Skill file: $SKILL_FILE" >&2

# Change to repository directory
cd "$REPO_PATH"

# Pull first if requested (merge conflict handling)
if [ "$PULL_FIRST" = true ]; then
    echo "Pulling from origin main..." >&2

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would run: git pull origin main" >&2
    else
        if ! git pull origin main; then
            echo "Error: Pull failed - merge conflicts may exist" >&2
            echo "" >&2
            echo "Conflict resolution steps:" >&2
            echo "  1. Resolve conflicts in affected files" >&2
            echo "  2. Run: git add <resolved-files>" >&2
            echo "  3. Run: git commit" >&2
            echo "  4. Run: git push origin main" >&2
            echo "" >&2
            echo "Alternatively, stash your changes:" >&2
            echo "  git stash" >&2
            echo "  git pull origin main" >&2
            echo "  git stash pop" >&2
            exit 1
        fi
        echo "Pull successful" >&2
    fi
    echo "" >&2
fi

# Check if file has changes
if ! git diff --quiet "$SKILL_FILE" && ! git diff --cached --quiet "$SKILL_FILE"; then
    echo "File has changes (unstaged or staged)" >&2
elif git diff --quiet "$SKILL_FILE" && git diff --cached --quiet "$SKILL_FILE"; then
    echo "Error: No changes detected in $SKILL_FILE" >&2
    echo "Nothing to commit" >&2
    exit 1
fi

# Show diff for user review
echo "" >&2
echo "Changes to be committed:" >&2
git diff "$SKILL_FILE" | head -50 >&2
echo "" >&2

# Stage the file
echo "Staging $SKILL_FILE..." >&2
if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] Would run: git add $SKILL_FILE" >&2
else
    git add "$SKILL_FILE"
fi

# Check if there are additional unstaged files in the skill directory
SKILL_DIR="$(dirname "$SKILL_FILE")"
if [ -d "$SKILL_DIR" ]; then
    # Check for reference files or other changes
    if git diff --name-only "$SKILL_DIR" | grep -q .; then
        echo "Note: Other files in $SKILL_DIR have changes:" >&2
        git diff --name-only "$SKILL_DIR" >&2
        echo "Only $SKILL_FILE will be committed. Stage others manually if needed." >&2
    fi
fi

# Format commit message
FULL_COMMIT_MSG="$SKILL_NAME: $COMMIT_MESSAGE"

echo "Commit message: $FULL_COMMIT_MSG" >&2

# Commit
echo "Committing..." >&2
if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] Would run: git commit -m \"$FULL_COMMIT_MSG\"" >&2
else
    if ! git commit -m "$FULL_COMMIT_MSG"; then
        echo "Error: Commit failed" >&2
        echo "Changes have been staged but not committed" >&2
        exit 1
    fi
fi

# Push (skip if --no-push or --dry-run)
if [ "$NO_PUSH" = true ]; then
    echo "Skipping push (--no-push specified)" >&2
elif [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] Would run: git push origin main" >&2
else
    echo "Pushing to origin main..." >&2
    if ! git push origin main; then
        echo "Error: Push failed" >&2
        echo "Commit succeeded but push failed" >&2
        echo "You may need to pull first: git pull origin main --rebase" >&2
        echo "Or use --pull-first flag next time" >&2
        exit 1
    fi
fi

echo "" >&2
if [ "$DRY_RUN" = true ]; then
    echo "✓ Dry-run complete (no changes made)" >&2
    echo "  Repository: $REPO_PATH" >&2
    echo "  File: $SKILL_FILE" >&2
    echo "  Would commit: $FULL_COMMIT_MSG" >&2
    if [ "$NO_PUSH" = false ]; then
        echo "  Would push to: origin/main" >&2
    fi
else
    echo "✓ Skill update complete!" >&2
    echo "  Repository: $REPO_PATH" >&2
    echo "  File: $SKILL_FILE" >&2
    echo "  Commit: $FULL_COMMIT_MSG" >&2
    if [ "$NO_PUSH" = true ]; then
        echo "  Committed locally (not pushed)" >&2
    else
        echo "  Pushed to: origin/main" >&2
    fi
fi
