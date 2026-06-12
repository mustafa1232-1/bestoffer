import fs from 'fs';
import path from 'path';

const root = process.cwd();
const backendSrc = path.join(root, 'backend', 'src');
const libDir = path.join(root, 'lib');

function read(file) {
  return fs.readFileSync(file, 'utf8');
}

function walk(dir, predicate = () => true, acc = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, predicate, acc);
    else if (predicate(full)) acc.push(full);
  }
  return acc;
}

function rel(p) {
  return path.relative(root, p).replace(/\\/g, '/');
}

function parseAppMounts(appJsPath) {
  const text = read(appJsPath);
  const mounts = [];
  const regex = /app\.use\(\s*[\"'\`]([^\"'\`]+)[\"'\`]\s*,\s*([a-zA-Z0-9_]+)\s*\)/g;
  let m;
  while ((m = regex.exec(text)) !== null) {
    mounts.push({ base: m[1], routerVar: m[2] });
  }
  return mounts;
}

function parseRouteFiles() {
  const files = walk(path.join(backendSrc, 'modules'), (f) => f.endsWith('.routes.js'));
  const routers = [];
  for (const file of files) {
    const text = read(file);
    const exported = [...text.matchAll(/export const\s+([a-zA-Z0-9_]+)\s*=\s*Router\(\)/g)].map((m) => m[1]);
    if (exported.length === 0) continue;

    for (const routerName of exported) {
      const globalUseRegex = new RegExp(`${routerName}\\.use\\(([^)]*)\\)`, 'g');
      const globalUses = [];
      let gm;
      while ((gm = globalUseRegex.exec(text)) !== null) {
        globalUses.push(gm[1]);
      }

      const routeRegex = /([A-Za-z0-9_]+)\.(get|post|put|patch|delete)\(\s*[\"'\`]([^\"'\`]+)[\"'\`]\s*,([\s\S]*?)\)\s*;/g;
      const routes = [];
      let rm;
      while ((rm = routeRegex.exec(text)) !== null) {
        const caller = rm[1];
        if (caller !== routerName) continue;
        const method = rm[2].toUpperCase();
        const routePath = rm[3];
        const args = rm[4].replace(/\n/g, ' ').replace(/\s+/g, ' ').trim();
        const tokens = args.split(',').map((s) => s.trim()).filter(Boolean);
        const handler = tokens[tokens.length - 1] || '';
        const middlewares = tokens.slice(0, -1);

        routes.push({ method, routePath, args, handler, middlewares });
      }

      routers.push({ routerName, file, globalUses, routes, text });
    }
  }
  return routers;
}

function detectAuthAndRole(route, router) {
  const combined = `${router.globalUses.join(',')} ${route.middlewares.join(',')} ${route.args}`;
  const authRequired = /requireAuth|opsAuth|requireOpsAuth/.test(combined) ? 'yes' : 'no/unknown';

  const roleTokens = [
    'requireSuperAdmin',
    'requireAdmin',
    'requireBackoffice',
    'requireAccountant',
    'requireCompanyAdmin',
    'requireCompanyUser',
    'requireOwner',
    'requireMerchantOwner',
    'requireMerchantStaff',
    'requireDelivery',
    'requireDeliveryAgent',
    'requireTaxiCaptain',
    'requirePharmacy',
    'requireCustomer',
    'requireHr',
    'opsAuth',
    'requireOpsAuth',
  ];
  const found = roleTokens.filter((t) => combined.includes(t));
  return {
    authRequired,
    role: found.length ? found.join(', ') : 'default/unknown',
  };
}

function normalizeEndpoint(base, routePath) {
  if (routePath === '/') return base;
  if (base.endsWith('/') && routePath.startsWith('/')) return `${base}${routePath.slice(1)}`;
  if (!base.endsWith('/') && !routePath.startsWith('/')) return `${base}/${routePath}`;
  return `${base}${routePath}`;
}

function collectFrontendLibDirs() {
  const dirs = [];
  if (fs.existsSync(libDir)) dirs.push(libDir);
  const containers = ['apps', 'packages'];
  for (const container of containers) {
    const containerDir = path.join(root, container);
    if (!fs.existsSync(containerDir)) continue;
    for (const entry of fs.readdirSync(containerDir, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const candidate = path.join(containerDir, entry.name, 'lib');
      if (fs.existsSync(candidate)) dirs.push(candidate);
    }
  }
  return dirs;
}

function normalizeUsageEndpoint(raw) {
  const noHost = raw.startsWith('http')
    ? raw.replace(/^https?:\/\/[^/]+/, '')
    : raw;
  const noQuery = noHost.split('?')[0];
  const collapsed = noQuery
    .replace(/\$\{[^}]+\}/g, ':param')
    .replace(/\$[A-Za-z_][A-Za-z0-9_]*/g, ':param')
    .replace(/\/+/g, '/');
  if (!collapsed.startsWith('/api/')) return null;
  return collapsed.replace(/\/$/, '') || '/';
}

function normalizeRouteEndpoint(raw) {
  return raw
    .replace(/\/:[A-Za-z0-9_]+/g, '/:param')
    .replace(/\/+/g, '/')
    .replace(/\/$/, '') || '/';
}

function endpointsMatch(routeEndpoint, usageEndpoint) {
  const a = normalizeRouteEndpoint(routeEndpoint);
  const b = normalizeRouteEndpoint(usageEndpoint);
  if (a === b) return true;

  const aSeg = a.split('/').filter(Boolean);
  const bSeg = b.split('/').filter(Boolean);
  if (aSeg.length !== bSeg.length) return false;
  for (let i = 0; i < aSeg.length; i += 1) {
    const left = aSeg[i];
    const right = bSeg[i];
    if (left === ':param' || right === ':param') continue;
    if (left !== right) return false;
  }
  return true;
}

function parseFlutterApiUsage() {
  const dartFiles = [];
  for (const dir of collectFrontendLibDirs()) {
    walk(dir, (f) => f.endsWith('.dart'), dartFiles);
  }
  const endpointToFiles = new Map();
  for (const file of dartFiles) {
    const text = read(file);
    const matches = [...text.matchAll(/[\"'\`]((?:https?:\/\/[^\"'\`\s]+)?\/api\/[^\"'\`\n\r]*)[\"'\`]/g)];
    for (const m of matches) {
      const endpoint = normalizeUsageEndpoint(m[1]);
      if (!endpoint) continue;
      if (!endpointToFiles.has(endpoint)) endpointToFiles.set(endpoint, new Set());
      endpointToFiles.get(endpoint).add(rel(file));
    }
  }
  return endpointToFiles;
}

function parseScreens() {
  const screenFiles = walk(libDir, (f) => /(_screen|_page)\.dart$/i.test(path.basename(f)));
  const screens = [];
  for (const file of screenFiles) {
    const text = read(file);
    const classes = [...text.matchAll(/class\s+([A-Za-z0-9_]+)\s+extends\s+(?:Consumer)?(?:Stateful|Stateless)Widget/g)].map((m) => m[1]);
    const hasL10n = /context\.l10n|AppLocalizations|\.lt\(|companyText\(|strings\.t\(/.test(text);
    const hardcoded = [...text.matchAll(/'([A-Za-z][^'\n]{2,60})'/g)].length;

    const relPath = rel(file);
    const pathParts = relPath.split('/');
    const featureIdx = pathParts.indexOf('features');
    const feature = featureIdx >= 0 && pathParts[featureIdx + 1] ? pathParts[featureIdx + 1] : 'core';

    let role = 'mixed';
    let platformModule = feature;
    if (/admin|ai_dev_support/.test(relPath)) role = 'super_admin/admin';
    else if (/owner|merchant|store/.test(relPath)) role = 'store_owner/store_staff';
    else if (/company/.test(relPath)) role = 'company_admin/company_staff';
    else if (/delivery|courier/.test(relPath)) role = 'delivery_agent';
    else if (/taxi|captain/.test(relPath)) role = 'taxi_captain';
    else if (/pharmacy/.test(relPath)) role = 'pharmacy';
    else if (/auth/.test(relPath)) role = 'all_roles';
    else role = 'customer/user';

    const routeHints = [...text.matchAll(/route(Name)?\s*[:=]\s*["'`]([^"'`]+)["'`]/g)].map((m) => m[2]);
    const route = routeHints[0] || 'navigator/material-route';

    const status = hasL10n ? (hardcoded > 30 ? 'needs review' : 'complete/likely') : 'needs review';

    screens.push({
      screenName: classes.join(', ') || path.basename(file, '.dart'),
      platformModule,
      route,
      role,
      translationStatus: hasL10n ? 'localized/partial' : 'needs localization review',
      themeStatus: /Theme\.of\(|AppTheme|app_theme|AppColors/.test(text) ? 'theme-aware' : 'needs theme review',
      status,
      notes: relPath,
      feature,
    });
  }
  return screens;
}

function escapeMd(text) {
  return String(text ?? '').replace(/\|/g, '\\|').replace(/\n/g, ' ');
}

function writePreLaunchReport({ backendRows, screenRows, flowRows }) {
  const out = [];
  out.push('# PRE_LAUNCH_AUDIT_REPORT');
  out.push('');
  out.push('## 1) Backend API Inventory');
  out.push('');
  out.push('| method | endpoint | controller/handler | auth required? | required role/permission | frontend screen using it | status | notes |');
  out.push('|---|---|---|---|---|---|---|---|');
  for (const row of backendRows) {
    out.push(`| ${row.method} | ${escapeMd(row.endpoint)} | ${escapeMd(row.handler)} | ${row.authRequired} | ${escapeMd(row.role)} | ${escapeMd(row.frontend)} | ${row.status} | ${escapeMd(row.notes)} |`);
  }
  out.push('');
  out.push('## 2) Frontend Screen Inventory');
  out.push('');
  out.push('| screen name | platform/module | route | role/user type | APIs used | translation status | theme status | status | notes |');
  out.push('|---|---|---|---|---|---|---|---|---|');
  for (const s of screenRows) {
    out.push(`| ${escapeMd(s.screenName)} | ${escapeMd(s.platformModule)} | ${escapeMd(s.route)} | ${escapeMd(s.role)} | ${escapeMd(s.apisUsed)} | ${escapeMd(s.translationStatus)} | ${escapeMd(s.themeStatus)} | ${escapeMd(s.status)} | ${escapeMd(s.notes)} |`);
  }
  out.push('');
  out.push('## 3) Business Flow Inventory');
  out.push('');
  out.push('| flow name | user type | backend endpoints | frontend screens | database tables | notifications | payment involvement | status | missing parts |');
  out.push('|---|---|---|---|---|---|---|---|---|');
  for (const f of flowRows) {
    out.push(`| ${escapeMd(f.flow)} | ${escapeMd(f.userType)} | ${escapeMd(f.endpoints)} | ${escapeMd(f.screens)} | ${escapeMd(f.tables)} | ${escapeMd(f.notifications)} | ${escapeMd(f.payment)} | ${escapeMd(f.status)} | ${escapeMd(f.missing)} |`);
  }
  fs.writeFileSync(path.join(root, 'PRE_LAUNCH_AUDIT_REPORT.md'), out.join('\n'));
}

function writeConnectionMatrix(rows) {
  const out = [];
  out.push('# API_FRONTEND_CONNECTION_MATRIX');
  out.push('');
  out.push('| method | backend endpoint | backend handler | frontend consumers | request/response handling | auth/permission guard | status | notes |');
  out.push('|---|---|---|---|---|---|---|---|');
  for (const r of rows) {
    out.push(`| ${r.method} | ${escapeMd(r.endpoint)} | ${escapeMd(r.handler)} | ${escapeMd(r.frontend)} | ${escapeMd(r.contract)} | ${escapeMd(r.guard)} | ${r.status} | ${escapeMd(r.notes)} |`);
  }
  fs.writeFileSync(path.join(root, 'API_FRONTEND_CONNECTION_MATRIX.md'), out.join('\n'));
}

function main() {
  const mounts = parseAppMounts(path.join(backendSrc, 'app.js'));
  const routers = parseRouteFiles();
  const endpointUse = parseFlutterApiUsage();
  const screens = parseScreens();

  const routerMountMap = new Map();
  for (const m of mounts) {
    if (!routerMountMap.has(m.routerVar)) routerMountMap.set(m.routerVar, []);
    routerMountMap.get(m.routerVar).push(m.base);
  }

  const backendRows = [];

  for (const router of routers) {
    const bases = routerMountMap.get(router.routerName) || [];
    for (const route of router.routes) {
      const { authRequired, role } = detectAuthAndRole(route, router);
      const effectiveBases = bases.length ? bases : ['UNMOUNTED'];
      for (const base of effectiveBases) {
        const endpoint = base === 'UNMOUNTED' ? `UNMOUNTED${route.routePath}` : normalizeEndpoint(base, route.routePath);

        const directFiles = [];
        for (const [ep, files] of endpointUse.entries()) {
          if (endpointsMatch(endpoint, ep)) {
            for (const f of files) directFiles.push(f);
          }
        }
        const uniqFiles = [...new Set(directFiles)].slice(0, 6);
        let status = 'not connected';
        if (base === 'UNMOUNTED') status = 'not connected';
        else if (uniqFiles.length > 0) status = 'connected/partial';

        backendRows.push({
          method: route.method,
          endpoint,
          handler: route.handler || 'unknown',
          authRequired,
          role,
          frontend: uniqFiles.join('<br>') || '-',
          status,
          notes: rel(router.file),
        });
      }
    }
  }

  backendRows.sort((a, b) => `${a.endpoint} ${a.method}`.localeCompare(`${b.endpoint} ${b.method}`));

  const apiByFeature = new Map();
  for (const [endpoint, files] of endpointUse.entries()) {
    for (const f of files) {
      const m = f.match(/lib\/features\/([^/]+)/);
      const feature = m ? m[1] : 'core';
      if (!apiByFeature.has(feature)) apiByFeature.set(feature, new Set());
      apiByFeature.get(feature).add(endpoint);
    }
  }

  const screenRows = screens.map((s) => {
    const apis = [...(apiByFeature.get(s.feature) || new Set())].slice(0, 8);
    return {
      ...s,
      apisUsed: apis.join('<br>') || '-',
    };
  });
  screenRows.sort((a, b) => a.platformModule.localeCompare(b.platformModule) || a.screenName.localeCompare(b.screenName));

  const flowRows = [
    {
      flow: 'Auth/Register/Login',
      userType: 'all roles',
      endpoints: '/api/auth/*',
      screens: 'login/register screens + role login',
      tables: 'users, sessions, role-specific profiles',
      notifications: 'optional push',
      payment: 'none',
      status: 'verified by tests/needs prod smoke',
      missing: 'cross-role prod smoke pending',
    },
    {
      flow: 'Customer order lifecycle',
      userType: 'customer,user',
      endpoints: '/api/orders/*, /api/merchants/*, /api/feed/*',
      screens: 'cart, checkout, orders, tracking',
      tables: 'orders, order_items, carts, addresses, pricing',
      notifications: 'order attention + push',
      payment: 'yes',
      status: 'partial',
      missing: 'full end-to-end prod run with tagged test orders',
    },
    {
      flow: 'Store owner order handling',
      userType: 'store owner/staff',
      endpoints: '/api/owner/*, /api/merchant/*, /api/orders/*',
      screens: 'store owner dashboard/orders/products',
      tables: 'merchants, products, merchant settlements',
      notifications: 'merchant alerts',
      payment: 'yes',
      status: 'partial',
      missing: 'real prod accept/prepare/complete chain verification',
    },
    {
      flow: 'Delivery mission lifecycle',
      userType: 'delivery agent',
      endpoints: '/api/delivery/*',
      screens: 'delivery dashboard + mission screens',
      tables: 'delivery_assignments, order_status_history',
      notifications: 'assignment alerts',
      payment: 'settlement impact',
      status: 'partial',
      missing: 'live dispatch/complete validation',
    },
    {
      flow: 'Taxi captain lifecycle',
      userType: 'taxi captain',
      endpoints: '/api/taxi/*',
      screens: 'captain dashboard/trips/loyalty',
      tables: 'taxi_rides, taxi_captain_profiles, coupons',
      notifications: 'trip alerts',
      payment: 'yes',
      status: 'partial',
      missing: 'live trip start/end fare confirmation',
    },
    {
      flow: 'Company portal operations',
      userType: 'company admin/staff',
      endpoints: '/api/company/*',
      screens: 'company portal screens',
      tables: 'companies, branches, company_employees',
      notifications: 'company alerts',
      payment: 'optional',
      status: 'partial',
      missing: 'branch/employee CRUD prod smoke',
    },
    {
      flow: 'Pharmacy workflow',
      userType: 'pharmacy/store',
      endpoints: '/api/pharmacy/*',
      screens: 'pharmacy feature screens',
      tables: 'pharmacy-related commerce tables',
      notifications: 'order alerts',
      payment: 'yes',
      status: 'needs review',
      missing: 'standalone app mapping + live flow check',
    },
    {
      flow: 'AI DEV SUPPORT operations',
      userType: 'super admin',
      endpoints: '/api/admin/ops/*, /ops/*',
      screens: 'ai_dev_support dashboard/settings/incidents/approvals',
      tables: 'ops_incidents, ops_actions, ops_audit_logs, ops_settings',
      notifications: 'webhooks + push + audit',
      payment: 'none direct',
      status: 'partial',
      missing: 'external keys matrix and prod webhook roundtrip confirmation',
    },
  ];

  writePreLaunchReport({ backendRows, screenRows, flowRows });

  const matrixRows = backendRows.map((r) => ({
    method: r.method,
    endpoint: r.endpoint,
    handler: r.handler,
    frontend: r.frontend,
    contract: 'validated by unit/widget tests where available; full schema audit pending per-module',
    guard: `${r.authRequired}; ${r.role}`,
    status: r.status,
    notes: r.notes,
  }));
  writeConnectionMatrix(matrixRows);

  console.log(`Generated PRE_LAUNCH_AUDIT_REPORT.md (${backendRows.length} backend rows, ${screenRows.length} screens).`);
  console.log(`Generated API_FRONTEND_CONNECTION_MATRIX.md (${matrixRows.length} rows).`);
}

main();
