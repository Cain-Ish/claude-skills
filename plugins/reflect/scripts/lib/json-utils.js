#!/usr/bin/env node
/**
 * Reflect Plugin - JSON Utilities
 * ================================
 * Cross-platform JSON manipulation utilities for systems without jq.
 *
 * Usage:
 *   node json-utils.js <command> [args...]
 *
 * Commands:
 *   get <file> <field>              - Extract field from JSON file
 *   set <file> <field> <value>      - Set field in JSON file
 *   append <file> <json>            - Append JSON line to JSONL file
 *   query <file> <jq-like-filter>   - Query JSONL file
 *   stats <file>                    - Get stats from metrics JSONL
 */

const fs = require('fs');
const path = require('path');

// ============================================================================
// Helper Functions
// ============================================================================

function readJsonFile(filePath) {
    try {
        const content = fs.readFileSync(filePath, 'utf8');
        return JSON.parse(content);
    } catch (err) {
        if (err.code === 'ENOENT') {
            return null;
        }
        throw err;
    }
}

function writeJsonFile(filePath, data) {
    const dir = path.dirname(filePath);
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
    }
    fs.writeFileSync(filePath, JSON.stringify(data, null, 2) + '\n');
}

function readJsonlFile(filePath) {
    try {
        const content = fs.readFileSync(filePath, 'utf8');
        return content
            .split('\n')
            .filter(line => line.trim() && !line.trim().startsWith('#'))
            .map(line => {
                try {
                    return JSON.parse(line);
                } catch {
                    return null;
                }
            })
            .filter(obj => obj !== null);
    } catch (err) {
        if (err.code === 'ENOENT') {
            return [];
        }
        throw err;
    }
}

function appendJsonlFile(filePath, data) {
    const dir = path.dirname(filePath);
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
    }
    const line = typeof data === 'string' ? data : JSON.stringify(data);
    fs.appendFileSync(filePath, line + '\n');
}

function getNestedValue(obj, path) {
    const keys = path.split('.');
    let value = obj;
    for (const key of keys) {
        if (value === null || value === undefined) {
            return undefined;
        }
        value = value[key];
    }
    return value;
}

function setNestedValue(obj, path, value) {
    const keys = path.split('.');
    let current = obj;
    for (let i = 0; i < keys.length - 1; i++) {
        const key = keys[i];
        if (!(key in current)) {
            current[key] = {};
        }
        current = current[key];
    }
    current[keys[keys.length - 1]] = value;
    return obj;
}

// ============================================================================
// Commands
// ============================================================================

function cmdGet(args) {
    const [filePath, field] = args;
    if (!filePath || !field) {
        console.error('Usage: json-utils.js get <file> <field>');
        process.exit(1);
    }

    const data = readJsonFile(filePath);
    if (data === null) {
        console.log('');
        return;
    }

    const value = getNestedValue(data, field);
    if (value === undefined) {
        console.log('');
    } else if (typeof value === 'object') {
        console.log(JSON.stringify(value));
    } else {
        console.log(value);
    }
}

function cmdSet(args) {
    const [filePath, field, ...valueParts] = args;
    const valueStr = valueParts.join(' ');

    if (!filePath || !field || valueStr === undefined) {
        console.error('Usage: json-utils.js set <file> <field> <value>');
        process.exit(1);
    }

    let data = readJsonFile(filePath) || {};

    // Try to parse value as JSON, otherwise use as string
    let value;
    try {
        value = JSON.parse(valueStr);
    } catch {
        value = valueStr;
    }

    data = setNestedValue(data, field, value);
    writeJsonFile(filePath, data);
    console.log('OK');
}

function cmdAppend(args) {
    const [filePath, ...jsonParts] = args;
    const jsonStr = jsonParts.join(' ');

    if (!filePath || !jsonStr) {
        console.error('Usage: json-utils.js append <file> <json>');
        process.exit(1);
    }

    let data;
    try {
        data = JSON.parse(jsonStr);
    } catch (err) {
        console.error('Invalid JSON:', err.message);
        process.exit(1);
    }

    appendJsonlFile(filePath, data);
    console.log('OK');
}

function cmdQuery(args) {
    const [filePath, ...filterParts] = args;
    const filter = filterParts.join(' ');

    if (!filePath) {
        console.error('Usage: json-utils.js query <file> [filter]');
        process.exit(1);
    }

    const data = readJsonlFile(filePath);

    if (!filter) {
        // No filter, return all
        data.forEach(item => console.log(JSON.stringify(item)));
        return;
    }

    // Simple filter support: field=value or field==value
    const match = filter.match(/^\.?(\w+(?:\.\w+)*)\s*={1,2}\s*"?([^"]*)"?$/);
    if (match) {
        const [, field, value] = match;
        const filtered = data.filter(item => {
            const itemValue = getNestedValue(item, field);
            return String(itemValue) === value;
        });
        filtered.forEach(item => console.log(JSON.stringify(item)));
        return;
    }

    // Select field: .field
    const selectMatch = filter.match(/^\.(\w+(?:\.\w+)*)$/);
    if (selectMatch) {
        const field = selectMatch[1];
        data.forEach(item => {
            const value = getNestedValue(item, field);
            if (value !== undefined) {
                console.log(typeof value === 'object' ? JSON.stringify(value) : value);
            }
        });
        return;
    }

    console.error('Unsupported filter syntax. Supported: .field, .field=value');
    process.exit(1);
}

function cmdStats(args) {
    const [filePath, skill] = args;

    if (!filePath) {
        console.error('Usage: json-utils.js stats <file> [skill]');
        process.exit(1);
    }

    const data = readJsonlFile(filePath);

    // Filter by skill if provided
    let proposals = data.filter(item => item.type === 'proposal');
    let outcomes = data.filter(item => item.type === 'outcome');

    if (skill) {
        proposals = proposals.filter(item => item.skill === skill);
        outcomes = outcomes.filter(item => item.skill === skill);
    }

    // Calculate stats
    const totalProposals = proposals.length;
    const approved = proposals.filter(p => p.user_action === 'approved').length;
    const rejected = proposals.filter(p => p.user_action === 'rejected').length;
    const modified = proposals.filter(p => p.user_action === 'modified').length;
    const deferred = proposals.filter(p => p.user_action === 'deferred').length;

    const acceptedCount = approved + modified;
    const acceptanceRate = totalProposals > 0
        ? ((acceptedCount / totalProposals) * 100).toFixed(1)
        : 0;

    const totalOutcomes = outcomes.length;
    const helpfulCount = outcomes.filter(o => o.improvement_helpful === true).length;
    const effectivenessRate = totalOutcomes > 0
        ? ((helpfulCount / totalOutcomes) * 100).toFixed(1)
        : 0;

    const stats = {
        skill: skill || 'all',
        proposals: {
            total: totalProposals,
            approved,
            rejected,
            modified,
            deferred,
            acceptanceRate: parseFloat(acceptanceRate)
        },
        outcomes: {
            total: totalOutcomes,
            helpful: helpfulCount,
            notHelpful: totalOutcomes - helpfulCount,
            effectivenessRate: parseFloat(effectivenessRate)
        }
    };

    console.log(JSON.stringify(stats, null, 2));
}

function cmdCount(args) {
    const [filePath, ...filterParts] = args;
    const filter = filterParts.join(' ');

    if (!filePath) {
        console.error('Usage: json-utils.js count <file> [filter]');
        process.exit(1);
    }

    const data = readJsonlFile(filePath);

    if (!filter) {
        console.log(data.length);
        return;
    }

    // Simple filter: field=value
    const match = filter.match(/^\.?(\w+(?:\.\w+)*)\s*={1,2}\s*"?([^"]*)"?$/);
    if (match) {
        const [, field, value] = match;
        const count = data.filter(item => {
            const itemValue = getNestedValue(item, field);
            return String(itemValue) === value;
        }).length;
        console.log(count);
        return;
    }

    console.error('Unsupported filter syntax');
    process.exit(1);
}

function cmdLast(args) {
    const [filePath, countStr, ...filterParts] = args;
    const count = parseInt(countStr) || 1;
    const filter = filterParts.join(' ');

    if (!filePath) {
        console.error('Usage: json-utils.js last <file> <count> [filter]');
        process.exit(1);
    }

    let data = readJsonlFile(filePath);

    // Apply filter if provided
    if (filter) {
        const match = filter.match(/^\.?(\w+(?:\.\w+)*)\s*={1,2}\s*"?([^"]*)"?$/);
        if (match) {
            const [, field, value] = match;
            data = data.filter(item => {
                const itemValue = getNestedValue(item, field);
                return String(itemValue) === value;
            });
        }
    }

    // Get last N items
    const lastItems = data.slice(-count);
    lastItems.forEach(item => console.log(JSON.stringify(item)));
}

// ============================================================================
// Main
// ============================================================================

const [,, command, ...args] = process.argv;

switch (command) {
    case 'get':
        cmdGet(args);
        break;
    case 'set':
        cmdSet(args);
        break;
    case 'append':
        cmdAppend(args);
        break;
    case 'query':
        cmdQuery(args);
        break;
    case 'stats':
        cmdStats(args);
        break;
    case 'count':
        cmdCount(args);
        break;
    case 'last':
        cmdLast(args);
        break;
    default:
        console.error(`
Reflect Plugin - JSON Utilities

Usage: node json-utils.js <command> [args...]

Commands:
  get <file> <field>              Extract field from JSON file
  set <file> <field> <value>      Set field in JSON file
  append <file> <json>            Append JSON line to JSONL file
  query <file> [filter]           Query JSONL file (.field or .field=value)
  stats <file> [skill]            Get metrics stats
  count <file> [filter]           Count matching lines
  last <file> <count> [filter]    Get last N matching lines

Examples:
  node json-utils.js get config.json thresholds.consecutiveRejections
  node json-utils.js set config.json enabled true
  node json-utils.js append metrics.jsonl '{"type":"proposal","skill":"test"}'
  node json-utils.js query metrics.jsonl .type=proposal
  node json-utils.js stats metrics.jsonl frontend-design
  node json-utils.js count metrics.jsonl .skill=reflect
  node json-utils.js last metrics.jsonl 5 .type=proposal
`);
        process.exit(1);
}
