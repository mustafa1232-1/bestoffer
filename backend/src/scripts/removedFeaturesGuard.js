import fs from 'fs';
import path from 'path';

const root = process.cwd();
const targets = [
  'backend/src',
  'lib',
  'README.md',
  'docs',
  'backend/.env.example',
  'backend/deploy/.env.prod.example',
  'backend/DEPLOY.md',
  'backend/package.json',
];

const forbiddenMatchers = [
  { label: '/api/assistant route', regex: /\/api\/assistant/ },
  { label: 'AssistantChatScreen symbol', regex: /\bAssistantChatScreen\b/ },
  { label: 'assistantApiProvider symbol', regex: /\bassistantApiProvider\b/ },
  { label: 'assistantControllerProvider symbol', regex: /\bassistantControllerProvider\b/ },
  { label: 'AdminAiCenterScreen symbol', regex: /\bAdminAiCenterScreen\b/ },
  { label: 'Settings AI memory screen', regex: /settings_ai_memory_screen/i },
  { label: 'AI DB config usage', regex: /\b(aiDb|runAiSqlMigrations|closeAiDbPools|aiDbHealthSnapshot)\b/ },
  { label: 'AI database env', regex: /\bAI_DATABASE(?:_STANDBY|_PUBLIC|_STANDBY_PUBLIC)?_URL\b/ },
  { label: 'AI DB failover env', regex: /\bAI_DB_FAILOVER_ENABLED\b/ },
  { label: 'Residence card AI env', regex: /\bRESIDENCE_CARD_AI_/ },
  { label: 'AI-only profile field', regex: /\baiProfile\b/ },
  { label: 'AI-only user fields', regex: /\b(aiTermsVersion|aiChatReviewConsent)\b/ },
  { label: 'AI-only tables', regex: /\b(ai_customer_profile|ai_chat_session|ai_chat_message|ai_order_draft|ai_training_memory|ai_chat_observation|ai_recommendation_snapshot|ai_post_moderation_finding|ai_system_finding|ai_user_learning_profile|ai_learning_fact|ai_learning_cycle_run)\b/ },
  { label: 'AI-only social report fields', regex: /\b(source_confidence|ai_finding_id)\b/ },
  { label: 'OpenAI config surface', regex: /\bOPENAI_(?:ENABLED|API_KEY|BASE_URL|MODEL|FALLBACK_MODEL|TIMEOUT_MS|RETRIES|MAX_PROMPT_ITEMS|TEMPERATURE|TOP_P|MAX_TOKENS|PRESENCE_PENALTY|FREQUENCY_PENALTY|ASSISTANT_NAME|LANGUAGE_LOCK|ANALYTIC_MODE|ANALYTIC_MIN_CONFIDENCE|SYSTEM_PROMPT_AR|SYSTEM_PROMPT_EN)\b/ },
  { label: 'Assistant web/learning env', regex: /\b(ASSISTANT_WEB_ASSIST_ENABLED|ASSISTANT_WEB_ASSIST_ON_LOW_CONFIDENCE|AI_WEB_RESEARCH_ENABLED|AI_WEB_RESEARCH_PROVIDER|AI_WEB_RESEARCH_TIMEOUT_MS|AI_WEB_SEARCH_LIMIT|AI_WEB_AUTO_LEARN_ENABLED|AI_WEB_AUTO_LEARN_MAX_QUERIES|AI_IDLE_LEARNING_INTERVAL_SEC|AI_IDLE_LEARNING_IDLE_WINDOW_MIN|AI_DAILY_LEARNING_ENABLED|AI_DAILY_LEARNING_HOUR_BAGHDAD|AI_DAILY_LEARNING_TICK_SEC|AI_DAILY_LEARNING_MAX_QUERIES|AI_DAILY_LEARNING_SYNTHETIC_CONVERSATIONS|AI_DAILY_LEARNING_SYNTHETIC_TURNS|AI_DAILY_SYNTHETIC_MAX_ROWS|AI_DAILY_MEMORY_PRUNE_ENABLED|AI_DAILY_MEMORY_MAX_ROWS|AI_DAILY_MEMORY_PRUNE_BATCH|AI_REDIS_RECENT_OBSERVATIONS_LIMIT|AI_REDIS_STREAM_OBSERVATIONS_KEY|AI_REDIS_STREAM_DAILY_CYCLES_KEY|AI_REDIS_STREAM_MAXLEN|AI_REDIS_USER_WINDOW_TTL_SEC|AI_REDIS_USER_RECENT_TURNS_LIMIT|ASSISTANT_OFF_TOPIC_REDIRECT_AFTER)\b/ },
];

const allowedLiteralSnippets = [
  'pharmacy_assistant',
  'remove_assistant_primary',
  'remove_assistant_auxiliary',
  'Remove assistant/AI footprint',
];

function shouldSkipLine(line) {
  return allowedLiteralSnippets.some((snippet) => line.includes(snippet));
}

function walk(targetPath, out) {
  const fullPath = path.join(root, targetPath);
  if (!fs.existsSync(fullPath)) return;
  const stat = fs.statSync(fullPath);
  if (stat.isDirectory()) {
    for (const entry of fs.readdirSync(fullPath, { withFileTypes: true })) {
      walk(path.join(targetPath, entry.name), out);
    }
    return;
  }
  out.push(targetPath.replace(/\\/g, '/'));
}

const files = [];
const excludedFiles = new Set([
  'backend/src/scripts/removedFeaturesGuard.js',
  'docs/railway-cleanup-checklist.md',
]);
for (const target of targets) walk(target, files);

const findings = [];
for (const relativePath of files) {
  if (excludedFiles.has(relativePath)) continue;
  const fullPath = path.join(root, relativePath);
  const content = fs.readFileSync(fullPath, 'utf8');
  const lines = content.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (shouldSkipLine(line)) continue;
    for (const matcher of forbiddenMatchers) {
      if (!matcher.regex.test(line)) continue;
      findings.push(`${relativePath}:${i + 1}: ${matcher.label}: ${line.trim()}`);
    }
  }
}

if (findings.length > 0) {
  console.error('Removed-features guard failed. Forbidden AI/assistant references remain:\n');
  for (const finding of findings) console.error(finding);
  process.exit(1);
}

console.log('Removed-features guard passed. No forbidden AI/assistant references found.');
