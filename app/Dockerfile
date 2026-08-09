# Aetherion AirOps multi-role service image
FROM node:20-alpine

WORKDIR /usr/src/app

# Install dependencies first for better layer caching
COPY package.json ./
RUN npm install --omit=dev

# Copy application source
COPY src ./src
COPY web ./web

ENV NODE_ENV=production
ENV PORT=8080
EXPOSE 8080

# Basic container healthcheck hitting the liveness probe
HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/health/live || exit 1

CMD ["node", "src/server.js"]
