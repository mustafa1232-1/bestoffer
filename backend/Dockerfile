FROM node:20-bookworm-slim

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev --no-audit --no-fund

COPY src ./src
COPY sql ./sql
COPY sql_supabase ./sql_supabase
RUN mkdir -p uploads && chown -R node:node /app

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=8080
USER node
EXPOSE 8080

CMD ["npm", "start"]
