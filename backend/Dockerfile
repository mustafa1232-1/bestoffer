FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY src ./src
COPY sql ./sql
RUN mkdir -p uploads

ENV NODE_ENV=production
EXPOSE 3000

CMD ["npm", "start"]
