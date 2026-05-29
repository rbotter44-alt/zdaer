// Cloudflare Worker resolver for Light On PWA.
// Purpose: extract a direct playable URL (.m3u8/.mpd/.mp4) from provider pages
// and return JSON to the Flutter Web player. It does NOT proxy video segments.
//
// Deploy as a Cloudflare Worker, then set in the browser console:
// localStorage.setItem('LIGHTON_WEB_RESOLVER', 'https://YOUR-WORKER.workers.dev/resolve')
// or run Flutter with:
// flutter run -d chrome --dart-define=LIGHTON_WEB_RESOLVER=https://YOUR-WORKER.workers.dev/resolve

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET,POST,OPTIONS',
  'access-control-allow-headers': 'content-type,authorization,x-requested-with,range',
  'access-control-max-age': '86400',
};

const LIGHTON_WORKER_VERSION = 'fix15-proxy-subtitle-debug';

function json(data, status = 200) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: {
      ...CORS,
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  });
}

function isHttpUrl(value) {
  try {
    const u = new URL(String(value || ''));
    return u.protocol === 'http:' || u.protocol === 'https:';
  } catch (_) {
    return false;
  }
}

function isPlayable(url) {
  return /\.(m3u8|mpd|mp4|m4v|mov|webm)(?:$|[?#])/i.test(String(url || '')) ||
    String(url || '').toLowerCase().includes('.m3u8') ||
    String(url || '').toLowerCase().includes('.mpd');
}

function absoluteUrl(candidate, base) {
  if (!candidate) return '';
  let text = String(candidate).trim();
  if (!text) return '';
  text = text.replace(/\\\//g, '/');
  text = text.replace(/\\u0026/g, '&').replace(/&amp;/g, '&');
  text = text.replace(/^["'`]+|["'`,;]+$/g, '');
  try {
    return new URL(text, base).toString();
  } catch (_) {
    return '';
  }
}

function decodeJsEscapes(text) {
  let out = String(text || '');
  for (let i = 0; i < 3; i++) {
    const before = out;
    out = out
      .replace(/\\\//g, '/')
      .replace(/\\u002F/gi, '/')
      .replace(/\\u002f/gi, '/')
      .replace(/\\u003A/gi, ':')
      .replace(/\\u003a/gi, ':')
      .replace(/\\u0026/gi, '&')
      .replace(/\\u003D/gi, '=')
      .replace(/\\u003d/gi, '=')
      .replace(/&amp;/g, '&');
    if (out === before) break;
  }
  return out;
}

function addCandidate(set, value, base) {
  const url = absoluteUrl(value, base);
  if (!url || !isPlayable(url)) return;
  set.add(url);
}

function extractCandidates(text, base) {
  const found = new Set();
  const body = decodeJsEscapes(text);

  const patterns = [
    /https?:\/\/[^\s"'<>\\]+?\.(?:m3u8|mpd|mp4|m4v|mov|webm)(?:\?[^\s"'<>\\]*)?/gi,
    /(?:file|src|url|playlist|source|hls|dash|stream)\s*[:=]\s*["'`]([^"'`]+?\.(?:m3u8|mpd|mp4|m4v|mov|webm)(?:\?[^"'`]*)?)["'`]/gi,
    /["'`]((?:\/|\.\/|\.\.\/)[^"'`]+?\.(?:m3u8|mpd|mp4|m4v|mov|webm)(?:\?[^"'`]*)?)["'`]/gi,
  ];

  for (const re of patterns) {
    let m;
    while ((m = re.exec(body)) !== null) {
      addCandidate(found, m[1] || m[0], base);
    }
  }
  return [...found];
}

function extractScriptUrls(html, base) {
  const out = [];
  const re = /<script[^>]+src=["']([^"']+)["'][^>]*>/gi;
  let m;
  while ((m = re.exec(html)) !== null) {
    const u = absoluteUrl(m[1], base);
    if (u && !out.includes(u)) out.push(u);
  }
  return out.slice(0, 12);
}

function scoreCandidate(url) {
  const u = String(url || '').toLowerCase();
  let score = 0;
  if (u.includes('.m3u8')) score += 1000;
  if (u.includes('.mpd')) score += 850;
  if (/\.(mp4|m4v|mov|webm)/.test(u)) score += 500;
  if (u.includes('master')) score += 120;
  if (u.includes('playlist')) score += 60;
  if (u.includes('workers.dev')) score += 90;
  if (u.includes('1080') || u.includes('1920x1080')) score += 80;
  if (u.includes('720') || u.includes('1280x720')) score += 40;
  if (u.includes('360') || u.includes('640x360')) score -= 30;
  if (u.includes('.css') || u.includes('.js')) score -= 1000;
  return score;
}

async function fetchText(url, referer) {
  const headers = {
    'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,application/json;q=0.8,*/*;q=0.7',
    'accept-language': 'en-US,en;q=0.9,ar;q=0.8',
    'cache-control': 'no-cache',
    'pragma': 'no-cache',
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome Safari',
  };
  if (referer) headers.referer = referer;
  const res = await fetch(url, { headers, redirect: 'follow' });
  const contentType = res.headers.get('content-type') || '';
  const text = await res.text();
  return { ok: res.ok, status: res.status, url: res.url, contentType, text };
}

async function validatePlayable(url, referer) {
  try {
    const res = await fetch(url, {
      headers: {
        'accept': '*/*',
        'range': 'bytes=0-4095',
        ...(referer ? { referer } : {}),
        'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome Safari',
      },
      redirect: 'follow',
    });
    const ct = res.headers.get('content-type') || '';
    const text = await res.text().catch(() => '');
    if (!res.ok && res.status !== 206) return { ok: false, status: res.status, contentType: ct };
    if (url.toLowerCase().includes('.m3u8') && !text.includes('#EXTM3U') && !ct.includes('mpegurl')) {
      return { ok: false, status: res.status, contentType: ct, reason: 'not EXT-M3U' };
    }
    return { ok: true, status: res.status, contentType: ct, sample: text.slice(0, 200) };
  } catch (e) {
    return { ok: false, status: 0, error: String(e && e.message ? e.message : e) };
  }
}

async function resolveProvider(inputUrl, pageUrl) {
  const target = new URL(inputUrl).toString();
  const referer = pageUrl && isHttpUrl(pageUrl) ? pageUrl : target;
  const allCandidates = new Set();

  if (isPlayable(target)) addCandidate(allCandidates, target, target);

  const page = await fetchText(target, referer);
  extractCandidates(page.text, page.url || target).forEach(u => allCandidates.add(u));

  const scripts = extractScriptUrls(page.text, page.url || target);
  for (const script of scripts) {
    try {
      const js = await fetchText(script, page.url || target);
      extractCandidates(js.text, script).forEach(u => allCandidates.add(u));
    } catch (_) {}
  }

  const ordered = [...allCandidates].sort((a, b) => scoreCandidate(b) - scoreCandidate(a));
  const checked = [];
  for (const candidate of ordered.slice(0, 15)) {
    const check = await validatePlayable(candidate, page.url || target);
    checked.push({ url: candidate, ...check });
    if (check.ok) {
      return {
        ok: true,
        provider: 'LightOn Worker Resolver',
        url: candidate,
        pageUrl: page.url || target,
        mimeType: candidate.toLowerCase().includes('.mpd') ? 'application/dash+xml' :
          candidate.toLowerCase().includes('.m3u8') ? 'application/vnd.apple.mpegurl' : 'video/mp4',
        candidates: ordered.slice(0, 10),
        checked,
      };
    }
  }

  return {
    ok: false,
    iframeUrl: target,
    error: ordered.length
      ? 'وجدت روابط محتملة لكن لم أستطع تأكيد رابط قابل للتشغيل.'
      : 'لم أجد m3u8/mpd/mp4 في صفحة المصدر أو سكربتاتها. قد يحتاج المصدر JavaScript runtime أو حماية إضافية.',
    pageStatus: page.status,
    candidates: ordered.slice(0, 20),
    checked,
  };
}


async function proxyBinary(request) {
  const reqUrl = new URL(request.url);
  const target = String(reqUrl.searchParams.get('url') || '').trim();
  const referer = String(reqUrl.searchParams.get('referer') || '').trim();
  if (!isHttpUrl(target)) {
    return new Response('Missing or invalid url', { status: 400, headers: CORS });
  }
  const headers = {
    'accept': 'application/zip,application/octet-stream,text/vtt,text/plain,*/*',
    'accept-language': 'en-US,en;q=0.9,ar;q=0.8',
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome Safari',
  };
  if (referer && isHttpUrl(referer)) headers.referer = referer;
  const upstream = await fetch(target, { headers, redirect: 'follow' });
  const outHeaders = new Headers(CORS);
  outHeaders.set('cache-control', 'no-store');
  outHeaders.set('x-lighton-worker-version', LIGHTON_WORKER_VERSION);
  outHeaders.set('x-lighton-upstream-status', String(upstream.status));
  outHeaders.set('content-type', upstream.headers.get('content-type') || 'application/octet-stream');
  const cd = upstream.headers.get('content-disposition');
  if (cd) outHeaders.set('content-disposition', cd);
  if (!upstream.ok) {
    const text = await upstream.text().catch(() => '');
    return json({
      ok: false,
      proxy: true,
      error: 'subtitle upstream HTTP ' + upstream.status,
      upstreamStatus: upstream.status,
      upstreamContentType: upstream.headers.get('content-type') || '',
      url: target,
      preview: String(text || '').slice(0, 500),
      workerVersion: LIGHTON_WORKER_VERSION,
    }, 502);
  }
  return new Response(upstream.body, { status: upstream.status, headers: outHeaders });
}

export default {
  async fetch(request) {
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });

    try {
      const reqUrl = new URL(request.url);
      if (reqUrl.pathname === '/' || reqUrl.pathname === '/health') {
        return json({ ok: true, name: 'LightOn Resolver Worker', version: LIGHTON_WORKER_VERSION, endpoints: ['/resolve', '/proxy', '/health'] });
      }
      if (reqUrl.pathname === '/proxy') return await proxyBinary(request);
      let payload = {};
      if (request.method === 'POST') {
        payload = await request.json().catch(() => ({}));
      } else {
        payload = Object.fromEntries(reqUrl.searchParams.entries());
      }

      const target = String(payload.url || payload.playerUrl || payload.embedUrl || '').trim();
      const pageUrl = String(payload.pageUrl || target || '').trim();
      if (!isHttpUrl(target)) return json({ ok: false, error: 'Missing or invalid url' }, 400);

      const result = await resolveProvider(target, pageUrl);
      return json(result, result.ok ? 200 : 200);
    } catch (e) {
      return json({ ok: false, error: String(e && e.message ? e.message : e) }, 500);
    }
  },
};
