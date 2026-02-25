# BestOffer Production Deployment

## 1) What must be online
- `PostgreSQL` database on a public server/VPS.
- `Backend API` running continuously on server (`0.0.0.0:3000` or behind Nginx).
- Flutter app built with real API URL (`API_BASE_URL`), not `localhost`.

## 2) Recommended quick setup (Docker on VPS)

### Copy backend to server
```bash
scp -r backend user@YOUR_SERVER_IP:/opt/bestoffer/
```

### Prepare env file
```bash
cd /opt/bestoffer/backend/deploy
cp .env.prod.example .env.prod
```
Edit `.env.prod` and set strong values:
- `POSTGRES_PASSWORD`
- `JWT_SECRET`

### Start database + api
```bash
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build
```

### Check health
```bash
curl http://YOUR_SERVER_IP:3000/health
```
Expected:
```json
{"status":"ok"}
```

## 3) Create first admin account (once)
Inside API container:
```bash
docker exec -it bestoffer-api sh
npm run seed:admin -- 07701234567 1234 "Admin"
exit
```

## 4) (Optional) move existing data from old database
From machine that has current DB access:
```bash
pg_dump "OLD_DATABASE_URL" > backup.sql
```
Restore on new DB:
```bash
psql "NEW_DATABASE_URL" -f backup.sql
```

## 5) Flutter build for real phones
Use server URL when running/building app:
```bash
flutter run --dart-define=API_BASE_URL=http://YOUR_SERVER_IP:3000
```
or release:
```bash
flutter build apk --release --dart-define=API_BASE_URL=https://api.YOURDOMAIN.com
```

## 6) Important notes
- Do not use `10.0.2.2`/`127.0.0.1` for production phones.
- Open firewall port `3000` or put API behind Nginx + HTTPS.
- Keep database and uploads volumes backed up.

## 7) Optional GPT assistant tuning (Railway variables)
Set these in Railway service variables if you want stronger AI chat quality:
- `OPENAI_ENABLED=true`
- `OPENAI_API_KEY=...`
- `OPENAI_MODEL=gpt-4.1-mini`
- `OPENAI_FALLBACK_MODEL=gpt-4o-mini`
- `OPENAI_TIMEOUT_MS=9000`
- `OPENAI_RETRIES=1`
- `OPENAI_MAX_PROMPT_ITEMS=6`
- `OPENAI_TEMPERATURE=0.55`
- `OPENAI_TOP_P=0.95`
- `OPENAI_MAX_TOKENS=600`
- `OPENAI_PRESENCE_PENALTY=0.25`
- `OPENAI_FREQUENCY_PENALTY=0.45`
- `OPENAI_ASSISTANT_NAME=سوقي`
- `OPENAI_LANGUAGE_LOCK=true`
