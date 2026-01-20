# Contributing to Reflect Plugin

Thank you for your interest in contributing to the Reflect plugin!

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/Cain-Ish/claude-skills.git
   cd claude-skills/plugins/reflect
   ```

2. Install dependencies:
   - **Required**: `git`, `bash 4.0+`
   - **Recommended**: `jq` (for JSON parsing)
   - **Optional**: `node` (for cross-platform JSON utilities)

3. Run tests:
   ```bash
   cd tests
   ./run_all_tests.sh
   ```

## Project Structure

```
plugins/reflect/
├── .claude-plugin/
│   └── plugin.json         # Plugin manifest
├── agents/
│   └── reflect-critic.md   # Validation sub-agent
├── commands/
│   └── reflect.md          # Slash command definition
├── config/
│   └── default-config.json # Default configuration
├── hooks/
│   ├── PreToolUse.md       # Pre-commit hook
│   └── Stop.md             # End-of-session hook
├── scripts/
│   ├── lib/
│   │   ├── common.sh       # Shared functions
│   │   ├── platform.sh     # Cross-platform wrappers
│   │   └── json-utils.js   # Node.js JSON utilities
│   ├── reflect.sh          # Main command dispatcher
│   ├── reflect-*.sh        # Feature scripts
│   └── ...
├── skills/
│   └── reflect/
│       ├── SKILL.md        # Main workflow
│       └── references/     # Documentation
├── CHANGELOG.md
├── CONTRIBUTING.md
└── README.md
```

## Code Style

### Bash Scripts

- Use `shellcheck` for linting
- Follow Google Shell Style Guide
- Source shared library at top of scripts:
  ```bash
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/lib/common.sh"
  source "$SCRIPT_DIR/lib/platform.sh"
  ```
- Use functions from common.sh:
  - `log_info`, `log_warn`, `log_error`, `log_debug` for logging
  - `extract_json_field`, `extract_json_bool` for JSON parsing
  - `validate_skill_name`, `validate_action` for input validation
  - `with_lock`, `append_jsonl` for file operations
- Add comments for non-obvious logic
- Use `set -euo pipefail` at the start

### Markdown Files

- Use consistent heading levels
- Include examples where applicable
- Keep line length under 100 characters

## Testing

### Running Tests

```bash
# Run all tests
cd tests && ./run_all_tests.sh

# Run specific test
./tests/test_common.sh
```

### Writing Tests

1. Create test file in `tests/` directory
2. Source the script being tested
3. Use simple pass/fail assertions:
   ```bash
   test_function_name() {
       result=$(function_to_test "input")
       if [ "$result" = "expected" ]; then
           pass "function_name"
       else
           fail "function_name: expected 'expected', got '$result'"
       fi
   }
   ```

## Pull Request Process

1. **Fork** the repository
2. **Create a branch**: `git checkout -b feature/your-feature`
3. **Make changes** following code style guidelines
4. **Test** your changes
5. **Update CHANGELOG.md** with your changes
6. **Commit** with clear messages
7. **Push** to your fork
8. **Create PR** with clear description

### Commit Message Format

```
type(scope): description

[optional body]

[optional footer]
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `refactor`: Code refactoring
- `test`: Adding tests
- `chore`: Maintenance

Example:
```
feat(stats): add JSON output option

Added --json flag to reflect-stats.sh for machine-readable output.
Useful for integrating with other tools.
```

## Reporting Issues

When reporting issues, please include:

1. **Description**: What happened vs what you expected
2. **Steps to reproduce**: Minimal steps to trigger the issue
3. **Environment**:
   - OS and version
   - Bash version (`bash --version`)
   - jq version if applicable (`jq --version`)
4. **Logs**: Relevant output with `DEBUG_REFLECT=1`

## Feature Requests

For feature requests, please describe:

1. **Use case**: Why you need this feature
2. **Proposed solution**: How you envision it working
3. **Alternatives**: Other approaches you considered

## Questions?

Open an issue with the `question` label or reach out to the maintainers.
