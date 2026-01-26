#!/usr/bin/env bash
# Generate real-time HTML dashboard from automation metrics
# Visualizes approval trends, routing accuracy, learning progress

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Configuration ===

DASHBOARD_DIR="${HOME}/.claude/automation-hub/dashboard"
DASHBOARD_FILE="${DASHBOARD_DIR}/index.html"

# === Initialize ===

mkdir -p "${DASHBOARD_DIR}"

# === Data Aggregation ===

aggregate_metrics() {
    local lookback_days="${1:-7}"

    local metrics_file
    metrics_file=$(get_metrics_path)

    if [[ ! -f "${metrics_file}" ]]; then
        echo "{}"
        return 0
    fi

    local cutoff_time
    cutoff_time=$(date -u -v-"${lookback_days}"d +%s 2>/dev/null || date -u -d "${lookback_days} days ago" +%s)

    # Load recent metrics
    local recent_metrics
    recent_metrics=$(jq -s --arg cutoff "${cutoff_time}" \
        'map(select(.timestamp >= ($cutoff | tonumber)))' \
        "${metrics_file}")

    # Calculate approval rates by complexity band
    local approval_stats
    approval_stats=$(echo "${recent_metrics}" | jq -r '
        map(select(.event_type == "approval")) |
        group_by(.data.complexity_band // "unknown") |
        map({
            band: .[0].data.complexity_band // "unknown",
            total: length,
            approved: (map(select(.data.approved == true)) | length),
            approval_rate: ((map(select(.data.approved == true)) | length) / length * 100 | floor)
        })' 2>/dev/null || echo '[]')

    # Calculate routing accuracy
    local routing_stats
    routing_stats=$(echo "${recent_metrics}" | jq -r '
        map(select(.event_type == "decision" and .data.feature == "auto_routing")) |
        {
            total_invocations: length,
            auto_approved: (map(select(.data.decision == "auto_approved")) | length),
            presented: (map(select(.data.decision == "presented")) | length),
            skipped: (map(select(.data.decision == "skipped")) | length)
        }' 2>/dev/null || echo '{}')

    # Calculate average decision latency
    local latency_stats
    latency_stats=$(echo "${recent_metrics}" | jq -r '
        map(select(.event_type == "decision" and .data.latency_ms)) |
        if length > 0 then
            {
                avg_latency_ms: (map(.data.latency_ms) | add / length | floor),
                max_latency_ms: (map(.data.latency_ms) | max),
                min_latency_ms: (map(.data.latency_ms) | min)
            }
        else
            {avg_latency_ms: 0, max_latency_ms: 0, min_latency_ms: 0}
        end' 2>/dev/null || echo '{}')

    # Learning progress
    local proposals_dir="${HOME}/.claude/automation-hub/proposals"
    local pending_proposals=0
    local applied_proposals=0

    if [[ -d "${proposals_dir}" ]]; then
        pending_proposals=$(ls -1 "${proposals_dir}"/*.json 2>/dev/null | wc -l | tr -d ' ')
    fi

    applied_proposals=$(echo "${recent_metrics}" | jq -r '
        map(select(.event_type == "proposal_applied")) | length' 2>/dev/null || echo '0')

    # Combine all stats
    jq -n \
        --argjson approval "${approval_stats}" \
        --argjson routing "${routing_stats}" \
        --argjson latency "${latency_stats}" \
        --arg pending "${pending_proposals}" \
        --arg applied "${applied_proposals}" \
        --arg lookback "${lookback_days}" \
        '{
            approval_by_band: $approval,
            routing_accuracy: $routing,
            latency: $latency,
            learning: {
                pending_proposals: ($pending | tonumber),
                applied_proposals: ($applied | tonumber)
            },
            lookback_days: ($lookback | tonumber),
            generated_at: (now | tostring)
        }'
}

# === HTML Dashboard Generation (XSS-Safe) ===

generate_html_dashboard() {
    local stats="$1"

    cat > "${DASHBOARD_FILE}" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="Content-Security-Policy" content="default-src 'self' 'unsafe-inline';">
    <title>Automation Hub - Observability Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: #0a0a0a;
            color: #e0e0e0;
            padding: 20px;
            line-height: 1.6;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
        }

        header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 30px;
            border-radius: 10px;
            margin-bottom: 30px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.3);
        }

        h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            color: white;
        }

        .subtitle {
            color: rgba(255, 255, 255, 0.9);
            font-size: 1.1em;
        }

        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }

        .card {
            background: #1a1a1a;
            border: 1px solid #333;
            border-radius: 10px;
            padding: 25px;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2);
            transition: transform 0.2s, box-shadow 0.2s;
        }

        .card:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.3);
        }

        .card-title {
            font-size: 1.2em;
            margin-bottom: 15px;
            color: #667eea;
            font-weight: 600;
        }

        .metric {
            margin: 15px 0;
        }

        .metric-label {
            color: #888;
            font-size: 0.9em;
            margin-bottom: 5px;
        }

        .metric-value {
            font-size: 2em;
            font-weight: bold;
            color: #e0e0e0;
        }

        .metric-value.good {
            color: #4caf50;
        }

        .metric-value.warning {
            color: #ff9800;
        }

        .metric-value.error {
            color: #f44336;
        }

        .progress-bar {
            width: 100%;
            height: 10px;
            background: #333;
            border-radius: 5px;
            overflow: hidden;
            margin-top: 10px;
        }

        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #667eea 0%, #764ba2 100%);
            transition: width 0.3s;
        }

        .band-stats {
            margin: 10px 0;
            padding: 10px;
            background: #222;
            border-radius: 5px;
            border-left: 3px solid #667eea;
        }

        .band-name {
            font-weight: 600;
            color: #667eea;
            margin-bottom: 5px;
        }

        .band-metrics {
            display: flex;
            justify-content: space-between;
            font-size: 0.9em;
            color: #888;
        }

        .timestamp {
            text-align: center;
            color: #666;
            font-size: 0.9em;
            margin-top: 30px;
        }

        .no-data {
            color: #666;
            font-style: italic;
        }

        @media (max-width: 768px) {
            .grid {
                grid-template-columns: 1fr;
            }

            h1 {
                font-size: 1.8em;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🤖 Automation Hub</h1>
            <p class="subtitle">Observability Dashboard - Production Monitoring</p>
        </header>

        <div id="dashboard" class="grid">
            <!-- Dashboard content will be inserted here using safe DOM methods -->
        </div>

        <div class="timestamp">
            Last updated: <span id="update-time"></span>
        </div>
    </div>

    <script>
        const stats = STATS_PLACEHOLDER;

        function createElement(tag, className, textContent) {
            const el = document.createElement(tag);
            if (className) el.className = className;
            if (textContent) el.textContent = textContent;
            return el;
        }

        function renderDashboard() {
            const container = document.getElementById('dashboard');
            container.textContent = ''; // Clear existing content

            // Render cards using safe DOM methods
            container.appendChild(renderApprovalRates(stats.approval_by_band));
            container.appendChild(renderRoutingAccuracy(stats.routing_accuracy));
            container.appendChild(renderPerformance(stats.latency));
            container.appendChild(renderLearning(stats.learning));

            // Update timestamp
            const updateTime = new Date(parseFloat(stats.generated_at) * 1000);
            document.getElementById('update-time').textContent = updateTime.toLocaleString();
        }

        function renderApprovalRates(bands) {
            const card = createElement('div', 'card');
            const title = createElement('div', 'card-title', '📊 Approval Rates by Complexity');
            card.appendChild(title);

            if (!bands || bands.length === 0) {
                const noData = createElement('p', 'no-data', 'No approval data available yet');
                card.appendChild(noData);
                return card;
            }

            bands.forEach(band => {
                const bandDiv = createElement('div', 'band-stats');

                const bandName = createElement('div', 'band-name', capitalizeWords(band.band));
                bandDiv.appendChild(bandName);

                const metrics = createElement('div', 'band-metrics');

                const color = band.approval_rate >= 70 ? 'good' : band.approval_rate >= 50 ? 'warning' : 'error';
                const rateSpan = document.createElement('span');
                rateSpan.textContent = 'Rate: ';
                const rateStrong = createElement('strong', color, band.approval_rate + '%');
                rateSpan.appendChild(rateStrong);

                const totalSpan = createElement('span', '', 'Total: ' + band.total);
                const approvedSpan = createElement('span', '', 'Approved: ' + band.approved);

                metrics.appendChild(rateSpan);
                metrics.appendChild(totalSpan);
                metrics.appendChild(approvedSpan);
                bandDiv.appendChild(metrics);

                const progressBar = createElement('div', 'progress-bar');
                const progressFill = createElement('div', 'progress-fill');
                progressFill.style.width = band.approval_rate + '%';
                progressBar.appendChild(progressFill);
                bandDiv.appendChild(progressBar);

                card.appendChild(bandDiv);
            });

            return card;
        }

        function renderRoutingAccuracy(routing) {
            const card = createElement('div', 'card');
            const title = createElement('div', 'card-title', '🎯 Routing Accuracy');
            card.appendChild(title);

            if (!routing || routing.total_invocations === 0) {
                const noData = createElement('p', 'no-data', 'No routing data available yet');
                card.appendChild(noData);
                return card;
            }

            const totalDiv = createElement('div', 'metric');
            totalDiv.appendChild(createElement('div', 'metric-label', 'Total Invocations'));
            totalDiv.appendChild(createElement('div', 'metric-value', routing.total_invocations.toString()));
            card.appendChild(totalDiv);

            const autoRate = Math.floor((routing.auto_approved / routing.total_invocations) * 100);
            const autoDiv = createElement('div', 'metric');
            autoDiv.appendChild(createElement('div', 'metric-label', 'Auto-Approved'));
            autoDiv.appendChild(createElement('div', 'metric-value good',
                routing.auto_approved + ' (' + autoRate + '%)'));
            card.appendChild(autoDiv);

            const skipRate = Math.floor((routing.skipped / routing.total_invocations) * 100);
            const skipDiv = createElement('div', 'metric');
            skipDiv.appendChild(createElement('div', 'metric-label', 'Skipped (Simple Prompts)'));
            skipDiv.appendChild(createElement('div', 'metric-value',
                routing.skipped + ' (' + skipRate + '%)'));
            card.appendChild(skipDiv);

            return card;
        }

        function renderPerformance(latency) {
            const card = createElement('div', 'card');
            const title = createElement('div', 'card-title', '⚡ Performance Metrics');
            card.appendChild(title);

            if (!latency || latency.avg_latency_ms === 0) {
                const noData = createElement('p', 'no-data', 'No latency data available yet');
                card.appendChild(noData);
                return card;
            }

            const avgColor = latency.avg_latency_ms < 100 ? 'good' :
                             latency.avg_latency_ms < 500 ? 'warning' : 'error';

            const avgDiv = createElement('div', 'metric');
            avgDiv.appendChild(createElement('div', 'metric-label', 'Average Latency'));
            avgDiv.appendChild(createElement('div', 'metric-value ' + avgColor,
                latency.avg_latency_ms + 'ms'));
            card.appendChild(avgDiv);

            const rangeDiv = createElement('div', 'metric');
            rangeDiv.appendChild(createElement('div', 'metric-label', 'Min / Max'));
            const rangeValue = createElement('div', 'metric-value');
            rangeValue.style.fontSize = '1.2em';
            rangeValue.textContent = latency.min_latency_ms + 'ms / ' + latency.max_latency_ms + 'ms';
            rangeDiv.appendChild(rangeValue);
            card.appendChild(rangeDiv);

            return card;
        }

        function renderLearning(learning) {
            const card = createElement('div', 'card');
            const title = createElement('div', 'card-title', '🧠 Learning Progress');
            card.appendChild(title);

            const pendingDiv = createElement('div', 'metric');
            pendingDiv.appendChild(createElement('div', 'metric-label', 'Pending Proposals'));
            pendingDiv.appendChild(createElement('div',
                'metric-value' + (learning.pending_proposals > 0 ? ' warning' : ''),
                learning.pending_proposals.toString()));
            card.appendChild(pendingDiv);

            const appliedDiv = createElement('div', 'metric');
            appliedDiv.appendChild(createElement('div', 'metric-label', 'Applied Optimizations'));
            appliedDiv.appendChild(createElement('div', 'metric-value good',
                learning.applied_proposals.toString()));
            card.appendChild(appliedDiv);

            if (learning.pending_proposals > 0) {
                const notice = createElement('p', '');
                notice.style.color = '#ff9800';
                notice.style.marginTop = '15px';
                notice.textContent = '💡 Review pending proposals with: /orchestrate proposals';
                card.appendChild(notice);
            }

            return card;
        }

        function capitalizeWords(str) {
            return str.split('_').map(word =>
                word.charAt(0).toUpperCase() + word.slice(1)
            ).join(' ');
        }

        // Initialize
        renderDashboard();

        // Auto-refresh every 60 seconds
        setInterval(() => {
            window.location.reload();
        }, 60000);
    </script>
</body>
</html>
EOF

    # Inject stats data
    local stats_escaped
    stats_escaped=$(echo "${stats}" | jq -c '.')

    # Use sed to replace placeholder
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "s|STATS_PLACEHOLDER|${stats_escaped}|g" "${DASHBOARD_FILE}"
    else
        sed -i "s|STATS_PLACEHOLDER|${stats_escaped}|g" "${DASHBOARD_FILE}"
    fi
}

# === Main ===

main() {
    local lookback_days="${1:-7}"

    echo "📊 Generating Observability Dashboard..."
    echo ""

    # Aggregate metrics
    local stats
    stats=$(aggregate_metrics "${lookback_days}")

    # Generate HTML
    generate_html_dashboard "${stats}"

    echo "✓ Dashboard generated: ${DASHBOARD_FILE}"
    echo ""
    echo "View in browser:"
    echo "  open ${DASHBOARD_FILE}"
    echo ""
    echo "Or with live server:"
    echo "  python3 -m http.server 8000 --directory ${DASHBOARD_DIR}"
    echo "  Then visit: http://localhost:8000"
    echo ""
    echo "Auto-refresh: Every 60 seconds"
}

# Execute
main "$@"

exit 0
