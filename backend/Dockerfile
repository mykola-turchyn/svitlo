FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production PORT=8787
# No runtime dependencies: Node runs the TypeScript sources directly (type stripping).
COPY package.json ./
COPY src ./src
USER node
EXPOSE 8787
HEALTHCHECK CMD wget -qO- http://127.0.0.1:8787/health || exit 1
CMD ["node", "src/server.ts"]
