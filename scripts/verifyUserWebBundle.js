'use strict';

const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const bundleRoot = path.join(repoRoot, 'build', 'web_main');

function fail(message) {
  throw new Error(`[user-web-bundle] ${message}`);
}

function requireFile(relativePath, minimumBytes = 1) {
  const absolutePath = path.join(bundleRoot, relativePath);
  if (!fs.existsSync(absolutePath)) {
    fail(`Missing ${relativePath}`);
  }
  const size = fs.statSync(absolutePath).size;
  if (size < minimumBytes) {
    fail(`${relativePath} is unexpectedly small (${size} bytes)`);
  }
  return absolutePath;
}

function requireJson(relativePath) {
  const absolutePath = requireFile(relativePath);
  const contents = fs.readFileSync(absolutePath, 'utf8');
  if (/^\s*</.test(contents)) {
    fail(`${relativePath} contains HTML instead of JSON`);
  }
  try {
    return JSON.parse(contents);
  } catch (error) {
    fail(`${relativePath} is invalid JSON: ${error.message}`);
  }
}

requireFile('index.html', 500);
requireFile('flutter_bootstrap.js', 500);
requireFile('main.dart.js', 1_000_000);
requireFile('assets/AssetManifest.bin', 100);
requireJson('assets/AssetManifest.bin.json');
requireJson('assets/FontManifest.json');
requireFile('assets/fonts/MaterialIcons-Regular.otf', 1_000);

const release = requireJson('maslaki-release.json');
if (!release.version || typeof release.version !== 'string') {
  fail('maslaki-release.json has no release version');
}

const index = fs.readFileSync(path.join(bundleRoot, 'index.html'), 'utf8');
const indexRelease = index.match(/window\.__MASLAKI_WEB_RELEASE__\s*=\s*"([^"]+)"/);
if (!indexRelease || indexRelease[1] !== release.version) {
  fail('index.html and maslaki-release.json use different release versions');
}

const assetBase = index.match(/<meta\s+name="assetBase"\s+content="([^"]+)"/i);
if (assetBase) {
  const relativeBase = assetBase[1].replace(/^\/+|\/+$/g, '');
  if (!relativeBase || relativeBase.includes('..')) {
    fail(`Unsafe assetBase value: ${assetBase[1]}`);
  }
  requireFile(path.join(relativeBase, 'assets', 'AssetManifest.bin'), 100);
  requireJson(path.join(relativeBase, 'assets', 'AssetManifest.bin.json'));
  requireJson(path.join(relativeBase, 'assets', 'FontManifest.json'));
  requireFile(
    path.join(relativeBase, 'assets', 'fonts', 'MaterialIcons-Regular.otf'),
    1_000,
  );
}

console.log(
  `[user-web-bundle] verified ${release.version}: Flutter manifests, fonts, runtime, and versioned assets are present`,
);
