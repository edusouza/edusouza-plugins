# Observability Investigation Guide

This phase is **optional** and **backend-agnostic**. First determine which observability backend is
connected this session, then map the generic investigation steps below to that backend's tools. If no
observability tooling is available, skip the phase and work from the stack traces/logs in the issue plus
the code analysis.

## Detecting the backend

Look for connected MCP servers or CLIs such as:

| Backend | Typical tools |
|---------|---------------|
| GCP Cloud Operations | `mcp__observability__*` (logs, error groups, traces, metrics, alerts), `mcp__cloud-run__*` |
| Datadog | logs search, APM traces, monitors, metrics queries |
| Sentry | issues/error groups, events, stack traces, releases |
| AWS CloudWatch | Logs Insights queries, metrics, alarms, X-Ray traces |
| Grafana / Loki / Tempo | LogQL, metrics, traces |
| Honeycomb | events, traces, triggers |
| Plain logs | `kubectl logs`, `docker logs`, a log file, or a hosting dashboard |

## Investigation Order

Follow this sequence to maximize signal while minimizing noise. Use whichever backend equivalents exist.

### 1. Error groups / issues (start here for error-class bugs)
- Filter by a time window matching the bug report
- Find the error group/issue matching the reported symptoms
- Note: error count, first/last seen, affected service, release/version

### 2. Logs (primary investigation tool)
- Filter by severity (`ERROR`, `WARNING`) and the timestamp from the report
- Search for: stack traces, error messages, request/correlation IDs
- Look for patterns: repeated errors, correlated failures, a specific tenant/account
- Generic filter shapes (translate to your query language):
  - severity `>= ERROR` for the affected service
  - message/text matches the error string from the issue
  - a structured field equals the tenant/account/request ID from the issue
  - request URL matches the affected endpoint

### 3. Traces (for latency/timeout bugs)
- Find traces matching the time window and endpoint
- Check span durations for bottlenecks
- Look for failed spans, retries, timeouts, and downstream calls

### 4. Metrics / time series (for performance/capacity bugs)
- Request latency (p50/p95/p99) and request count/traffic
- CPU and memory utilization (pressure → throttling/OOM)
- Instance/replica count (scaling events)
- Error rate over time

### 5. Alerts (check if already flagged)
- Did existing alerts fire around the time of the bug?
- Correlate alert timing with error logs

### 6. Service / deploy state
- Current revision/version, scaling config, environment
- Recent deploys/releases that might correlate with the onset of the bug

## Interpreting Signals

### Correlation Patterns

| Pattern | Likely Cause |
|---------|-------------|
| Errors spike after a deploy/release | Regression in the latest version |
| Errors only for a specific tenant/account | Tenant data issue or missing config |
| Timeout errors with high CPU | Resource exhaustion, needs scaling |
| Intermittent 500s with DB errors | Connection pool exhaustion or migration issue |
| Auth errors (401/403) | Token/JWKS/identity-provider config, role mismatch |
| External-call failures | Upstream/3rd-party quota, timeout, or contract change |

### What to Extract for RCA

- Exact error messages and stack traces
- Affected endpoints/operations
- Time window (first occurrence, frequency)
- Affected scope (all users, one tenant, a specific action)
- Correlation with deploys or config changes
