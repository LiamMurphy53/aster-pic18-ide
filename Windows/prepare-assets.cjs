'use strict';
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..'), assets = path.join(__dirname, 'assets');
fs.rmSync(assets, { recursive: true, force: true });
fs.mkdirSync(assets, { recursive: true });
for (const name of ['Web', 'Resources', 'Examples']) {
  fs.cpSync(path.join(root, name), path.join(assets, name), { recursive: true,
    filter: p => !/(^|[\\/])(build|dist|private|References)([\\/]|$)/.test(path.relative(path.join(root, name), p)) });
}
for (const name of ['LICENSE', 'THIRD_PARTY_NOTICES.md']) fs.copyFileSync(path.join(root, name), path.join(assets, name));
// Adapt the existing UI at packaging time without changing the native Mac app.
for (const name of ['app.js', 'index.html']) {
  const file = path.join(assets, 'Web', name);
  let text = fs.readFileSync(file, 'utf8').replaceAll('⌘', 'Ctrl+').replaceAll('⇧', 'Shift+').replaceAll('Finder', 'Explorer');
  if (name === 'app.js') text = text.replaceAll('e.metaKey', 'e.ctrlKey').replaceAll(".path.split('/mplab_platform')", ".path.split('/gnuBins')[0].split('/mplab_platform')")
    .replaceAll('/Applications/microchip/mplabx/v6.20', 'C:/Program Files/Microchip/MPLABX/v6.20')
    .replaceAll('/Applications/microchip/xc8/v2.46', 'C:/Program Files/Microchip/xc8/v2.46');
  fs.writeFileSync(file, text);
}
