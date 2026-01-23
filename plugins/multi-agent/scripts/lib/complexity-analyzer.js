#!/usr/bin/env node

/**
 * Complexity Analyzer - Core decision engine for multi-agent orchestration
 *
 * Analyzes requests to determine:
 * - Complexity score (0-100)
 * - Detected domains (security, performance, testing, etc.)
 * - Recommended coordination pattern
 * - Token cost estimates
 * - Optimal agent selection
 */

const fs = require('fs');
const path = require('path');

// Load agent registry
const REGISTRY_PATH = path.join(__dirname, 'agent-registry.json');
const registry = JSON.parse(fs.readFileSync(REGISTRY_PATH, 'utf8'));

/**
 * Estimate token count from request text
 * Rough approximation: 1 token ≈ 4 characters
 */
function estimateTokens(text) {
  const baseTokens = Math.ceil(text.length / 4);

  // Adjust based on complexity indicators
  const hasCodeBlocks = (text.match(/```/g) || []).length / 2;
  const hasMultipleSentences = (text.match(/[.!?]+/g) || []).length;
  const hasLists = (text.match(/^[\s]*[-*]\s/gm) || []).length;

  let multiplier = 1.0;
  if (hasCodeBlocks > 0) multiplier += 0.3;
  if (hasMultipleSentences > 5) multiplier += 0.2;
  if (hasLists > 3) multiplier += 0.1;

  return Math.ceil(baseTokens * multiplier);
}

/**
 * Detect domains from request keywords
 * Returns array of domain names with confidence scores
 */
function detectDomains(request) {
  const text = request.toLowerCase();
  const detectedDomains = [];

  Object.entries(registry.domain_keywords).forEach(([domain, keywords]) => {
    const matches = keywords.filter(kw => text.includes(kw.toLowerCase()));
    if (matches.length > 0) {
      detectedDomains.push({
        name: domain,
        confidence: matches.length / keywords.length,
        matchedKeywords: matches
      });
    }
  });

  // Sort by confidence and return top domains
  return detectedDomains
    .sort((a, b) => b.confidence - a.confidence)
    .map(d => d.name);
}

/**
 * Analyze structural complexity
 * Returns points based on task structure
 */
function analyzeStructure(request) {
  let structuralPoints = 0;
  const text = request.toLowerCase();

  // Multi-step indicators
  const stepIndicators = ['first', 'then', 'after', 'next', 'finally', 'and then'];
  const hasSteps = stepIndicators.some(ind => text.includes(ind));
  if (hasSteps) structuralPoints += 10;

  // Validation/review indicators
  const reviewIndicators = ['review', 'check', 'validate', 'verify', 'audit', 'analyze'];
  const needsReview = reviewIndicators.some(ind => text.includes(ind));
  if (needsReview) structuralPoints += 10;

  // Parallel work indicators
  const parallelIndicators = ['and', 'both', 'all', 'comprehensive', 'complete'];
  const hasParallelWork = parallelIndicators.some(ind => text.includes(ind));
  const multipleDomainsDetected = detectDomains(request).length > 1;
  if (hasParallelWork && multipleDomainsDetected) structuralPoints += 10;

  return Math.min(structuralPoints, 30); // Cap at 30 points
}

/**
 * Calculate overall complexity score (0-100)
 */
function calculateScore(tokens, domains, structural) {
  let score = 0;

  // Token-based scoring (max 40 points)
  if (tokens > 50000) score += 40;
  else if (tokens > 30000) score += 30;
  else if (tokens > 10000) score += 20;
  else if (tokens > 5000) score += 10;

  // Domain diversity (max 30 points)
  if (domains.length >= 3) score += 30;
  else if (domains.length === 2) score += 20;
  else if (domains.length === 1) score += 10;

  // Structural complexity (already capped at 30)
  score += structural;

  return Math.min(score, 100);
}

/**
 * Select coordination pattern based on score and domains
 */
function selectPattern(score, domains) {
  if (score < 30) {
    return 'single';
  } else if (score >= 30 && score < 50) {
    return 'sequential';
  } else if (score >= 50 && score < 70) {
    return domains.length > 1 ? 'parallel' : 'sequential';
  } else {
    return 'hierarchical';
  }
}

/**
 * Select optimal agents for detected domains
 */
function selectAgents(domains, pattern) {
  const selectedAgents = [];

  // For single pattern, use general-purpose
  if (pattern === 'single') {
    return ['general-purpose'];
  }

  // Match domains to agents
  domains.forEach(domain => {
    const agent = registry.agents.find(a =>
      a.capabilities.some(cap =>
        registry.domain_keywords[domain]?.includes(cap)
      )
    );

    if (agent && !selectedAgents.includes(agent.id)) {
      selectedAgents.push(agent.id);
    }
  });

  // Fallback to domain-specific defaults
  const domainDefaults = {
    'security': 'security-auditor',
    'performance': 'performance-engineer',
    'testing': 'test-automator',
    'review': 'code-reviewer',
    'architecture': 'architect-review',
    'debugging': 'debugger'
  };

  domains.forEach(domain => {
    const defaultAgent = domainDefaults[domain];
    if (defaultAgent && !selectedAgents.includes(defaultAgent)) {
      selectedAgents.push(defaultAgent);
    }
  });

  // Limit based on pattern
  const limits = {
    'sequential': 2,
    'parallel': 3,
    'hierarchical': 5
  };

  return selectedAgents.slice(0, limits[pattern] || 1);
}

/**
 * Estimate execution cost
 */
function estimateCost(agents, baseTokens) {
  const agentCount = agents.length;
  const avgTokensPerAgent = agents.reduce((sum, agentId) => {
    const agent = registry.agents.find(a => a.id === agentId);
    return sum + (agent?.avg_tokens || 5000);
  }, 0) / agentCount;

  const singleAgentCost = baseTokens + 5000; // Base + overhead
  const multiAgentCost = baseTokens + (avgTokensPerAgent * agentCount);

  return {
    single: singleAgentCost,
    multi: multiAgentCost,
    multiplier: `${Math.round(multiAgentCost / singleAgentCost)}x`
  };
}

/**
 * Main analysis function
 */
function analyzeComplexity(request, tokenBudget = 200000) {
  const tokens = estimateTokens(request);
  const domains = detectDomains(request);
  const structural = analyzeStructure(request);

  // Calculate token points explicitly
  let tokenPoints = 0;
  if (tokens > 50000) tokenPoints = 40;
  else if (tokens > 30000) tokenPoints = 30;
  else if (tokens > 10000) tokenPoints = 20;
  else if (tokens > 5000) tokenPoints = 10;

  // Calculate domain points
  const domainPoints = domains.length >= 3 ? 30 : domains.length * 10;

  const score = calculateScore(tokens, domains, structural);
  const pattern = selectPattern(score, domains);
  const agents = selectAgents(domains, pattern);
  const cost = estimateCost(agents, tokens);

  return {
    complexity_score: score,
    token_estimate: tokens,
    domains: domains,
    pattern: pattern,
    recommended_agents: agents,
    cost: cost,
    within_budget: cost.multi <= tokenBudget,
    analysis: {
      token_points: tokenPoints,
      domain_points: domainPoints,
      structural_points: structural
    }
  };
}

// CLI interface
if (require.main === module) {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    console.error('Usage: complexity-analyzer.js "<request>" [token_budget]');
    process.exit(1);
  }

  const request = args[0];
  const tokenBudget = parseInt(args[1]) || 200000;

  const result = analyzeComplexity(request, tokenBudget);
  console.log(JSON.stringify(result, null, 2));
}

module.exports = { analyzeComplexity, estimateTokens, detectDomains };
