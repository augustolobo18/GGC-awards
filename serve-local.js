// Servidor estático local para public/ (só para desenvolvimento; a Vercel não usa este arquivo).
// Sem dependências: não baixa nada do npm (evita risco de pacote comprometido via npx).
//
// Proteções:
// - Escuta só em 127.0.0.1: nenhuma outra máquina da rede alcança a porta.
// - Aceita só Host localhost/127.0.0.1 (bloqueia DNS rebinding de sites maliciosos).
// - Só GET/HEAD; nunca sai de public/ (path traversal); nunca lista diretórios nem serve dotfiles.
//
// Uso: node serve-local.js            (porta 3000)
//      node serve-local.js 3001       (outra porta)
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');

const HOST = '127.0.0.1';
const PORT = Number(process.argv[2] || 3000);
const ROOT = path.resolve(__dirname, 'public');
const HOSTS_OK = new Set([`localhost:${PORT}`, `127.0.0.1:${PORT}`]);

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.svg': 'image/svg+xml',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif',
  '.webp': 'image/webp', '.ico': 'image/x-icon', '.mp3': 'audio/mpeg', '.wav': 'audio/wav',
  '.woff': 'font/woff', '.woff2': 'font/woff2', '.ttf': 'font/ttf',
};

function responder(res, status, corpo) {
  res.writeHead(status, { 'Content-Type': 'text/plain; charset=utf-8', 'X-Content-Type-Options': 'nosniff' });
  res.end(corpo);
}

// Resolve a URL para um arquivo dentro de ROOT, ou null se não puder/precisar servir.
function resolver(url) {
  let p;
  try { p = decodeURIComponent(url.split('?')[0].split('#')[0]); } catch { return null; }
  if (p.includes('\0')) return null;
  let file = path.resolve(ROOT, '.' + path.posix.normalize('/' + p));
  if (file !== ROOT && !file.startsWith(ROOT + path.sep)) return null;
  if (path.relative(ROOT, file).split(path.sep).some((parte) => parte.startsWith('.'))) return null;
  try {
    if (fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
  } catch {
    if (!path.extname(file) && fs.existsSync(file + '.html')) file += '.html';
  }
  return file;
}

const servidor = http.createServer((req, res) => {
  if (!HOSTS_OK.has(String(req.headers.host || '').toLowerCase())) return responder(res, 421, 'Host não permitido');
  if (req.method !== 'GET' && req.method !== 'HEAD') return responder(res, 405, 'Método não permitido');
  const file = resolver(req.url || '/');
  if (!file) return responder(res, 404, '404');
  fs.readFile(file, (err, data) => {
    if (err) return responder(res, 404, '404');
    res.writeHead(200, {
      'Content-Type': TYPES[path.extname(file).toLowerCase()] || 'application/octet-stream',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
      'X-Frame-Options': 'DENY',
      'Referrer-Policy': 'strict-origin-when-cross-origin',
    });
    res.end(req.method === 'HEAD' ? undefined : data);
  });
});

servidor.on('error', (e) => { console.error(`Não consegui abrir ${HOST}:${PORT}: ${e.message}`); process.exit(1); });
servidor.listen(PORT, HOST, () => console.log(`Servindo ${ROOT} em http://localhost:${PORT} (só esta máquina)`));
