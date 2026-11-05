"""Prometheus metrics, served on /metrics and scraped by the platform team."""

from prometheus_client import Counter, Histogram

REQUESTS = Counter(
    "http_requests_total",
    "HTTP requests by route template and status.",
    ["method", "route", "status"],
)
APP_EVENTS = Counter("app_events_total", "Product events sent by the app.", ["event"])
ACCESS_LOG_WRITE_FAILURES = Counter(
    "access_log_write_failures_total",
    "Times recording a clinician's access to a diary failed (O.Mon_1).",
)
LATENCY = Histogram(
    "http_request_duration_seconds", "HTTP request duration by route template.", ["method", "route"]
)
