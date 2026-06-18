# Stage 1: Base image with pnpm
FROM node:22-alpine AS base
RUN corepack enable && corepack prepare pnpm@9.15.4 --activate

# Stage 2: Install dependencies
# Copy only package manifests first for better layer caching
FROM base AS deps
WORKDIR /app
COPY .npmrc package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY packages/core/package.json ./packages/core/
COPY packages/protobufs/package.json ./packages/protobufs/
COPY packages/transport-deno/package.json ./packages/transport-deno/
COPY packages/transport-http/package.json ./packages/transport-http/
COPY packages/transport-node/package.json ./packages/transport-node/
COPY packages/transport-node-serial/package.json ./packages/transport-node-serial/
COPY packages/transport-web-bluetooth/package.json ./packages/transport-web-bluetooth/
COPY packages/transport-web-serial/package.json ./packages/transport-web-serial/
COPY packages/ui/package.json ./packages/ui/
COPY packages/web/package.json packages/web/.npmrc ./packages/web/
RUN pnpm install --frozen-lockfile

# Stage 3: Generate protobufs using the official buf CLI image
FROM bufbuild/buf AS proto-gen
WORKDIR /app
COPY packages/protobufs/ ./packages/protobufs/
RUN cd packages/protobufs && buf generate

# Stage 4: Build the web app
FROM deps AS builder
ARG VITE_COMMIT_HASH=DEV
ARG VITE_VERSION=v0.0.0
ENV VITE_COMMIT_HASH=$VITE_COMMIT_HASH
ENV VITE_VERSION=$VITE_VERSION
WORKDIR /app
COPY . .
# Overwrite with freshly generated protobufs from the proto-gen stage
COPY --from=proto-gen /app/packages/protobufs/packages/ts/dist/ ./packages/protobufs/packages/ts/dist/
# Pre-create dist so vite-plugin-pwa's closeBundle hook can write sw.js
# before Vite flushes its own output to disk
RUN mkdir -p packages/web/dist && pnpm --filter meshtastic-web run build

# Stage 5: Serve with nginx
FROM nginx:1.29.1-alpine-slim AS runner
COPY --from=builder /app/packages/web/dist /usr/share/nginx/html
COPY packages/web/infra/default.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
