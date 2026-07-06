# NuP Sentinel Probe

> # ⚠️ APOSENTADO / DEPRECATED — não use em novos projetos
>
> Este backend de telemetria **caseiro** foi **aposentado**. A plataforma
> migrou para **OpenTelemetry** padrão, atrás de porta hexagonal:
>
> - **Produção de telemetria (easynup):** porta `ObservabilityPort` +
>   adapter OTel + auto-instrumentação OTel (`--import`). Os emissores do
>   Probe foram removidos (commit `296d65beb`).
> - **Consumo (nup-sentinel):** o `trace-oracle` lê traços via **Jaeger/OTel**;
>   o adapter legado `DebugProbeTraceAdapter` foi removido (PR #217).
>
> **Decisão:** [easynup `ADR-073` r2](https://github.com/nuptechs/EasyNuP) —
> "don't build your own observability backend" — e
> [nup-sentinel `ADR-0014` D3](https://github.com/nuptechs/nup-sentinel/blob/main/docs/adr/0014-organismo-operado-apice-code-intel-observabilidade.md).
>
> O código aqui fica só como **referência histórica** (repositório arquivado).
> As peças únicas — captura de sessão rrweb, correlation engine — já vivem no
> caminho vivo do Sentinel + no substrato OTel.

---

[![CI](https://github.com/nuptechs/nup-sentinel-probe/actions/workflows/ci.yml/badge.svg)](https://github.com/nuptechs/nup-sentinel-probe/actions/workflows/ci.yml)
[![Node.js](https://img.shields.io/badge/node-%3E%3D20-brightgreen)](https://nodejs.org)
[![TypeScript](https://img.shields.io/badge/typescript-5.7%2B-blue)](https://www.typescriptlang.org)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow)](LICENSE)

> Universal runtime debug capture, correlation, and analysis for any application stack.

**Probe** instruments your application at every layer — browser, network, server, database — and correlates events into a unified timeline. When a bug happens, you get a complete picture: what the user clicked, what HTTP requests fired, what the server logged, what DB queries ran, and how they all connect.

> **Estado real das capacidades:** este README descreve o que as bibliotecas *podem* fazer. Para o que de fato está ligado ponta-a-ponta (✅), o que existe mas não recebe dados na integração com o easynup (🟡) e o que é stub (⚪) — incluindo a limitação importante de que a extração de campos (`observed-fields`/`runtime-hits`) fica **cega no easynup hoje porque o corpo da requisição não é enviado** — veja **[docs/CAPABILITIES.md](docs/CAPABILITIES.md)**.

## Architecture

> For detailed design decisions, data flow, and security model, see [ARCHITECTURE.md](ARCHITECTURE.md).
> For the complete API specification, see [docs/API.md](docs/API.md).
> For development setup and contribution guidelines, see [CONTRIBUTING.md](CONTRIBUTING.md).

```
┌─────────────────────────────────────────────────────────────────┐
│                          Probe                            │
│                                                                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
│  │ Browser  │  │   Log    │  │ Network  │  │   SDK    │       │
│  │  Agent   │  │Collector │  │Intercept │  │ (Node/  │       │
│  │(Playwrt) │  │(File/    │  │(Proxy/   │  │ Browser)│       │
│  │          │  │ Docker)  │  │ Midware) │  │         │       │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬────┘       │
│       │              │              │              │             │
│       ▼              ▼              ▼              ▼             │
│  ┌─────────────────────────────────────────────────────┐       │
│  │              EventBus (pub/sub)                     │       │
│  └──────────────────────┬──────────────────────────────┘       │
│                         ▼                                       │
│  ┌─────────────────────────────────────────────────────┐       │
│  │        Correlation Engine (3 strategies)            │       │
│  │   request-id  ·  temporal  ·  url-matching          │       │
│  └──────────────────────┬──────────────────────────────┘       │
│                         ▼                                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                     │
│  │  HTML    │  │   JSON   │  │ Markdown │   ← Reporter        │
│  │ Report   │  │  Export  │  │  Report  │                     │
│  └──────────┘  └──────────┘  └──────────┘                     │
└─────────────────────────────────────────────────────────────────┘
```

## Monorepo Structure

| Package | Purpose |
|---------|---------|
| `@nuptechs-sentinel-probe/core` | Types, ports (interfaces), EventBus, utilities |
| `@nuptechs-sentinel-probe/browser-agent` | Playwright-based browser automation & capture |
| `@nuptechs-sentinel-probe/log-collector` | File tail, Docker logs, stdout/stderr adapters |
| `@nuptechs-sentinel-probe/network-interceptor` | HTTP proxy & Express middleware capture |
| `@nuptechs-sentinel-probe/correlation-engine` | Event correlation with 3 strategies + timeline |
| `@nuptechs-sentinel-probe/reporter` | HTML, JSON, Markdown report generation |
| `@nuptechs-sentinel-probe/sdk` | Instrumentation for Node.js (Express) & browsers |
| `@nuptechs-sentinel-probe/cli` | Command-line interface: capture, watch, report, replay |
| `@nuptechs-sentinel-probe/server` | Express + WebSocket API server |
| **dashboard** | React 19 + TanStack Query + Tailwind CSS web UI |

## Features

- **Multi-layer capture** — Browser, network, logs, database, custom events
- **Real-time correlation** — 3 strategies (request-id, temporal, url-matching)
- **Web dashboard** — Live metrics, session management, trace waterfall, log viewer
- **Enterprise security** — API key + JWT auth, rate limiting, input redaction
- **SDK instrumentation** — Express middleware, console capture, DB interceptors (Postgres, MySQL, MongoDB, Redis)
- **Report generation** — HTML, JSON, Markdown export
- **Docker-ready** — Multi-stage build, health checks, non-root user
- **CI/CD** — GitHub Actions with Node 20/22 matrix + Docker verification

## Quick Start

### Prerequisites

- Node.js ≥ 20
- npm ≥ 10

### Install

```bash
git clone <repo-url> nup-probe
cd nup-probe
npm install
npm run build
```

### Capture a Debug Session

```bash
# Full capture: browser + network + logs
npx probe capture http://localhost:3000 \
  --log-file ./logs/app.log \
  --format html \
  --output ./debug-output

# Watch logs in real-time
npx probe watch --log-file ./logs/app.log --level warn

# Generate report from saved session
npx probe report ./debug-output/session.json --format markdown
```

### Instrument Your Node.js Server (SDK)

```typescript
import { createProbeMiddleware } from '@nuptechs-sentinel-probe/sdk/node';

const app = express();

// Add probe middleware — captures requests, responses, timing
app.use(createProbeMiddleware({
  enabled: true,
  captureDbQueries: true,
  captureCache: true,
  captureCustomSpans: true,
  correlationHeader: 'x-probe-correlation-id',
}));
```

### Instrument Your Frontend (Browser SDK)

```typescript
import { installFetchInterceptor } from '@nuptechs-sentinel-probe/sdk/browser';
import { installErrorBoundary } from '@nuptechs-sentinel-probe/sdk/browser';

// Capture all fetch requests + inject correlation headers
const restoreFetch = installFetchInterceptor({
  correlationHeader: 'x-probe-correlation-id',
  onEvent: (event) => sendToProbeServer(event),
});

// Capture uncaught errors and unhandled rejections
const restoreErrors = installErrorBoundary(
  (event) => sendToProbeServer(event)
);

// Later: cleanup
restoreFetch();
restoreErrors();
```

### Start the Server (API + WebSocket)

```bash
cd server
npm start
# Server runs on http://localhost:7070
# WebSocket on ws://localhost:7070
```

**REST API:**
- `POST /api/sessions` — Create session
- `GET /api/sessions` — List sessions
- `POST /api/sessions/:id/events` — Ingest events (batch ≤ 1000)
- `GET /api/sessions/:id/timeline` — Get correlated timeline
- `GET /api/sessions/:id/report?format=html` — Generate report

**WebSocket Protocol:**
```json
{ "type": "subscribe", "sessionId": "sess-..." }
→ { "type": "event", "sessionId": "...", "event": {...} }
→ { "type": "group", "sessionId": "...", "group": {...} }
```

## Configuration

Create a `.proberc.json` in your project root:

```json
{
  "projectName": "my-app",
  "outputDir": ".probe-data",
  "session": {
    "browser": {
      "enabled": true,
      "targetUrl": "http://localhost:3000",
      "screenshotOnAction": true,
      "captureConsole": true,
      "headless": false,
      "viewport": { "width": 1280, "height": 720 }
    },
    "network": {
      "enabled": true,
      "mode": "proxy",
      "captureBody": true,
      "excludeExtensions": [".css", ".js", ".png", ".jpg", ".svg", ".woff2"]
    },
    "logs": [
      {
        "enabled": true,
        "source": { "type": "file", "name": "backend", "path": "./logs/app.log" }
      },
      {
        "enabled": true,
        "source": { "type": "docker", "name": "postgres", "containerId": "abc123" }
      }
    ],
    "correlation": {
      "strategies": ["request-id", "temporal", "url-matching"],
      "temporalWindowMs": 2000,
      "correlationHeader": "x-probe-correlation-id",
      "groupTimeoutMs": 30000
    }
  }
}
```

Environment variable overrides:
- `PROBE_TARGET_URL` — Browser target URL
- `PROBE_PROXY_PORT` — Network proxy port
- `PROBE_OUTPUT_DIR` — Output directory

## Design Principles

### Port/Adapter Pattern

Every external dependency is behind an abstract port class. Adapters implement the ports. This means:

- **Swap Playwright for Puppeteer** → write a new `BrowserAgentPort` adapter
- **Use S3 instead of local files** → write a new `StoragePort` adapter
- **Add a Datadog reporter** → write a new `ReporterPort` adapter
- **Switch from pg to mysql** → write a new `LogSourcePort` adapter for MySQL slow query log

```
Port (abstract class)     →  Adapter (concrete implementation)
─────────────────────────────────────────────────────────────
BrowserAgentPort          →  PlaywrightBrowserAdapter
LogSourcePort             →  FileLogAdapter, DockerLogAdapter, StdoutLogAdapter
NetworkCapturePort        →  ProxyAdapter, MiddlewareAdapter
CorrelatorPort            →  EventCorrelator
StoragePort               →  (FileStorage — planned)
ReporterPort              →  HtmlReporter, JsonReporter, MarkdownReporter
```

### EventBus — Decoupled Communication

Components never talk to each other directly. The EventBus provides:
- Type-based subscriptions (`bus.on('browser:click', handler)`)
- Source-level cascading (`bus.on('browser', handler)` catches all browser events)
- Wildcard subscriptions (`bus.onAny(handler)`)

### Immutable Events

All event types use `readonly` properties. Events are created once and never modified. This ensures:
- Safe concurrent reads
- Reliable timeline reconstruction
- No accidental mutation in correlation

### Correlation Strategies

1. **request-id** — Links events sharing the same correlation ID or request ID
2. **temporal** — Groups events within a time window after a trigger (e.g., click → requests within 2s)
3. **url-matching** — Matches browser navigations to network requests by URL

## Development

```bash
# Build all packages
npm run build

# Watch mode (development)
npm run dev

# Run tests
npm test

# Clean all build artifacts
npm run clean
```

## Dashboard

The web dashboard provides real-time visibility into debug sessions:

- **Overview** — Live KPI cards, throughput chart, source distribution, event stream
- **Sessions** — Create/manage debug sessions with status tracking
- **Session Detail** — Event timeline, source filters, export (JSON/HTML/Markdown)
- **Traces** — Distributed tracing waterfall visualization
- **Logs** — Searchable log viewer with level filters
- **Errors** — Grouped error tracking with stack traces
- **Settings** — Server connection config, SDK quick start

```bash
# Development (with hot reload)
cd dashboard && npm run dev
# → http://localhost:3000 (proxies API to :7070)

# Production (served by probe-server)
npm run build
# Dashboard is served automatically at http://localhost:7070
```

## Docker

```bash
# Production build
docker build -t nup-probe .
docker run -p 7070:7070 -e PROBE_AUTH_DISABLED=1 nup-probe

# Development with docker-compose
docker compose --profile dev up

# Production with docker-compose
docker compose up probe-server
```

## Demo App

An Express.js Todo API instrumented with Probe:

```bash
# Start the probe server first
cd server && npm start

# In another terminal, start the demo
cd examples/express-app && npm run dev

# Generate some events
curl http://localhost:3001/api/todos
curl -X POST http://localhost:3001/api/todos -H 'Content-Type: application/json' -d '{"title":"Buy milk"}'
curl http://localhost:3001/api/todos

# View events in the dashboard at http://localhost:3000
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | TypeScript 5.7+ (strict mode) |
| Runtime | Node.js 20+ |
| Module System | ESM (ES2022) |
| Monorepo | Turborepo |
| Browser Automation | Playwright |
| HTTP Proxy | Node.js native `http` |
| Server | Express 4 + ws 8 |
| CLI | Commander 12 + Chalk 5 + Ora 8 |

## License

MIT

## Documentation

| Document | Description |
|----------|-------------|
| [README.md](README.md) | Quick start, features, configuration |
| [ARCHITECTURE.md](ARCHITECTURE.md) | System design, Port/Adapter pattern, data flow, security model |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development setup, testing, code conventions, CI/CD |
| [docs/API.md](docs/API.md) | Complete REST and WebSocket API reference |
| [docs/CAPABILITIES.md](docs/CAPABILITIES.md) | **Catálogo de capacidades com status honesto (✅/🟡/⚪) + evidência arquivo:linha — fonte de verdade do que está ligado** |
| [CHANGELOG.md](CHANGELOG.md) | Release history and notable changes |
