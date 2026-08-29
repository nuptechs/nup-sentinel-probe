# ============================================================
# Debug Probe — Multi-stage Production Build
# ============================================================

# Stage 1: Install and build
FROM node:26-alpine AS builder

WORKDIR /app
COPY package.json package-lock.json turbo.json tsconfig.base.json ./

# Copy workspace package.json files first (cache layer)
COPY packages/core/package.json packages/core/
COPY packages/log-collector/package.json packages/log-collector/
COPY packages/network-interceptor/package.json packages/network-interceptor/
COPY packages/correlation-engine/package.json packages/correlation-engine/
COPY packages/browser-agent/package.json packages/browser-agent/
COPY packages/reporter/package.json packages/reporter/
COPY packages/sdk/package.json packages/sdk/
COPY packages/cli/package.json packages/cli/
COPY server/package.json server/
COPY dashboard/package.json dashboard/

RUN npm ci --ignore-scripts

# Copy all source files and build
COPY packages/ packages/
COPY server/ server/
COPY dashboard/ dashboard/

RUN npx turbo run build

# Stage 2: Production image
FROM node:26-alpine AS production

WORKDIR /app

# Non-root user for security
RUN addgroup -g 1001 probe && \
    adduser -u 1001 -G probe -s /bin/sh -D probe

COPY --from=builder /app/package.json /app/package-lock.json /app/turbo.json /app/tsconfig.base.json ./

# Copy built packages
COPY --from=builder /app/packages/ packages/
COPY --from=builder /app/server/ server/
COPY --from=builder /app/dashboard/dist/ dashboard/dist/

# Install production dependencies only
RUN npm ci --omit=dev --ignore-scripts && \
    npm cache clean --force

USER probe

ENV NODE_ENV=production
ENV PORT=7070

EXPOSE 7070

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:7070/health || exit 1

CMD ["node", "server/dist/index.js"]
