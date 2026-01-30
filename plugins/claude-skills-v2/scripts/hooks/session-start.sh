#!/usr/bin/env bash
set -euo pipefail

# SessionStart hook - Initialize session
# Loads context, detects package manager, starts learning engine

# Configuration
CLAUDE_SKILLS_DIR="${HOME}/.claude/claude-skills"
SESSION_STATE_DIR="${CLAUDE_SKILLS_DIR}/session-state"
CONTEXT_DIR="${CLAUDE_SKILLS_DIR}/context"
LEARNING_DIR="${CLAUDE_SKILLS_DIR}/learning"

# Create directories
mkdir -p "$SESSION_STATE_DIR" "$CONTEXT_DIR" "$LEARNING_DIR"

# Get hook input from stdin
HOOK_INPUT=$(cat)

# Extract session info
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // "unknown"')
CWD=$(echo "$HOOK_INPUT" | jq -r '.cwd // "."')

# Initialize output
OUTPUT_JSON='{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": ""
  }
}'

# Function to update context
update_context() {
  local message="$1"
  OUTPUT_JSON=$(echo "$OUTPUT_JSON" | jq --arg msg "$message" \
    '.hookSpecificOutput.additionalContext += $msg + "\n"')
}

# 1. Load previous session context (last 7 days)
RECENT_SESSIONS=$(find "$SESSION_STATE_DIR" -name "*.json" -mtime -7 2>/dev/null | sort -r | head -5)
if [[ -n "$RECENT_SESSIONS" ]]; then
  SESSION_COUNT=$(echo "$RECENT_SESSIONS" | wc -l | tr -d ' ')
  update_context "📝 Loaded context from $SESSION_COUNT recent session(s)"

  # Extract key insights from recent sessions
  RECENT_DOMAINS=$(echo "$RECENT_SESSIONS" | xargs cat 2>/dev/null | \
    jq -r '.domains[]? // empty' | sort | uniq -c | sort -rn | head -3)

  if [[ -n "$RECENT_DOMAINS" ]]; then
    update_context "Recent work domains: $(echo "$RECENT_DOMAINS" | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')"
  fi
fi

# 2. Detect package manager
cd "$CWD" 2>/dev/null || true

PACKAGE_MANAGER=""
if [[ -f "package.json" ]]; then
  if [[ -f "pnpm-lock.yaml" ]]; then
    PACKAGE_MANAGER="pnpm"
  elif [[ -f "yarn.lock" ]]; then
    PACKAGE_MANAGER="yarn"
  elif [[ -f "bun.lockb" ]]; then
    PACKAGE_MANAGER="bun"
  elif [[ -f "package-lock.json" ]]; then
    PACKAGE_MANAGER="npm"
  else
    PACKAGE_MANAGER="npm (no lockfile detected)"
  fi

  update_context "📦 Package manager: $PACKAGE_MANAGER"
fi

# Detect Python environment
if [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then
  PYTHON_VERSION=$(python3 --version 2>/dev/null | awk '{print $2}' || echo "unknown")
  update_context "🐍 Python environment detected (version: $PYTHON_VERSION)"

  if [[ -f "pyproject.toml" ]] && grep -q "uv" pyproject.toml 2>/dev/null; then
    update_context "   Using uv package manager"
  elif [[ -f "poetry.lock" ]]; then
    update_context "   Using poetry package manager"
  fi
fi

# Detect Go project
if [[ -f "go.mod" ]]; then
  GO_VERSION=$(go version 2>/dev/null | awk '{print $3}' || echo "unknown")
  update_context "🔷 Go project detected ($GO_VERSION)"
fi

# Detect Rust project
if [[ -f "Cargo.toml" ]]; then
  RUST_VERSION=$(rustc --version 2>/dev/null | awk '{print $2}' || echo "unknown")
  update_context "🦀 Rust project detected ($RUST_VERSION)"
fi

# 3. Git repository detection
if git rev-parse --git-dir > /dev/null 2>&1; then
  GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  GIT_STATUS=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

  update_context "🔀 Git branch: $GIT_BRANCH ($GIT_STATUS uncommitted change(s))"

  # Check for unmerged branches
  UNMERGED=$(git branch --no-merged 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$UNMERGED" -gt 0 ]]; then
    update_context "   ⚠️ $UNMERGED unmerged branch(es) exist"
  fi
fi

# 4. Initialize learning engine
LEARNING_PID_FILE="${LEARNING_DIR}/observer.pid"

# Check if observer is already running
if [[ -f "$LEARNING_PID_FILE" ]]; then
  OLD_PID=$(cat "$LEARNING_PID_FILE")
  if ps -p "$OLD_PID" > /dev/null 2>&1; then
    update_context "🧠 Learning engine already running (PID: $OLD_PID)"
  else
    # Stale PID file, remove it
    rm -f "$LEARNING_PID_FILE"
  fi
fi

# Start background observer if not running
if [[ ! -f "$LEARNING_PID_FILE" ]]; then
  # Check if observer script exists
  OBSERVER_SCRIPT="${CLAUDE_PLUGIN_ROOT:-}/scripts/learning/background-observer.sh"

  if [[ -f "$OBSERVER_SCRIPT" ]]; then
    # Start in background
    nohup "$OBSERVER_SCRIPT" > "${LEARNING_DIR}/observer.log" 2>&1 &
    echo $! > "$LEARNING_PID_FILE"
    update_context "🧠 Learning engine started (background pattern detection)"
  else
    update_context "⚠️ Learning engine not available (observer script not found)"
  fi
fi

# 5. Check for high-confidence instincts
INSTINCTS_DIR="${CLAUDE_SKILLS_DIR}/instincts"
HIGH_CONFIDENCE_COUNT=0

if [[ -d "$INSTINCTS_DIR" ]]; then
  HIGH_CONFIDENCE_COUNT=$(find "$INSTINCTS_DIR" -name "*.md" -type f -exec grep -l "^confidence: 0\.[789]" {} \; 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$HIGH_CONFIDENCE_COUNT" -gt 0 ]]; then
    update_context "💡 $HIGH_CONFIDENCE_COUNT high-confidence instinct(s) available"
  fi
fi

# 6. Register session heartbeat (for cleanup detection)
HEARTBEAT_DIR="${CLAUDE_SKILLS_DIR}/heartbeats"
mkdir -p "$HEARTBEAT_DIR"
HEARTBEAT_FILE="${HEARTBEAT_DIR}/${SESSION_ID}"
echo "$(date +%s)" > "$HEARTBEAT_FILE"

# 7. Save session initialization state
SESSION_STATE_FILE="${SESSION_STATE_DIR}/${SESSION_ID}.json"
jq -n \
  --arg session_id "$SESSION_ID" \
  --arg cwd "$CWD" \
  --arg package_manager "$PACKAGE_MANAGER" \
  --arg git_branch "${GIT_BRANCH:-}" \
  --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  '{
    session_id: $session_id,
    start_time: $timestamp,
    cwd: $cwd,
    package_manager: $package_manager,
    git_branch: $git_branch,
    domains: []
  }' > "$SESSION_STATE_FILE"

# 8. Welcome message
update_context ""
update_context "✨ Claude Skills 2.0 initialized"
update_context "   Session ID: $SESSION_ID"
update_context "   Auto-invoke: enabled (10/hour limit)"
update_context "   Learning: enabled (pattern detection every 5 min)"

# Output result
echo "$OUTPUT_JSON"
exit 0
