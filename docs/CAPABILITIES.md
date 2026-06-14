# Catálogo de Capacidades — NuP Sentinel Probe

> **Documento de estado real, sem maquiagem.** Cada item traz status honesto e evidência `arquivo:linha`.
> Quando README/ARCHITECTURE/API.md prometerem algo, este arquivo é a fonte de verdade sobre o que de fato funciona.

Legenda de status:

- ✅ **funciona** — implementado e ligado ponta-a-ponta; produz dado útil.
- 🟡 **construído mas não ligado / sem dados** — o código existe e é testado, mas no caminho real (ex.: integração com o easynup) ele não recebe os eventos certos ou está desligado por padrão.
- ⚪ **stub / planejado** — esqueleto, placeholder ou só interface.

---

## TL;DR — a verdade desconfortável sobre extração de campos

O Probe **sabe** capturar corpo de requisição/resposta e SQL (✅ nas libs). O **problema** é o que chega no servidor a partir do easynup hoje:

1. A extração de campos (`observed-fields`) e a contagem de rotas (`runtime-hits`) **só consideram eventos `source: 'network'` com `type: 'request'/'response'` e um campo `body` no topo** — `server/src/services/field-extractor.ts:104-118` e `server/src/services/route-aggregator.ts:83-92`.
2. O **único emissor que produz esse formato** é o `MiddlewareAdapter` do pacote `network-interceptor` (`packages/network-interceptor/src/adapters/middleware.adapter.ts:152-167` e `:215-228`) — emite `source:'network'`, `type:'request'/'response'`, `body` no topo.
3. **Mas o easynup não usa esse emissor.** A instrumentação do easynup manda outra coisa:
   - **Backend Java** (`ProbeEventEmitter.emitIfEnabled`) envia `source: "sdk"`, `type: "http-request"` e **só método + URL + userAgent dentro de `data`** — sem corpo (`easynup/src/main/java/easynup/config/ProbeEventEmitter.java:121-141`).
   - **Frontend Vue** (`useObservability`) e o relay do gateway (`probe-events.js`) emitem `source: "browser"`, só erros/`browser-error` — também sem corpo de API (`easynup/frontend/src/composables/useObservability.ts:64-72`, `easynup/services/gateway/src/routes/probe-events.js:64-78`).
   - Além disso, `probe.enabled=false` é o **default** (`easynup/src/main/resources/application.properties:44`).

**Resultado:** mesmo com tráfego real no easynup, o `field-extractor` recebe **0 evento elegível** → `observed-fields` e `runtime-hits` voltam **vazios**. A extração de campos fica **cega** não por bug do Probe, mas porque o corpo nunca é enviado e o `source` está errado.

> Há um emissor "correto" pronto e testado (o `MiddlewareAdapter`) que produziria exatamente o formato esperado — ele simplesmente não está plugado no easynup, que usa o caminho debug-probe (Java→`source:'sdk'`, browser→`source:'browser'`).

---

## 1. SDK — instrumentação Node

| Capacidade | Status | Evidência |
|---|---|---|
| Middleware Express (rota, status, duração, correlation-id) | ✅ na lib | `packages/sdk/src/node/express-middleware.ts:73-148` |
| Propagação de correlation-id (request/response header) | ✅ | `express-middleware.ts:80-106` |
| Contexto via AsyncLocalStorage (request/correlation id) | ✅ | `packages/sdk/src/node/context.ts` (export em `node/index.ts:18`) |
| Interceptor de SQL Postgres (`pg.Pool.query`) — query, params, duração, rowCount, erro | ✅ na lib | `packages/sdk/src/node/db-interceptor.ts:36-78` |
| Redação de params sensíveis (JWT, cartão, SSN + regex custom anti-ReDoS) | ✅ | `db-interceptor.ts:155-196` |
| Interceptores MySQL / MongoDB / Redis | ✅ na lib | `node/index.ts:9-15` (`wrapMysqlPool`/`wrapMongoClient`/`wrapRedisClient`) |
| Interceptor de console / log | ✅ na lib | `node/index.ts:16` (`createLogInterceptor`/`wrapConsole`) |
| `RequestTracer` (rastreio de requisição) | ✅ na lib | `node/index.ts:7` |
| Transporte: `batch-sender` (envio em lote) + `circuit-breaker` (proteção do endpoint de ingestão) | ✅ na lib | `packages/sdk/src/shared/batch-sender.ts`, `circuit-breaker.ts` |

**Caveat decisivo do SDK Node:** o `SdkEventCollector` **carimba todo evento como `source: 'sdk'`** (`packages/sdk/src/node/event-collector.ts:25-32`) e o middleware emite `type: 'request-start'/'request-end'` **sem corpo** (`express-middleware.ts:119-141`). Ou seja, **mesmo o middleware do SDK não alimenta o `field-extractor`** (que exige `source:'network'` + `type:'request'/'response'` + `body`). O SDK serve para timeline/correlação, **não** para extração de campos.

---

## 2. SDK — instrumentação Browser

| Capacidade | Status | Evidência |
|---|---|---|
| Interceptor de `fetch` (URL, método, status, duração, erro) + injeta correlation-id | ✅ na lib | `packages/sdk/src/browser/fetch-interceptor.ts:25-106` |
| Interceptor de XHR | ✅ na lib | `packages/sdk/src/browser/xhr-interceptor.ts` (export em `browser/index.ts:6`) |
| Interceptor de console | ✅ na lib | `browser/console-interceptor.ts` (export `browser/index.ts:7`) |
| Error boundary (erros não tratados + rejeições) | ✅ na lib | `browser/error-boundary.ts` (export `browser/index.ts:8`) |

**Caveat:** o fetch-interceptor emite `source: 'sdk'` e `type: 'request-start'/'request-end'` **sem corpo** (`fetch-interceptor.ts:52-59`, `:76-82`). Também não alimenta o `field-extractor`.

---

## 3. Network Interceptor — o emissor "correto" (e não usado pelo easynup)

| Capacidade | Status | Evidência |
|---|---|---|
| `MiddlewareAdapter` Express — emite `source:'network'`, `type:'request'/'response'` com **corpo no topo** | ✅ na lib | `packages/network-interceptor/src/adapters/middleware.adapter.ts:152-167`, `:215-228` |
| Captura de corpo de request/response (com cap, truncamento e redação) | ✅ na lib | `middleware.adapter.ts:126-167`, `:169-231` |
| `ProxyAdapter` HTTP (captura via proxy) com guardas SSRF / DNS-rebinding | ✅ na lib | `packages/network-interceptor/src/adapters/proxy.adapter.ts` + testes `__tests__/adapters/proxy-ssrf.test.ts`, `proxy-dns-rebinding.test.ts` |
| Filtro de tráfego (extensões/URLs excluídas) | ✅ | `packages/network-interceptor/src/filters/traffic-filter.ts` |
| **Ligado no easynup** | 🟡 **NÃO** | `grep` no `services/gateway/src` não acha `MiddlewareAdapter`/`createNetworkCapture`; o easynup usa o relay `probe-events.js` (browser) e o `ProbeEventEmitter` Java (sdk) |

> **Este é o pacote que tornaria `observed-fields`/`runtime-hits` úteis.** Está pronto e testado, mas o easynup não o monta. É a peça que falta plugar.

---

## 4. Servidor — rotas REST (sessões, eventos, derivações, relatório, métricas)

### 4.1 Sessões — CRUD

| Capacidade | Status | Evidência |
|---|---|---|
| Criar sessão (`POST /api/sessions`) — nome/config/tags + folding de `projectId`/`externalSessionId`/`metadata` em tags `sentinel:`/`ext:`/`meta:` (gancho Sentinel) | ✅ | `server/src/routes/sessions.ts:48-77` |
| Listar sessões paginadas + filtro status/search (`GET /api/sessions`) | ✅ | `server/src/routes/sessions.ts:79-91` |
| Detalhe da sessão (`GET /api/sessions/:id`) | ✅ | `server/src/routes/sessions.ts:93-106` |
| Deletar sessão (`DELETE /api/sessions/:id`) — com log de auditoria | ✅ | `server/src/routes/sessions.ts:108-123` |
| Atualizar status (`PATCH /api/sessions/:id/status`) — idle/capturing/paused/completed/error | ✅ | `server/src/routes/sessions.ts:125-150` |
| Validação anti-path-traversal do `sessionId` (`/^[\w-]+$/`, ≤128) | ✅ | `server/src/routes/sessions.ts:19` |

### 4.2 Eventos e derivações

| Capacidade | Status | Evidência |
|---|---|---|
| Ingestão de eventos em lote (`POST /api/sessions/:id/events`, ≤1000, cap 256KB/evento, early-reject por Content-Length) | ✅ | `server/src/routes/events.ts:48-86` |
| Query de eventos com filtros + paginação | ✅ | `server/src/routes/events.ts:88-110` |
| Timeline correlacionada (`GET /api/sessions/:id/timeline`) | ✅ | `server/src/routes/events.ts:112-126` |
| Grupos de correlação (`GET /api/sessions/:id/groups`) | ✅ | `server/src/routes/events.ts:215-229` |
| **`observed-fields`** (`GET /api/sessions/:id/observed-fields`) — campos top-level por entidade (p/ FieldDeathDetector do Sentinel); janela opcional `fromTime`/`toTime`, cap 50k eventos | 🟡 funciona, mas **cego no easynup** | `server/src/routes/events.ts:137-172` + `server/src/services/field-extractor.ts:104-106` |
| **`runtime-hits`** (`GET /api/sessions/:id/runtime-hits`) — contagem de rotas canônicas `:id` (p/ TripleOrphanDetector); janela opcional, cap 50k | 🟡 funciona, mas **cego no easynup** | `server/src/routes/events.ts:181-213` + `server/src/services/route-aggregator.ts:84-86` |

> Agregação **por sessão** apenas — a agregação cross-sessão é deliberadamente deixada para o orquestrador (Sentinel), para não acoplar o Probe ao modelo de projeto do Sentinel (`events.ts:133-136`, `:178-180`).

### 4.3 Relatório e métricas

| Capacidade | Status | Evidência |
|---|---|---|
| Relatório da sessão (`GET /api/sessions/:id/report?format=html\|json\|markdown`) — opções `includeScreenshots`/`includeRequestBodies`/`maxEventsPerGroup` (cap 1000); usa o pacote `reporter` via import dinâmico | ✅ | `server/src/routes/reports.ts:18-68` |
| Métricas Prometheus (`GET /metrics`) — montado **antes** da auth (scrapers não carregam token) | ✅ | `server/src/routes/metrics.ts:11-19` + `server/src/index.ts:107` |
| Health check (`GET /health`) — status storage + snapshot de métricas (sessões/ws/correlators/erro%) + pool stats; 503 se storage degradado | ✅ | `server/src/index.ts:110-138` |
| Readiness (`GET /ready`) — 503 se storage indisponível | ✅ | `server/src/index.ts:139-146` |

**Por que `observed-fields`/`runtime-hits` ficam 🟡 (vazios) no easynup:**

- `field-extractor` só conta evento se `ev.source === 'network'` E `type === 'request'|'response'` E houver `body` JSON-objeto no topo (`field-extractor.ts:104-130`). O easynup manda `source:'sdk'`/`'browser'` sem corpo → todos os eventos são descartados em `:105`.
- `route-aggregator` exige `ev.source === 'network'` E `type === 'request'` (`route-aggregator.ts:84-86`). O easynup manda `source:'sdk'`/`'browser'` → idem, 0 contado.

A **lib** está correta e tem cobertura (`extractObservedFields`/`extractRuntimeHits` são funções puras testadas). O furo é de **integração**: emissor errado + corpo não enviado + `probe.enabled=false` default.

---

## 4-bis. Servidor — segurança, hardening e operação

| Capacidade | Status | Evidência |
|---|---|---|
| Autenticação por API key (compare em tempo constante) **ou** JWT HS256 (verify constant-time); modo `enableAuth` | ✅ | `server/src/middleware/auth.ts:44-50`, `:109-124` + `server/src/index.ts:188-212` |
| Guardas de boot fail-fast — `PROBE_AUTH_DISABLED=1` proibido em produção; produção exige key ou JWT; key ≥16 chars; JWT secret ≥32 chars | ✅ | `server/src/index.ts:193-209` |
| Rate limiting token-bucket com 2 tiers (leitura 200/s burst 500 · escrita 50/s burst 100) | ✅ | `server/src/middleware/rate-limiter.ts:30-35` + `server/src/index.ts:178-186` |
| CORS restrito a `CORS_ORIGINS` (rejeita cross-origin em produção sem origens configuradas) | ✅ | `server/src/index.ts:166-173` |
| Helmet + CSP estrita (`defaultSrc 'self'`, `objectSrc 'none'`, `frameAncestors 'none'`) | ✅ | `server/src/index.ts:149-164` |
| Limite de corpo JSON (10 MB, `strict`) | ✅ | `server/src/index.ts:174` |
| Request logger (pino) + log de auditoria em create/delete/status de sessão | ✅ | `server/src/middleware/request-logger.ts` + `server/src/routes/sessions.ts:75,121,148` |
| Error handler central + `notFoundHandler` para `/api/*` | ✅ | `server/src/middleware/error-handler.ts` + `server/src/index.ts:236-237` |
| `asyncHandler` (captura rejeições de handlers async) | ✅ | `server/src/middleware/async-handler.ts` |
| Validação de env via Zod no boot (porta, storage, secrets, webhook) | ✅ | `server/src/index.ts:39-57` |
| Graceful shutdown (drena WS + storage, timeout 30s) + safety nets `unhandledRejection`/`uncaughtException` | ✅ | `server/src/index.ts:257-328` |
| SPA fallback — serve dashboard estático em produção quando `dashboard/dist` existe | ✅ | `server/src/index.ts:223-233` |

## 4-ter. Servidor — storage, métricas internas e recuperação de webhook

| Capacidade | Status | Evidência |
|---|---|---|
| Storage plugável via factory — `memory` / `file` / `postgres` (Postgres se `DATABASE_URL`) | ✅ na lib | `packages/core/src/storage/index.ts:16-30` + `server/src/index.ts:60-78` |
| Circuit breaker de Postgres + detecção de erro transitório | ✅ na lib | `packages/core/src/storage/index.ts:7` (`StorageCircuitBreaker`/`isTransientError`) |
| Storage instrumentado (duração/contagem/erros por operação) | ✅ | `server/src/lib/instrumented-storage.ts` + `server/src/index.ts:73` |
| Coleta de pool stats do Postgres (gauges de conexões/waiting/circuit-breaker) | ✅ | `server/src/index.ts:75-77` + `server/src/lib/metrics.ts:153-177` |
| ~30 métricas Prometheus (HTTP, sessões, eventos, correlator, storage, pool PG, WebSocket) | ✅ | `server/src/lib/metrics.ts:21-217` |
| Persistência de entregas de webhook em Postgres (`PostgresWebhookEventStore`) quando há DB + webhook configurado | ✅ | `server/src/index.ts:84-93` |
| **Recuperação de webhooks pendentes/falhos no boot** (resume escalonado pós-restart) | ✅ | `server/src/index.ts:247-255`, `:296-317` |
| Fábrica de notificação (`buildNotificationPort`) com store opcional | ✅ | `server/src/lib/notification-factory.ts` + `server/src/index.ts:95-102` |

---

## 5. Correlation Engine

| Capacidade | Status | Evidência |
|---|---|---|
| Estratégia request-id | ✅ | `packages/correlation-engine/src/strategies/request-id.strategy.ts` |
| Estratégia temporal (janela após gatilho) | ✅ | `packages/correlation-engine/src/strategies/temporal.strategy.ts` |
| Estratégia url-matching | ✅ | `packages/correlation-engine/src/strategies/url-matching.strategy.ts` |
| Builder de timeline / summary | ✅ | `packages/correlation-engine/src/summary-builder.ts` + testes |

---

## 6. Demais pacotes

| Capacidade | Status | Evidência |
|---|---|---|
| Log Collector — adapters file / docker / stdout + parser | ✅ na lib | `packages/log-collector/src/adapters/`, `src/parser/log-parser.ts` |
| Reporter — HTML / JSON / Markdown | ✅ na lib | `packages/reporter/src/adapters/` |
| Browser Agent (Playwright) + blocklist de `evaluate` | ✅ na lib | `packages/browser-agent/src/adapters/playwright.adapter.ts` + teste `evaluate-blocklist.test.ts` |
| CLI — `capture` / `watch` / `report` / `replay` (commander + `.proberc.json`) | ✅ | `packages/cli/src/index.ts:21-24` + `packages/cli/src/commands/` |
| Dashboard React (overview, sessions, session-detail, traces, logs, errors, settings) | ✅ | `dashboard/src/pages/` |
| WebSocket em tempo real (subscribe por sessão, auth, cap de assinaturas) | ✅ | `server/src/ws/realtime.ts` + testes `subscription-cap.test.ts` |

### 6.1 Notificação / webhook (pacote `core`)

| Capacidade | Status | Evidência |
|---|---|---|
| `WebhookNotificationAdapter` — entrega com retry (schedule fixo) + máx. tentativas + timeout | ✅ na lib | `packages/core/src/notification/webhook.adapter.ts` (`WEBHOOK_MAX_RETRIES`/`WEBHOOK_RETRY_SCHEDULE_MS`/`WEBHOOK_TIMEOUT_MS`) |
| Assinatura HMAC do payload + cálculo de delay de retry | ✅ na lib | `packages/core/src/notification/webhook-signing.ts` (`signPayload`/`computeRetryDelay`) |
| Guarda SSRF (bloqueia URL interna / IPv4 privado) | ✅ na lib | `packages/core/src/notification/ssrf-guard.ts` (`isInternalUrl`/`isPrivateIPv4`) |
| Store de eventos (DLQ / pendentes) — in-memory **ou** Postgres (sobrevive a restart) | ✅ na lib | `webhook-event-store.ts` (`InMemoryWebhookEventStore`) + `postgres-webhook-event-store.ts` |
| `NoopNotificationAdapter` (quando webhook não configurado) | ✅ na lib | `packages/core/src/notification/notification.port.ts` |

### 6.2 Núcleo compartilhado (pacote `core`)

| Capacidade | Status | Evidência |
|---|---|---|
| `EventBus` (pub/sub interno com caps) | ✅ na lib | `packages/core/src/events/event-bus.ts` |
| Redação de dados sensíveis (`isSensitiveKey`/`redactHeaders`/`redactBody`/`maskValue`) — usada pelos interceptores | ✅ na lib | `packages/core/src/utils/redact.ts` |
| Trace context W3C (`parseTraceparent`/`formatTraceparent`/`createTraceContext`/child spans) | ✅ na lib | `packages/core/src/utils/trace-context.ts` |
| `RingBuffer` (buffer circular com limite) | ✅ na lib | `packages/core/src/utils/ring-buffer.ts` |
| Geradores de id (session/correlation/request/span/trace) + timestamps | ✅ na lib | `packages/core/src/utils/id-generator.ts`, `timestamp.ts` |
| Ports hexagonais (storage/correlator/log-source/network-capture/reporter/browser-agent) | ✅ na lib | `packages/core/src/ports/` |

---

## 7. Integração easynup — estado real

| Item | Status | Evidência |
|---|---|---|
| Filtro Java de contexto (`ProbeContextFilter`) presente | 🟡 presente, mas desligado por default | `easynup/src/main/java/easynup/config/ProbeContextFilter.java:43` |
| Emissor Java (`ProbeEventEmitter`) presente | 🟡 manda só método+URL, `source:'sdk'`, **sem corpo** | `easynup/.../ProbeEventEmitter.java:121-141` |
| `probe.enabled` default | 🟡 **false** | `easynup/src/main/resources/application.properties:44` (true só em `application-docker.properties:64`) |
| Frontend `useObservability` | 🟡 só `source:'browser'` + `browser-error`, sem corpo de API | `easynup/frontend/src/composables/useObservability.ts:64-72` |
| Relay do gateway `POST /api/probe/events` | 🟡 força `source:'browser'`, repassa só `type`+`data` | `easynup/services/gateway/src/routes/probe-events.js:64-78` |
| `network-interceptor` (`MiddlewareAdapter`) montado no easynup | 🟡 **não montado** | `grep` vazio em `services/gateway/src` |

**Conclusão de integração:** para `observed-fields`/`runtime-hits` saírem do 🟡 (vazio) para ✅ no easynup, é preciso (a) montar o `MiddlewareAdapter` do `network-interceptor` no gateway/backend para emitir `source:'network'` + `type:'request'/'response'` + `body`, **ou** (b) reescrever o `ProbeEventEmitter`/relay para emitir esse mesmo formato; e (c) ligar `probe.enabled=true` no ambiente alvo. Enquanto isso não acontece, a extração de campos permanece cega.
