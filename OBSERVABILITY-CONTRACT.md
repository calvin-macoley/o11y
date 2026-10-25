# Observability Contract

The rules every app must follow to plug into the homelab LGTM stack, and the
line between what **developers** own and what the **platform/ops** owns.

> **One sentence:** apps *emit* the three signals in open standards to endpoints
> given by env vars; the platform *collects, stores, visualises and alerts*. An
> app must never contain a Mimir/Loki/Tempo URL or a scrape config.

---

## The boundary

| Concern | Owner | What it means |
|---|---|---|
| **Instrumentation** — emit metrics, logs, traces, health | **Developer** | Code inside the app. Speak Prometheus / JSON-to-stdout / OTLP. Know nothing about backends. |
| **Collection** — scrape, tail, receive | **Platform** | Alloy config: `prometheus.scrape`, `loki.source.*`, `otelcol.receiver.otlp`. |
| **Storage** — TSDB, log store, trace store | **Platform** | Mimir, Loki, Tempo (object storage on MinIO). |
| **Visualisation & alerting** | **Platform** | Grafana datasources, dashboards, alert rules, retention, multitenancy. |

The two sides meet at **one handshake: environment variables** (see below).

---

## What every app MUST emit (developer contract)

### 1. Metrics — Prometheus text format on `GET /metrics`
- Default process metrics (`collectDefaultMetrics` / equivalent): heap, GC, event-loop lag.
- **RED** per route: `<app>_http_requests_total{method,route,status_code}` and
  `<app>_http_request_duration_seconds` (histogram). **Keep `route` as the
  pattern (`/api/logs/:date`), never the raw URL** — raw URLs explode cardinality.
- A few **business** counters/gauges that matter for *this* app.
- `<app>_build_info{version,commit} 1` for release correlation.
- Metric names are prefixed with the service name (`gym_`, `nutri_`, `hub_`).

### 2. Logs — structured JSON to **stdout** (never files)
- One JSON object per line (pino or equivalent). Include `service` + `version`.
- Levels: `>=500 → error`, `>=400 → warn`, else `info`.
- **Ignore** `/healthz`, `/readyz`, `/metrics` in request logging (noise).
- Do **not** write log files or rotate — the container's stdout is the interface;
  Alloy tails it into Loki.

### 3. Traces — OTLP to `OTEL_EXPORTER_OTLP_ENDPOINT`
- Init the OTEL SDK **before any other import** so auto-instrumentation patches
  http/express/fetch. If the env var is unset, **no-op** (local dev stays quiet).
- Set resource attributes `service.name` (from `OTEL_SERVICE_NAME`) and
  `service.version`.
- Export both traces and OTLP metrics to the same endpoint; add custom spans
  around expensive/external work (Sheets calls, cross-service fan-out).

### 4. Health — liveness & readiness
- `GET /healthz` → `200` when the process is up. **Must not** touch downstreams.
- `GET /readyz` → `200` only when the app can serve real traffic (DB reachable,
  auth verified). Readiness failure pulls the pod out of rotation.

---

## The handshake (env-var interface)

Set by the platform (ConfigMap), read by the app. **These are the only knobs
the platform uses to steer telemetry** — no code change required per environment.

| Variable | Set by | Purpose |
|---|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | platform | OTLP base URL (Alloy). Unset ⇒ tracing off. |
| `OTEL_SERVICE_NAME` | platform | `service.name` in traces/metrics. |
| `LOG_LEVEL` | platform | Log verbosity. |
| `APP_VERSION` / `APP_COMMIT` | CI | Stamp for `*_build_info` + log/trace resource. |

Metrics scraping needs **no** app env var — the platform points Alloy at the
pod's `/metrics` (via k8s annotations or a PodMonitor).

---

## Current compliance

| Signal | gym-tracker | hub | nutri |
|---|---|---|---|
| Metrics `/metrics` | ✅ | ✅ | ✅ |
| Structured logs → stdout | ✅ pino | ✅ pino | ✅ pino |
| OTLP traces | ✅ | ✅ | ✅ |
| `/healthz` + `/readyz` | ✅ | ✅ | ✅ |

All three apps are contract-compliant. `nutri` had **no** telemetry and was
brought up to bar; `hub` gained OTLP tracing (its fan-out to the other two shows
as client spans).

---

## Platform state & gaps

Currently provisioned (`o11y/o11y-deployment/group_vars/all.yml`): **Grafana +
Mimir + MinIO + nginx gateway**, with **Alloy** as the collector
(`o11y-collector/`) and node-exporter on hosts (`nodes-observability/`).

So the metrics pipeline is complete: **app `/metrics` → Alloy `prometheus.scrape`
→ `remote_write` → Mimir → Grafana**.

**Two backends are not yet deployed**, so signals the apps already emit have
nowhere to land:

| Gap | Effect | To close (platform work) |
|---|---|---|
| **No Loki** | Structured logs emitted but not aggregated/searchable. | Deploy Loki (bucket on MinIO); add `loki.source.kubernetes` (or file/journal) in Alloy → Loki. |
| **No Tempo** | OTLP traces have no store; Alloy's `otelcol.exporter.otlp "tempo"` points nowhere. | Deploy Tempo (bucket on MinIO); keep Alloy OTLP receiver → Tempo; set `OTEL_EXPORTER_OTLP_ENDPOINT` on the apps to the Alloy Service. |

Until then, traces/logs work locally (point the env var at a local Alloy) but
are not centralised.

---

## Checklist for a new app (before it ships to k3s)

- [ ] `/metrics` exposes default + RED + `*_build_info`; `route` labels are patterns.
- [ ] Logs are single-line JSON on stdout with `service`/`version`; health routes ignored.
- [ ] OTEL initialised first-thing; no-ops without `OTEL_EXPORTER_OTLP_ENDPOINT`.
- [ ] `/healthz` (liveness, no downstreams) and `/readyz` (real readiness) exist.
- [ ] No backend URLs, scrape configs, or log-file paths baked into the app.
- [ ] ConfigMap wires `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_SERVICE_NAME`, `LOG_LEVEL`, `APP_VERSION/COMMIT`.
- [ ] Platform: Alloy scrape/tail added; Grafana dashboard + alert (`up`, error rate, latency, `hub_upstream_up`).
