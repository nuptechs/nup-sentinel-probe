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
| Interceptores MySQL / MongoDB / Redis | ✅ na lib | `node/index.ts:11-15` (`wrapMysqlPool`/`wrapMongoClient`/`wrapRedisClient`) |
| Interceptor de console / log | ✅ na lib | `node/index.ts:16` (`createLogInterceptor`/`wrapConsole`) |

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

## 4. Servidor — ingestão e derivações

| Capacidade | Status | Evidência |
|---|---|---|
| Ingestão de eventos em lote (`POST /api/sessions/:id/events`, ≤1000, cap 256KB/evento) | ✅ | `server/src/routes/events.ts:48-86` |
| Query de eventos com filtros + paginação | ✅ | `server/src/routes/events.ts:88-110` |
| Timeline correlacionada | ✅ | `server/src/routes/events.ts:112-126` |
| Grupos de correlação | ✅ | `server/src/routes/events.ts:215-229` |
| **`observed-fields`** — campos top-level por entidade (p/ FieldDeathDetector do Sentinel) | 🟡 funciona, mas **cego no easynup** | `server/src/routes/events.ts:137-172` + `server/src/services/field-extractor.ts` |
| **`runtime-hits`** — contagem de rotas canônicas `:id` (p/ TripleOrphanDetector) | 🟡 funciona, mas **cego no easynup** | `server/src/routes/events.ts:181-213` + `server/src/services/route-aggregator.ts` |

**Por que `observed-fields`/`runtime-hits` ficam 🟡 (vazios) no easynup:**

- `field-extractor` só conta evento se `ev.source === 'network'` E `type === 'request'|'response'` E houver `body` JSON-objeto no topo (`field-extractor.ts:104-130`). O easynup manda `source:'sdk'`/`'browser'` sem corpo → todos os eventos são descartados em `:105`.
- `route-aggregator` exige `ev.source === 'network'` E `type === 'request'` (`route-aggregator.ts:84-86`). O easynup manda `source:'sdk'`/`'browser'` → idem, 0 contado.

A **lib** está correta e tem cobertura (`extractObservedFields`/`extractRuntimeHits` são funções puras testadas). O furo é de **integração**: emissor errado + corpo não enviado + `probe.enabled=false` default.

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
| Browser Agent (Playwright) | ✅ na lib | `packages/browser-agent/src/` |
| CLI — `capture` / `watch` / `report` / `replay` | ✅ | `packages/cli/src/index.ts:7-10` |
| Dashboard React (overview, sessions, traces, logs, errors) | ✅ | `dashboard/src/` |
| WebSocket em tempo real (subscribe por sessão) | ✅ | `server/src/ws/realtime.ts` |
| Notificação/webhook (retry/DLQ/SSRF/HMAC) | ✅ na lib | `packages/core/src/notification/` (export `core/src/index.ts:19`) |

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
