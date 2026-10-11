#!/usr/bin/env node

/**
 * Trackpad Toggle — NPM CLI Runner & Installer
 *
 * Allows installing, running, and managing Trackpad Toggle via:
 *   npx trackpad-toggle
 *   npm install -g trackpad-toggle
 */

const os = require('os');
const fs = require('fs');
const path = require('path');
const https = require('https');
const { execSync, spawnSync } = require('child_process');

// ── 1. OS Compatibility Check ────────────────────────────────────────────────
if (process.platform !== 'darwin') {
  console.error('\x1b[31mError: Trackpad Toggle is a native macOS application designed for MacBooks.\x1b[0m');
  console.error(`Current platform (${process.platform}) is not supported.`);
  process.exit(1);
}

const APP_PATH = '/Applications/TrackpadToggle.app';
const REPO = 'rajanraj2/trackpad-toggle';
const RELEASES_API = `https://api.github.com/repos/${REPO}/releases/latest`;

// ── 2. Helper Functions ─────────────────────────────────────────────────────

function run(cmd, options = {}) {
  try {
    return execSync(cmd, { stdio: 'pipe', encoding: 'utf8', ...options }).trim();
  } catch (err) {
    return null;
  }
}

function isInstalled() {
  return fs.existsSync(APP_PATH) && fs.existsSync(path.join(APP_PATH, 'Contents/MacOS/TrackpadToggle'));
}

function isRunning() {
  const pids = run('pgrep -x TrackpadToggle');
  return !!pids;
}

function getInstalledVersion() {
  if (!isInstalled()) return null;
  const plistPath = path.join(APP_PATH, 'Contents/Info.plist');
  return run(`defaults read "${plistPath}" CFBundleShortVersionString`) || 'Unknown';
}

function fetchLatestReleaseInfo() {
  return new Promise((resolve, reject) => {
    const options = {
      headers: {
        'User-Agent': 'trackpad-toggle-npm-runner',
        'Accept': 'application/vnd.github+json'
      }
    };
    https.get(RELEASES_API, options, (res) => {
      if (res.statusCode !== 200) {
        return reject(new Error(`GitHub API returned HTTP ${res.statusCode}`));
      }
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(body);
          const dmgAsset = (json.assets || []).find(a => a.name.endsWith('.dmg'));
          if (!dmgAsset) {
            return reject(new Error('No .dmg asset found on latest GitHub release'));
          }
          resolve({
            version: (json.tag_name || 'latest').replace(/^v/, ''),
            downloadUrl: dmgAsset.browser_download_url,
            name: json.name || json.tag_name
          });
        } catch (e) {
          reject(e);
        }
      });
    }).on('error', reject);
  });
}

function downloadFile(url, destPath) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(destPath);
    
    function get(targetUrl) {
      https.get(targetUrl, { headers: { 'User-Agent': 'trackpad-toggle-npm' } }, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          return get(res.headers.location);
        }
        if (res.statusCode !== 200) {
          return reject(new Error(`Download failed with status ${res.statusCode}`));
        }
        const total = parseInt(res.headers['content-length'] || '0', 10);
        let downloaded = 0;

        res.on('data', (chunk) => {
          downloaded += chunk.length;
          if (total > 0) {
            const percent = ((downloaded / total) * 100).toFixed(0);
            process.stdout.write(`\r▶ Downloading TrackpadToggle.dmg: ${percent}% (${(downloaded / 1024 / 1024).toFixed(1)} MB / ${(total / 1024 / 1024).toFixed(1)} MB)`);
          }
        });

        res.pipe(file);
        file.on('finish', () => {
          file.close(() => {
            process.stdout.write('\n');
            resolve();
          });
        });
      }).on('error', (err) => {
        fs.unlink(destPath, () => {});
        reject(err);
      });
    }

    get(url);
  });
}

async function installFromRelease() {
  console.log('\x1b[36m▶ Fetching latest release information from GitHub…\x1b[0m');
  const release = await fetchLatestReleaseInfo();
  console.log(`✓ Found latest version: \x1b[32mv${release.version}\x1b[0m`);

  const tempDir = os.tmpdir();
  const tempDmg = path.join(tempDir, `TrackpadToggle_${Date.now()}.dmg`);
  const mountPoint = path.join(tempDir, `TrackpadToggle_mount_${Date.now()}`);

  try {
    await downloadFile(release.downloadUrl, tempDmg);

    console.log('▶ Mounting disk image…');
    fs.mkdirSync(mountPoint, { recursive: true });
    run(`hdiutil attach -nobrowse -readonly -mountpoint "${mountPoint}" "${tempDmg}"`);

    const sourceApp = path.join(mountPoint, 'TrackpadToggle.app');
    if (!fs.existsSync(sourceApp)) {
      throw new Error('TrackpadToggle.app not found inside DMG');
    }

    console.log(`▶ Installing to ${APP_PATH}…`);
    run(`killall TrackpadToggle 2>/dev/null || true`);
    run(`rm -rf "${APP_PATH}"`);
    run(`cp -R "${sourceApp}" "/Applications/"`);

    console.log('▶ Clearing macOS Gatekeeper quarantine…');
    run(`xattr -d -r com.apple.quarantine "${APP_PATH}" 2>/dev/null || true`);

    console.log('▶ Detaching disk image…');
    run(`hdiutil detach "${mountPoint}" -force 2>/dev/null || true`);
    run(`rm -rf "${mountPoint}" "${tempDmg}"`);

    console.log('\x1b[32m✅ Trackpad Toggle installed successfully!\x1b[0m');
    console.log(`   Location: ${APP_PATH}`);
    console.log(`   Version:  v${release.version}`);
    return release.version;
  } catch (err) {
    run(`hdiutil detach "${mountPoint}" -force 2>/dev/null || true`);
    run(`rm -rf "${mountPoint}" "${tempDmg}"`);
    throw err;
  }
}

function launchApp() {
  console.log('▶ Launching Trackpad Toggle…');
  run(`open "${APP_PATH}"`);
  console.log('\x1b[32m✓ Trackpad Toggle is now running in your menu bar!\x1b[0m');
  console.log('  Default toggle shortcut: \x1b[33m⌃⌥⌘T\x1b[0m (Control + Option + Command + T)');
  console.log('  Open Settings anytime via Spotlight (⌘Space) or the menu-bar icon.');
}

function printStatus() {
  console.log('\n\x1b[1mTrackpad Toggle Status:\x1b[0m');
  console.log('──────────────────────────────────────');
  console.log(`Installed: ${isInstalled() ? '\x1b[32mYES\x1b[0m (' + APP_PATH + ')' : '\x1b[31mNO\x1b[0m'}`);
  if (isInstalled()) {
    console.log(`Version:   v${getInstalledVersion()}`);
    console.log(`Running:   ${isRunning() ? '\x1b[32mYES (active in menu bar)\x1b[0m' : '\x1b[33mNO (stopped)\x1b[0m'}`);
    console.log(`Shortcut:  ⌃⌥⌘T (default)`);
  }
  console.log('──────────────────────────────────────\n');
}

function printHelp() {
  console.log(`
\x1b[1mTrackpad Toggle — macOS Menu-Bar Utility CLI\x1b[0m

Usage:
  npx trackpad-toggle [command]
  trackpad-toggle [command]

Commands:
  (no args)    Launch Trackpad Toggle (installs automatically if not installed)
  install      Install or update to the latest release in /Applications
  status       Show current installation and running status
  open, start  Launch the installed application
  quit, stop   Quit all running instances of Trackpad Toggle
  uninstall    Completely remove the application and reset permissions
  help, -h     Show this help message

Examples:
  npx trackpad-toggle          # Run or install immediately
  npx trackpad-toggle status   # Inspect current app state
  npx trackpad-toggle install  # Fresh install from latest release
`);
}

// ── 3. CLI Command Dispatcher ────────────────────────────────────────────────

async function main() {
  const arg = (process.argv[2] || '').toLowerCase().trim();

  switch (arg) {
    case 'help':
    case '-h':
    case '--help':
      printHelp();
      break;

    case 'status':
      printStatus();
      break;

    case 'open':
    case 'start':
      if (!isInstalled()) {
        console.log('Trackpad Toggle is not installed yet. Installing now…');
        await installFromRelease();
      }
      launchApp();
      break;

    case 'quit':
    case 'stop':
      console.log('▶ Stopping Trackpad Toggle…');
      run('killall TrackpadToggle 2>/dev/null || true');
      console.log('✓ Trackpad Toggle stopped.');
      break;

    case 'install':
    case 'update':
      await installFromRelease();
      launchApp();
      break;

    case 'uninstall':
      console.log('▶ Stopping Trackpad Toggle…');
      run('killall TrackpadToggle 2>/dev/null || true');
      if (fs.existsSync(APP_PATH)) {
        console.log(`▶ Removing ${APP_PATH}…`);
        run(`rm -rf "${APP_PATH}"`);
      }
      console.log('▶ Resetting macOS TCC permission records…');
      run('tccutil reset Accessibility com.powertools.trackpadtoggle 2>/dev/null || true');
      run('tccutil reset ListenEvent com.powertools.trackpadtoggle 2>/dev/null || true');
      console.log('\x1b[32m✓ Trackpad Toggle has been completely uninstalled.\x1b[0m');
      break;

    case '':
    default:
      if (!isInstalled()) {
        console.log('\x1b[33mTrackpad Toggle is not installed in /Applications. Installing now…\x1b[0m');
        await installFromRelease();
      }
      launchApp();
      break;
  }
}

main().catch((err) => {
  console.error('\x1b[31mError:\x1b[0m', err.message);
  process.exit(1);
});
