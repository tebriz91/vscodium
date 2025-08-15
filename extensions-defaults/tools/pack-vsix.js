/* eslint-disable no-console */
const fs = require('fs');
const path = require('path');
const child_process = require('child_process');

function run(cmd, opts={}) {
  console.log(`> ${cmd}`);
  child_process.execSync(cmd, { stdio: 'inherit', ...opts });
}

function ensureVsce() {
  try {
    child_process.execSync('vsce --version', { stdio: 'ignore' });
    return 'vsce';
  } catch {
    try {
      child_process.execSync('npx --yes @vscode/vsce --version', { stdio: 'inherit' });
      return 'npx --yes @vscode/vsce';
    } catch (e) {
      throw new Error('vsce not available');
    }
  }
}

function main() {
  const repoRoot = path.resolve(__dirname, '..', '..');
  const extRoot = path.resolve(__dirname, '..', 'vsrat-defaults', 'extension');
  const outDir = path.resolve(repoRoot, 'extensions-extra');
  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });

  const vsce = ensureVsce();
  run(`${vsce} package`, { cwd: extRoot });

  // Find produced vsix
  const files = fs.readdirSync(extRoot).filter(f => f.endsWith('.vsix'));
  if (files.length === 0) throw new Error('No .vsix produced');
  const vsix = files.sort().reverse()[0];
  const src = path.join(extRoot, vsix);
  const dst = path.join(outDir, vsix);
  fs.copyFileSync(src, dst);
  console.log(`Copied ${vsix} to ${dst}`);
}

main();


