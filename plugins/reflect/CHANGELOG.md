# Changelog

All notable changes to the Reflect plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-01-19

### Added
- **Shared library** (`lib/common.sh`) - Consolidates common functions across all scripts
- **Cross-platform support** (`lib/platform.sh`) - Platform-specific wrappers for macOS, Linux, Windows
- **Node.js JSON utilities** (`lib/json-utils.js`) - Fallback for systems without jq
- **Configuration system** - Customizable thresholds via `~/.claude/reflect-config.json`
- **File locking** - Prevents race conditions in concurrent metrics writes
- **Input validation** - Security-focused validation for skill names and actions
- **Config command** - `/reflect config` for configuration management
- **Color-coded output** - Visual feedback with color-coded log levels
- **CONTRIBUTING.md** - Contribution guidelines
- **CHANGELOG.md** - Version history

### Changed
- Scripts now source shared library instead of duplicating code
- JSON parsing uses `jq` with fallback to `python3` or `node`
- Consecutive rejection threshold is now configurable (default: 3)
- Stats output uses bash arithmetic instead of `bc` dependency
- Improved cross-platform `stat` command handling

### Fixed
- Race condition when multiple processes write to metrics file
- JSON parsing failures on special characters
- `tac` command not available on macOS (uses `tail -r` or `awk` fallback)
- Hardcoded paths replaced with configurable variables

### Security
- Added skill name validation to prevent path traversal
- Input sanitization for all user-provided values

## [1.0.0] - 2026-01-19

### Added
- Initial plugin release for Claude Code marketplace
- Core reflect skill for session analysis and skill improvement
- Signal detection (corrections, successes, edge cases)
- Proposal generation with confidence levels
- Critic agent for 12-factor validation
- Metrics tracking (JSONL format)
- Memory system for skill knowledge
- Auto-pause on consecutive rejections
- Commands: on, off, status, stats, validate, resume, analyze-all, cleanup, improve

### Scripts
- `reflect.sh` - Main command dispatcher
- `reflect-track-proposal.sh` - Proposal event logging
- `reflect-track-outcome.sh` - Outcome tracking
- `reflect-stats.sh` - Effectiveness metrics
- `reflect-analyze-effectiveness.sh` - Meta-analysis
- `reflect-commit-changes.sh` - Git integration
- `reflect-cleanup-memories.sh` - Memory maintenance
- `reflect-analyze-all.sh` - Batch analysis
- `reflect-config.sh` - Configuration management

### Hooks
- `PreToolUse` - Pre-commit validation
- `Stop` - End-of-session reflection trigger

---

## Version History

| Version | Date | Description |
|---------|------|-------------|
| 1.1.0 | 2026-01-19 | Architecture improvements, cross-platform support |
| 1.0.0 | 2026-01-19 | Initial marketplace release |
