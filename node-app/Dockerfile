FROM node:20-slim AS deps
WORKDIR /build
 
COPY package.json package-lock.json ./
 
RUN npm ci
 
FROM node:20-slim AS prod-deps
WORKDIR /build
COPY package.json package-lock.json ./
 
RUN npm ci --omit=dev
 
FROM node:20-slim AS final
 

RUN mkdir -p /app && chown -R node:node /app
WORKDIR /app
 
COPY --from=prod-deps --chown=node:node /build/node_modules ./node_modules
 
COPY --chown=node:node src/ ./src/
COPY --chown=node:node package.json ./
 
USER node
 
EXPOSE 3000
 
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', r => process.exit(r.statusCode === 200 ? 0 : 1))"
 

CMD ["node", "src/index.js"]


