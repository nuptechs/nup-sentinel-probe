# API Reference

> Complete HTTP and WebSocket API specification for `@nuptechs-sentinel-probe/server`.
>
> **Endpoints de derivação não listados abaixo:** o servidor também expõe `GET /api/sessions/:id/observed-fields` (`server/src/routes/events.ts:137`) e `GET /api/sessions/:id/runtime-hits` (`:181`), que agregam campos e rotas a partir dos eventos. **Eles só produzem dado se a sessão tiver eventos `source:'network'` com `type:'request'/'response'` e `body` no topo** — qualquer outro emissor (incl. o SDK `source:'sdk'` e a integração atual do easynup) os deixa vazios. Detalhes e estado real em **[CAPABILITIES.md](CAPABILITIES.md)**.

**Base URL:** `http://localhost:7070`

## Authentication

All endpoints except `/health`, `/ready`, and `/metrics` require authentication.

### API Key

Pass via header:
```
Authorization: Bearer <api-key>
```

API keys must be ≥16 characters. Configure via `PROBE_API_KEYS` env var (comma-separated for multiple keys).

### JWT

Pass via header:
```
Authorization: Bearer <jwt-token>
```

JWT tokens are verified against `PROBE_JWT_SECRET` (≥32 chars). Expected claims: `sub`, `iat`, `exp`.

### Disable Auth (Development Only)

Set `PROBE_AUTH_DISABLED=1`. This is **forbidden** when `NODE_ENV=production`.

---

## Health & Observability

### GET /health

Liveness probe. Returns server status, storage connectivity, pool stats, and uptime.

**Auth:** None

**Response 200:**
```json
{
  "status": "ok",
  "storage": "connected",
  "uptime": 1234.5,
  "sessions": 3,
  "connections": 2,
  "poolStats": {
    "totalCount": 10,
    "idleCount": 8,
    "waitingCount": 0,
    "maxConnections": 20
  }
}
```

### GET /ready

Readiness probe. Tests actual storage connectivity.

**Auth:** None

**Response 200:**
```json
{ "status": "ready" }
```

**Response 503:**
```json
{ "status": "not ready", "error": "Storage unreachable" }
```

### GET /metrics

Prometheus exposition format. Returns all registered metrics.

**Auth:** None

**Response 200:**
```
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET",path="/api/sessions",status="200"} 42
...
```

---

## Sessions

### POST /api/sessions

Create a new debug session.

**Request Body** (optional):
```json
{
  "name": "my-debug-session",
  "config": { "browser": { "enabled": true } },
  "tags": ["frontend", "auth-flow"]
}
```

| Field | Type | Constraints |
|-------|------|-------------|
| `name` | string | Max 256 chars, alphanumeric + `\s\-.:()[]` |
| `config` | object | Arbitrary key-value pairs |
| `tags` | string[] | Max 20 tags, each max 64 chars |

**Response 201:**
```json
{
  "id": "sess-a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "name": "my-debug-session",
  "status": "idle",
  "config": { "browser": { "enabled": true } },
  "tags": ["frontend", "auth-flow"],
  "createdAt": "2026-03-31T12:00:00.000Z",
  "eventCount": 0
}
```

### GET /api/sessions

List sessions with pagination and optional filtering.

**Query Parameters:**

| Param | Type | Default | Constraints |
|-------|------|---------|-------------|
| `limit` | number | 50 | 1–200 |
| `offset` | number | 0 | ≥ 0 |
| `status` | string | — | Filter by status |
| `search` | string | — | Search in name (max 256 chars) |

**Response 200:**
```json
{
  "sessions": [ { "id": "...", "name": "...", "status": "idle", ... } ],
  "total": 42,
  "limit": 50,
  "offset": 0
}
```

### GET /api/sessions/:id

Get full session details.

**Response 200:** Session object (same shape as POST response).

**Response 404:**
```json
{ "error": "Session not found" }
```

### DELETE /api/sessions/:id

Delete a session and all its events.

**Response 204:** No content.

**Response 404:**
```json
{ "error": "Session not found" }
```

### PATCH /api/sessions/:id/status

Update session status.

**Request Body:**
```json
{ "status": "capturing" }
```

| Status | Description |
|--------|-------------|
| `idle` | Created but not yet capturing |
| `capturing` | Actively collecting events |
| `paused` | Temporarily stopped |
| `completed` | Session finished |
| `error` | Session encountered an error |

**Response 200:** Updated session object.

**Response 400:** Invalid status value.

---

## Events

### POST /api/sessions/:id/events

Ingest events in batch. Accepts up to **1,000 events** per request.

**Request Body** — array or wrapped object:
```json
{
  "events": [
    {
      "id": "evt-001",
      "sessionId": "sess-...",
      "timestamp": 1711872000000,
      "source": "browser",
      "type": "click",
      "data": { "selector": "#submit-btn", "text": "Submit" }
    },
    {
      "id": "evt-002",
      "sessionId": "sess-...",
      "timestamp": 1711872000100,
      "source": "network",
      "type": "request",
      "data": { "method": "POST", "url": "/api/orders" }
    }
  ]
}
```

**Required Event Fields:**

| Field | Type | Constraints |
|-------|------|-------------|
| `id` | string | 1–128 chars |
| `sessionId` | string | 1–128 chars |
| `timestamp` | number | Finite number (epoch ms) |
| `source` | enum | `browser`, `network`, `log`, `sdk`, `correlation` |

Additional fields are passed through as-is.

**Limits:**
- Max batch size: 1,000 events
- Max single event: 256 KB JSON
- Max payload: `Content-Length` validated before parsing

**Response 200:**
```json
{ "ingested": 2 }
```

**Response 400:** Validation errors.

**Response 404:** Session not found.

**Response 413:** Payload too large.

### GET /api/sessions/:id/events

Query events with filtering and pagination.

**Query Parameters:**

| Param | Type | Default | Constraints |
|-------|------|---------|-------------|
| `source` | enum | — | `browser`, `network`, `log`, `sdk`, `correlation` |
| `type` | string | — | Event type (max 64 chars) |
| `fromTime` | number | — | Epoch ms lower bound |
| `toTime` | number | — | Epoch ms upper bound |
| `limit` | number | 500 | 1–10,000 |
| `offset` | number | 0 | ≥ 0 |

**Response 200:**
```json
{
  "events": [ { "id": "...", "source": "browser", "timestamp": 1711872000000, ... } ],
  "total": 150
}
```

---

## Timeline & Reports

### GET /api/sessions/:id/timeline

Get the correlated event timeline for a session.

**Response 200:**
```json
{
  "sessionId": "sess-...",
  "groups": [
    {
      "id": "grp-001",
      "strategy": "request-id",
      "events": [ { ... }, { ... } ],
      "startTime": 1711872000000,
      "endTime": 1711872000500,
      "duration": 500
    }
  ],
  "ungroupedEvents": [ { ... } ]
}
```

### GET /api/sessions/:id/report

Generate a report in the specified format.

**Query Parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `format` | enum | `html` | `html`, `json`, `markdown` |
| `includeScreenshots` | boolean | `true` | Include base64 screenshots |
| `includeRequestBodies` | boolean | `false` | Include HTTP request/response bodies |
| `maxEventsPerGroup` | number | 500 | Max events per correlation group (cap: 1000) |

**Response 200:**
- `format=html` → `Content-Type: text/html`
- `format=json` → `Content-Type: application/json`
- `format=markdown` → `Content-Type: text/markdown`

---

## WebSocket Protocol

**URL:** `ws://localhost:7070`

### Connection Authentication

Option A — API key in query string:
```
ws://localhost:7070?apiKey=your-api-key
```

Option B — JWT in Sec-WebSocket-Protocol:
```
Sec-WebSocket-Protocol: probe-v1, <jwt-token>
```

### Client → Server Messages

**Subscribe to session events:**
```json
{ "type": "subscribe", "sessionId": "sess-..." }
```

**Unsubscribe:**
```json
{ "type": "unsubscribe", "sessionId": "sess-..." }
```

### Server → Client Messages

**Event notification:**
```json
{
  "type": "event",
  "sessionId": "sess-...",
  "event": {
    "id": "evt-001",
    "source": "browser",
    "timestamp": 1711872000000,
    "type": "click",
    "data": { ... }
  }
}
```

**Correlation group update:**
```json
{
  "type": "group",
  "sessionId": "sess-...",
  "group": {
    "id": "grp-001",
    "strategy": "temporal",
    "events": [ ... ]
  }
}
```

### Limits

| Limit | Value |
|-------|-------|
| Max message size (client → server) | 4 KB |
| Rate limit | 20 messages/second per connection |
| Max subscriptions per client | 50 |
| Max connections per IP | 50 |
| Ping interval | 30 seconds |

### Error Handling

The server closes the connection with a WebSocket close code on errors:

| Code | Reason |
|------|--------|
| 1008 | Policy violation (auth failed, rate limit exceeded) |
| 1009 | Message too large |
| 1011 | Internal server error |

---

## Rate Limiting

| Category | Limit | Scope |
|----------|-------|-------|
| Reads (GET) | 200 req/s | Per IP |
| Writes (POST/PATCH/DELETE) | 50 req/s | Per IP |
| WebSocket messages | 20 msg/s | Per connection |

**Response 429:**
```json
{ "error": "Too many requests" }
```

Includes `Retry-After` header.

---

## Error Responses

All errors follow a consistent format:

```json
{
  "error": "Human-readable error message",
  "details": [ ... ]  // Optional — Zod validation issues
}
```

| Status | Meaning |
|--------|---------|
| 400 | Validation error (bad input, invalid format) |
| 401 | Authentication required or failed |
| 404 | Resource not found |
| 413 | Payload too large |
| 429 | Rate limit exceeded |
| 500 | Internal server error |
