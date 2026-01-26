#!/usr/bin/env bash
# OpenTelemetry-compatible telemetry exporter for automation decisions
# Exports metrics in OTLP JSON format for standard observability platforms

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Configuration ===

TELEMETRY_ENDPOINT="${AUTOMATION_TELEMETRY_ENDPOINT:-}"
EXPORT_FORMAT="${AUTOMATION_TELEMETRY_FORMAT:-otlp-json}"
EXPORT_DIR="${HOME}/.claude/automation-hub/telemetry"
SERVICE_NAME="automation-hub"
SERVICE_VERSION="1.0.0"

# === Initialize ===

mkdir -p "${EXPORT_DIR}"

# === Helper Functions ===

get_current_timestamp_ns() {
    # Get current time in nanoseconds (OpenTelemetry standard)
    local seconds
    seconds=$(date +%s)
    local nanoseconds=$((seconds * 1000000000))
    echo "${nanoseconds}"
}

generate_trace_id() {
    # Generate random 16-byte trace ID in hex (32 chars)
    LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 32
}

generate_span_id() {
    # Generate random 8-byte span ID in hex (16 chars)
    LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 16
}

# === Export Metrics to OTLP Format ===

export_decision_span() {
    local event_type="$1"
    local feature="$2"
    local decision="$3"
    local latency_ms="$4"
    local metadata="$5"

    local timestamp_ns
    timestamp_ns=$(get_current_timestamp_ns)

    local trace_id
    trace_id=$(generate_trace_id)

    local span_id
    span_id=$(generate_span_id)

    # Create OpenTelemetry span in OTLP JSON format
    local span
    span=$(jq -n \
        --arg trace_id "${trace_id}" \
        --arg span_id "${span_id}" \
        --arg name "${event_type}:${feature}" \
        --arg timestamp "${timestamp_ns}" \
        --arg latency "${latency_ms}" \
        --arg decision "${decision}" \
        --argjson metadata "${metadata}" \
        '{
            resourceSpans: [{
                resource: {
                    attributes: [
                        {key: "service.name", value: {stringValue: "automation-hub"}},
                        {key: "service.version", value: {stringValue: "1.0.0"}},
                        {key: "deployment.environment", value: {stringValue: "production"}}
                    ]
                },
                scopeSpans: [{
                    scope: {
                        name: "automation-hub.decisions",
                        version: "1.0.0"
                    },
                    spans: [{
                        traceId: $trace_id,
                        spanId: $span_id,
                        name: $name,
                        kind: 1,
                        startTimeUnixNano: $timestamp,
                        endTimeUnixNano: ($timestamp | tonumber + ($latency | tonumber * 1000000) | tostring),
                        attributes: [
                            {key: "automation.feature", value: {stringValue: $feature}},
                            {key: "automation.decision", value: {stringValue: $decision}},
                            {key: "automation.latency_ms", value: {intValue: ($latency | tonumber)}},
                            {key: "automation.metadata", value: {stringValue: ($metadata | tostring)}}
                        ],
                        status: {code: 1}
                    }]
                }]
            }]
        }')

    echo "${span}"
}

export_approval_metric() {
    local feature="$1"
    local approved="$2"
    local complexity_score="$3"

    local timestamp_ns
    timestamp_ns=$(get_current_timestamp_ns)

    # Create OpenTelemetry metric in OTLP JSON format
    local metric
    metric=$(jq -n \
        --arg timestamp "${timestamp_ns}" \
        --arg feature "${feature}" \
        --arg approved "${approved}" \
        --arg complexity "${complexity_score}" \
        '{
            resourceMetrics: [{
                resource: {
                    attributes: [
                        {key: "service.name", value: {stringValue: "automation-hub"}},
                        {key: "service.version", value: {stringValue: "1.0.0"}}
                    ]
                },
                scopeMetrics: [{
                    scope: {
                        name: "automation-hub.approvals",
                        version: "1.0.0"
                    },
                    metrics: [{
                        name: "automation.approval_rate",
                        description: "User approval rate for automation decisions",
                        unit: "1",
                        sum: {
                            dataPoints: [{
                                attributes: [
                                    {key: "feature", value: {stringValue: $feature}},
                                    {key: "complexity_band", value: {stringValue: $complexity}}
                                ],
                                startTimeUnixNano: $timestamp,
                                timeUnixNano: $timestamp,
                                asInt: (if $approved == "true" then 1 else 0 end)
                            }],
                            aggregationTemporality: 1,
                            isMonotonic: false
                        }
                    }]
                }]
            }]
        }')

    echo "${metric}"
}

# === Export All Recent Metrics ===

export_recent_metrics() {
    local lookback_hours="${1:-24}"

    local metrics_file
    metrics_file=$(get_metrics_path)

    if [[ ! -f "${metrics_file}" ]]; then
        debug "No metrics file found, nothing to export"
        return 0
    fi

    local cutoff_time
    cutoff_time=$(date -u -v-"${lookback_hours}"H +%s 2>/dev/null || date -u -d "${lookback_hours} hours ago" +%s)

    local export_file="${EXPORT_DIR}/export-$(date +%Y%m%d-%H%M%S).json"

    echo "📊 Exporting telemetry data (last ${lookback_hours} hours)..."
    echo ""

    # Extract recent metrics
    local recent_metrics
    recent_metrics=$(jq -s --arg cutoff "${cutoff_time}" \
        'map(select(.timestamp >= ($cutoff | tonumber)))' \
        "${metrics_file}")

    local count
    count=$(echo "${recent_metrics}" | jq 'length')

    if [[ ${count} -eq 0 ]]; then
        echo "No metrics found in last ${lookback_hours} hours"
        return 0
    fi

    echo "Found ${count} metrics to export"
    echo ""

    # Convert to OTLP format
    local otlp_spans='{"resourceSpans": []}'
    local otlp_metrics='{"resourceMetrics": []}'

    # Process decision events
    local decisions
    decisions=$(echo "${recent_metrics}" | jq -c '.[] | select(.event_type == "decision")')

    if [[ -n "${decisions}" ]]; then
        echo "Processing decision spans..."

        while IFS= read -r decision; do
            local feature
            feature=$(echo "${decision}" | jq -r '.data.feature // "unknown"')

            local outcome
            outcome=$(echo "${decision}" | jq -r '.data.decision // "unknown"')

            local latency
            latency=$(echo "${decision}" | jq -r '.data.latency_ms // 0')

            local metadata
            metadata=$(echo "${decision}" | jq -c '.data')

            local span
            span=$(export_decision_span "decision" "${feature}" "${outcome}" "${latency}" "${metadata}")

            # Append to spans collection
            otlp_spans=$(echo "${otlp_spans}" | jq --argjson span "${span}" \
                '.resourceSpans += $span.resourceSpans')

        done <<< "${decisions}"
    fi

    # Process approval events
    local approvals
    approvals=$(echo "${recent_metrics}" | jq -c '.[] | select(.event_type == "approval")')

    if [[ -n "${approvals}" ]]; then
        echo "Processing approval metrics..."

        while IFS= read -r approval; do
            local feature
            feature=$(echo "${approval}" | jq -r '.data.feature // "unknown"')

            local approved
            approved=$(echo "${approval}" | jq -r '.data.approved // "false"')

            local complexity
            complexity=$(echo "${approval}" | jq -r '.data.complexity_score // 0')

            # Classify complexity band
            local band="low"
            if [[ ${complexity} -ge 30 ]] && [[ ${complexity} -lt 50 ]]; then
                band="moderate"
            elif [[ ${complexity} -ge 50 ]] && [[ ${complexity} -lt 70 ]]; then
                band="complex"
            elif [[ ${complexity} -ge 70 ]]; then
                band="very_complex"
            fi

            local metric
            metric=$(export_approval_metric "${feature}" "${approved}" "${band}")

            # Append to metrics collection
            otlp_metrics=$(echo "${otlp_metrics}" | jq --argjson metric "${metric}" \
                '.resourceMetrics += $metric.resourceMetrics')

        done <<< "${approvals}"
    fi

    # Combine spans and metrics
    local export_data
    export_data=$(jq -n \
        --argjson spans "${otlp_spans}" \
        --argjson metrics "${otlp_metrics}" \
        '{
            spans: $spans,
            metrics: $metrics,
            exportedAt: (now | tostring),
            exportedCount: {
                spans: ($spans.resourceSpans | length),
                metrics: ($metrics.resourceMetrics | length)
            }
        }')

    # Save to file
    echo "${export_data}" | jq '.' > "${export_file}"

    echo "✓ Exported to: ${export_file}"
    echo ""

    # Send to endpoint if configured
    if [[ -n "${TELEMETRY_ENDPOINT}" ]]; then
        echo "Sending to telemetry endpoint: ${TELEMETRY_ENDPOINT}"

        # Send spans
        local spans_payload
        spans_payload=$(echo "${export_data}" | jq '.spans')

        if curl -s -X POST "${TELEMETRY_ENDPOINT}/v1/traces" \
            -H "Content-Type: application/json" \
            -d "${spans_payload}" > /dev/null 2>&1; then
            echo "✓ Spans sent successfully"
        else
            echo "⚠️  Failed to send spans (check endpoint configuration)"
        fi

        # Send metrics
        local metrics_payload
        metrics_payload=$(echo "${export_data}" | jq '.metrics')

        if curl -s -X POST "${TELEMETRY_ENDPOINT}/v1/metrics" \
            -H "Content-Type: application/json" \
            -d "${metrics_payload}" > /dev/null 2>&1; then
            echo "✓ Metrics sent successfully"
        else
            echo "⚠️  Failed to send metrics (check endpoint configuration)"
        fi
    fi

    echo ""
    echo "Summary:"
    echo "  Spans: $(echo "${export_data}" | jq '.exportedCount.spans')"
    echo "  Metrics: $(echo "${export_data}" | jq '.exportedCount.metrics')"
    echo "  Format: OpenTelemetry OTLP JSON"
}

# === Calculate Aggregate Statistics ===

calculate_statistics() {
    local export_file="$1"

    if [[ ! -f "${export_file}" ]]; then
        echo "Export file not found: ${export_file}"
        return 1
    fi

    echo "📈 Telemetry Statistics"
    echo ""

    local data
    data=$(cat "${export_file}")

    # Decision latency statistics
    local avg_latency
    avg_latency=$(echo "${data}" | jq -r '
        .spans.resourceSpans[].scopeSpans[].spans[] |
        .attributes[] | select(.key == "automation.latency_ms") |
        .value.intValue' | \
        jq -s 'add / length | floor')

    echo "Decision Latency:"
    echo "  Average: ${avg_latency}ms"
    echo ""

    # Approval rates by feature
    echo "Approval Rates:"
    echo "${data}" | jq -r '
        .metrics.resourceMetrics[].scopeMetrics[].metrics[] |
        select(.name == "automation.approval_rate") |
        .sum.dataPoints[] |
        "  " + (.attributes[] | select(.key == "feature") | .value.stringValue) + ": " +
        (if .asInt == 1 then "✓ Approved" else "✗ Rejected" end)' | head -10

    echo ""
}

# === Main ===

main() {
    local command="${1:-export}"

    case "${command}" in
        export)
            local hours="${2:-24}"
            export_recent_metrics "${hours}"
            ;;

        stats)
            local file="${2:-$(ls -t "${EXPORT_DIR}"/export-*.json 2>/dev/null | head -1)}"
            if [[ -n "${file}" ]]; then
                calculate_statistics "${file}"
            else
                echo "No export files found in ${EXPORT_DIR}"
                exit 1
            fi
            ;;

        configure)
            echo "OpenTelemetry Configuration"
            echo ""
            echo "Current Settings:"
            echo "  Endpoint: ${TELEMETRY_ENDPOINT:-not set}"
            echo "  Format: ${EXPORT_FORMAT}"
            echo "  Export Directory: ${EXPORT_DIR}"
            echo ""
            echo "To configure:"
            echo "  export AUTOMATION_TELEMETRY_ENDPOINT=http://localhost:4318"
            echo "  export AUTOMATION_TELEMETRY_FORMAT=otlp-json"
            echo ""
            echo "Compatible with:"
            echo "  - Grafana Cloud"
            echo "  - Honeycomb"
            echo "  - Datadog"
            echo "  - Braintrust"
            echo "  - Any OTLP-compatible backend"
            ;;

        *)
            cat <<'EOF'
Telemetry Exporter - OpenTelemetry-compatible metrics export

USAGE:
  telemetry-exporter.sh export [hours]    Export recent metrics (default: 24h)
  telemetry-exporter.sh stats [file]      Show statistics from export
  telemetry-exporter.sh configure         Show configuration help

EXAMPLES:
  telemetry-exporter.sh export           Export last 24 hours
  telemetry-exporter.sh export 168       Export last 7 days
  telemetry-exporter.sh stats            Show latest export stats

OPENTELEMETRY FORMAT:
  Exports in OTLP JSON format compatible with all major observability platforms.

  Traces: Decision events as spans with latency tracking
  Metrics: Approval rates, complexity distributions

CONFIGURATION:
  AUTOMATION_TELEMETRY_ENDPOINT   OTLP endpoint (e.g., http://localhost:4318)
  AUTOMATION_TELEMETRY_FORMAT     Export format (default: otlp-json)

EOF
            ;;
    esac
}

# Execute
main "$@"

exit 0
