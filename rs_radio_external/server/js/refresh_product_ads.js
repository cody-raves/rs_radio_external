const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const resourcePath = process.argv[2] || process.cwd();
const adsPath = path.join(resourcePath, 'data', 'product_ads.json');
const ytdlpBin = process.platform === 'win32'
  ? path.join(resourcePath, 'tools', 'yt-dlp.exe')
  : path.join(resourcePath, 'tools', 'yt-dlp');

function runYtDlp(url) {
  return new Promise((resolve, reject) => {
    const child = spawn(ytdlpBin, ['--dump-single-json', '--no-warnings', '--skip-download', url], {
      cwd: resourcePath,
      windowsHide: true
    });

    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk.toString(); });
    child.stderr.on('data', (chunk) => { stderr += chunk.toString(); });
    child.on('error', reject);
    child.on('close', (code) => {
      if (code !== 0) {
        reject(new Error(stderr.trim() || `yt-dlp exited with code ${code}`));
        return;
      }
      try {
        resolve(JSON.parse(stdout));
      } catch (err) {
        reject(err);
      }
    });
  });
}

async function main() {
  const raw = fs.readFileSync(adsPath, 'utf8');
  const ads = JSON.parse(raw);
  for (let i = 0; i < ads.length; i += 1) {
    const ad = ads[i];
    if (!ad || typeof ad.file !== 'string' || !ad.file.trim()) continue;
    try {
      const meta = await runYtDlp(ad.file.trim());
      if (typeof meta.title === 'string' && meta.title.trim()) {
        ad.label = meta.title.trim();
      }
      const duration = Number(meta.duration || 0);
      if (duration > 0) {
        ad.durationSec = Math.max(1, Math.round(duration));
      }
      console.log(`[refresh_product_ads] ${i + 1}/${ads.length} ok ${ad.label} (${ad.durationSec || 0}s)`);
    } catch (err) {
      console.warn(`[refresh_product_ads] ${i + 1}/${ads.length} failed ${ad.file}: ${err.message}`);
    }
  }
  fs.writeFileSync(adsPath, JSON.stringify(ads, null, 2) + '\n');
}

main().catch((err) => {
  console.error('[refresh_product_ads] fatal:', err.message);
  process.exit(1);
});
