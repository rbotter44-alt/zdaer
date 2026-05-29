(function () {
  'use strict';

  const players = new Map();
  const FRAME_ALLOW = 'autoplay; fullscreen; encrypted-media; picture-in-picture; screen-wake-lock';
  const FRAME_CSP = "frame-src 'self' https://vidfast.pro https://www.vidfast.pro https://*.vidfast.pro https://player.videasy.net https://videasy.net https://*.videasy.net blob: data:; child-src 'self' https://vidfast.pro https://www.vidfast.pro https://*.vidfast.pro https://player.videasy.net https://videasy.net https://*.videasy.net blob: data:; navigate-to 'self' blob: data:;";

  function installParentAdGuard() {
    if (!document.querySelector('meta[http-equiv="Content-Security-Policy"]')) {
      const csp = document.createElement('meta');
      csp.httpEquiv = 'Content-Security-Policy';
      csp.content = FRAME_CSP;
      (document.head || document.documentElement).appendChild(csp);
    }

    if (window.__lightOnParentAdGuard) return;
    window.__lightOnParentAdGuard = true;

    const adDomains = [
      'pagead2', 'googlesyndication', 'doubleclick', 'googleads',
      'adservice.google', 'securepubads', 'pubmatic', 'rubiconproject',
      'adnxs', 'exoclick', 'juicyads', 'adsterra', 'propellerads',
      'popcash', 'popads', 'adcash', 'trafficjunky', 'hilltopads',
      'richpush', 'zeropark', 'revcontent', 'taboola', 'outbrain',
      'mgid', 'openx', 'criteo', 'fundingchoices', 'imasdk',
      'bvtpk', 'b7510', 'oyo4d', 'omoonsih', 'jnbhi', 'sourshaped',
      'tfnvuckb', 'waust', 'whacmoltibsay', 'rtmark',
      'popunder', 'clickunder', 'trafficshop', 'plugrush',
      'pyppo', 'pop.pro', 'casalemedia', 'dtscout', 'dtscdn',
      'mrktmtrcs', 'onaudience', 'histats',
      'crummydevioussucculent', 'yawncollaremotion', 'preferencenail',
      'newshinyd', 'bobapsoabauns', 'fleraprt', 'tzegilo',
      'affidavitheadfirstonward', 'deductpursue',
      'protrafficinspector', 'fundingchoicesmessages'
    ];

    function isAdUrl(value) {
      if (!value) return true;
      const s = String(value).toLowerCase();
      if (adDomains.some((d) => s.includes(d))) return true;
      return /(^|[\/_.-])(ads?|adserver|adservice|adunit|banner|interstitial|popup|popunder|clickunder)([\/_.-]|$)/i.test(s);
    }

    const originalOpen = window.open;
    window.open = function (url, target, features) {
      if (isAdUrl(url)) return null;
      return originalOpen ? originalOpen.apply(window, arguments) : null;
    };

    try {
      const originalAssign = window.location.assign.bind(window.location);
      window.location.assign = function (url) {
        if (isAdUrl(url)) return;
        return originalAssign(url);
      };
    } catch (_) {}

    try {
      const originalReplace = window.location.replace.bind(window.location);
      window.location.replace = function (url) {
        if (isAdUrl(url)) return;
        return originalReplace(url);
      };
    } catch (_) {}

    function blockAdLink(event) {
      let node = event.target;
      while (node && node !== document) {
        const href = node.href || (node.getAttribute && (node.getAttribute('href') || node.getAttribute('data-url') || node.getAttribute('data-link')));
        if (href && isAdUrl(href)) {
          event.preventDefault();
          event.stopImmediatePropagation();
          return false;
        }
        node = node.parentNode;
      }
      return true;
    }

    document.addEventListener('click', blockAdLink, true);
    document.addEventListener('auxclick', blockAdLink, true);
    document.addEventListener('securitypolicyviolation', function (event) {
      if (event && event.blockedURI && isAdUrl(event.blockedURI)) {
        try { event.preventDefault(); } catch (_) {}
      }
    }, true);
  }

  function post(id, payload) {
    try {
      const root = document.getElementById(id);
      if (!root) return;
      const detail = JSON.stringify(Object.assign({ source: 'lighton_web_player', id: id }, payload || {}));
      root.dispatchEvent(new CustomEvent('lighton-player-event', { detail: detail }));
    } catch (_) {}
  }

  function numericAspect(value) {
    if (typeof value === 'number' && isFinite(value) && value > 0.2 && value < 5) return value;
    const text = String(value || '').trim();
    const m = text.match(/^(\d+(?:\.\d+)?)\s*[:/]\s*(\d+(?:\.\d+)?)$/);
    if (m) {
      const a = Number(m[1]);
      const b = Number(m[2]);
      if (a > 0 && b > 0) return a / b;
    }
    const n = Number(text);
    if (isFinite(n) && n > 0.2 && n < 5) return n;
    return 16 / 9;
  }

  function fitIframe(iframe, fill, root, aspectRatio) {
    if (!iframe) return;
    const cw = Math.max(1, (root && root.clientWidth) || window.innerWidth || 1);
    const ch = Math.max(1, (root && root.clientHeight) || window.innerHeight || 1);
    const ar = numericAspect(aspectRatio);
    let w, h;

    if (fill) {
      if (cw / ch > ar) {
        w = cw;
        h = cw / ar;
      } else {
        h = ch;
        w = ch * ar;
      }
    } else {
      if (cw / ch > ar) {
        h = ch;
        w = ch * ar;
      } else {
        w = cw;
        h = cw / ar;
      }
    }

    iframe.style.position = 'absolute';
    iframe.style.left = '50%';
    iframe.style.top = '50%';
    iframe.style.width = Math.ceil(w) + 'px';
    iframe.style.height = Math.ceil(h) + 'px';
    iframe.style.transform = 'translate(-50%, -50%)';
    iframe.style.maxWidth = 'none';
    iframe.style.maxHeight = 'none';
    iframe.setAttribute('data-lighton-fit', fill ? 'fill-cover' : 'fit-contain');
  }

  function clearPlayer(id) {
    const old = players.get(id);
    if (!old) return;
    try { if (old.timer) clearTimeout(old.timer); } catch (_) {}
    try { if (old.resizeObserver) old.resizeObserver.disconnect(); } catch (_) {}
    try { if (old.resizeHandler) window.removeEventListener('resize', old.resizeHandler); } catch (_) {}
    players.delete(id);
  }

  function makeIframe(root, id, config) {
    installParentAdGuard();
    const iframe = document.createElement('iframe');
    iframe.src = String(config.url || '');
    iframe.allow = FRAME_ALLOW;
    iframe.allowFullscreen = true;
    iframe.referrerPolicy = 'origin';
    iframe.style.border = '0';
    iframe.style.background = '#000';

    let markedReady = false;
    function markReady() {
      if (markedReady) return;
      markedReady = true;
      post(id, { type: 'ready', mode: 'iframe' });
    }

    iframe.addEventListener('load', markReady);
    iframe.addEventListener('error', function () {
      post(id, { type: 'error', message: 'تعذّر تحميل مشغل VidFast الداخلي' });
    });

    root.innerHTML = '';
    root.appendChild(iframe);

    const record = {
      iframe: iframe,
      root: root,
      mode: 'iframe',
      fill: !!config.fill,
      aspectRatio: config.aspectRatio || '16:9'
    };

    const applyFit = function () { fitIframe(iframe, record.fill, root, record.aspectRatio); };
    record.resizeHandler = applyFit;
    try {
      if (window.ResizeObserver) {
        record.resizeObserver = new ResizeObserver(applyFit);
        record.resizeObserver.observe(root);
      } else {
        window.addEventListener('resize', applyFit);
      }
    } catch (_) {
      try { window.addEventListener('resize', applyFit); } catch (_) {}
    }
    applyFit();

    // بعض مشغلات iframe الخارجية لا تطلق load بشكل يمكن الاعتماد عليه دائمًا.
    // نخفي الدائرة بعد مهلة قصيرة ونترك واجهة VidFast الداخلية تظهر مباشرة.
    record.timer = setTimeout(markReady, 1600);
    players.set(id, record);
  }

  window.LightOnWebPlayer = {
    mount: function (id, config) {
      const root = document.getElementById(id);
      if (!root) return;
      clearPlayer(id);
      makeIframe(root, id, config || {});
    },
    dispose: function (id) {
      clearPlayer(id);
      const root = document.getElementById(id);
      if (root) root.innerHTML = '';
    },
    setFit: function (id, fill) {
      const rec = players.get(id);
      if (!rec || !rec.iframe) return;
      rec.fill = !!fill;
      fitIframe(rec.iframe, rec.fill, rec.root, rec.aspectRatio);
    }
  };
})();
