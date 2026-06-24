/* ============================================================================
   modifiedS — SPA frontend
   Vanilla JS, no framework. Hash-routed. Talks to the Bantu + Sua backend.

   Structure:
     1. State + helpers
     2. API client
     3. Auth
     4. Router
     5. Views (home, roadmaps, roadmapDetail, topic, lesson, notes, tutor,
              progress, profile, login)
     6. Boot
   ============================================================================ */

'use strict';

/* ─── 1. State + helpers ───────────────────────────────────────────── */

const state = {
  user: null,
  token: null,
  roadmaps: null,        // cached list
  roadmapCache: new Map(),
  progressCache: null,
};

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

function el(tag, attrs = {}, ...children) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') e.className = v;
    else if (k === 'html') e.innerHTML = v;
    else if (k.startsWith('on') && typeof v === 'function') {
      e.addEventListener(k.slice(2).toLowerCase(), v);
    } else if (k === 'dataset') {
      for (const [dk, dv] of Object.entries(v)) e.dataset[dk] = dv;
    } else if (v !== null && v !== undefined) {
      e.setAttribute(k, v);
    }
  }
  for (const c of children.flat()) {
    if (c == null || c === false) continue;
    e.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
  }
  return e;
}

function escapeHtml(s) {
  if (s == null) return '';
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** Render a tiny subset of markdown: headings, lists, bold, italic, code,
 *  blockquotes, paragraphs. Keeps the bundle minimal. */
function renderMarkdown(src) {
  if (!src) return '';
  const lines = String(src).split(/\r?\n/);
  const out = [];
  let inUl = false, inOl = false, inPre = false, preBuf = [];

  const inline = (s) =>
    s.replace(/`([^`]+)`/g, '<code>$1</code>')
     .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
     .replace(/\*([^*]+)\*/g, '<em>$1</em>')
     .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');

  const closeLists = () => {
    if (inUl) { out.push('</ul>'); inUl = false; }
    if (inOl) { out.push('</ol>'); inOl = false; }
  };

  for (const raw of lines) {
    const line = raw;
    if (line.startsWith('```')) {
      if (inPre) {
        out.push('<pre><code>' + escapeHtml(preBuf.join('\n')) + '</code></pre>');
        preBuf = [];
        inPre = false;
      } else {
        closeLists();
        inPre = true;
      }
      continue;
    }
    if (inPre) { preBuf.push(line); continue; }

    if (/^###\s+/.test(line))      { closeLists(); out.push('<h3>' + inline(line.slice(4)) + '</h3>'); }
    else if (/^##\s+/.test(line))  { closeLists(); out.push('<h2>' + inline(line.slice(3)) + '</h2>'); }
    else if (/^#\s+/.test(line))   { closeLists(); out.push('<h1>' + inline(line.slice(2)) + '</h1>'); }
    else if (/^>\s+/.test(line))   { closeLists(); out.push('<blockquote>' + inline(line.slice(2)) + '</blockquote>'); }
    else if (/^[-*]\s+/.test(line)) {
      if (!inUl) { closeLists(); out.push('<ul>'); inUl = true; }
      out.push('<li>' + inline(line.replace(/^[-*]\s+/, '')) + '</li>');
    }
    else if (/^\d+\.\s+/.test(line)) {
      if (!inOl) { closeLists(); out.push('<ol>'); inOl = true; }
      out.push('<li>' + inline(line.replace(/^\d+\.\s+/, '')) + '</li>');
    }
    else if (line.trim() === '')   { closeLists(); }
    else                           { closeLists(); out.push('<p>' + inline(line) + '</p>'); }
  }
  closeLists();
  if (inPre) out.push('<pre><code>' + escapeHtml(preBuf.join('\n')) + '</code></pre>');
  return out.join('\n');
}

function timeAgo(iso) {
  if (!iso) return '';
  const d = new Date(iso.replace(' ', 'T') + 'Z');
  if (isNaN(d)) return iso;
  const s = (Date.now() - d.getTime()) / 1000;
  if (s < 60) return 'just now';
  if (s < 3600) return Math.floor(s / 60) + 'm ago';
  if (s < 86400) return Math.floor(s / 3600) + 'h ago';
  if (s < 604800) return Math.floor(s / 86400) + 'd ago';
  return d.toLocaleDateString();
}

function initials(name) {
  if (!name) return '?';
  return name.trim().slice(0, 2).toUpperCase();
}

function diffColor(diff) {
  return { beginner: 'beg', intermediate: 'int', advanced: 'adv' }[diff] || '';
}

function toast(msg, kind = '') {
  const t = $('#toast');
  t.textContent = msg;
  t.className = 'toast show ' + kind;
  clearTimeout(toast._t);
  toast._t = setTimeout(() => { t.className = 'toast ' + kind; }, 3000);
}

/* ─── 2. API client ────────────────────────────────────────────────── */

const api = {
  async req(path, { method = 'GET', body, auth = false } = {}) {
    const headers = { 'Content-Type': 'application/json' };
    if (auth && state.token) headers['Authorization'] = 'Bearer ' + state.token;
    const opts = { method, headers };
    if (body !== undefined) opts.body = JSON.stringify(body);
    let r;
    try {
      r = await fetch('/api' + path, opts);
    } catch (e) {
      throw new Error('Network error: ' + e.message);
    }
    let j = null;
    try { j = await r.json(); } catch (_) { /* maybe empty body */ }
    if (!r.ok) {
      const msg = (j && (j.error || j.message)) || ('HTTP ' + r.status);
      const err = new Error(msg);
      err.status = r.status;
      err.body = j;
      throw err;
    }
    return j;
  },

  // Auth
  register: (b) => api.req('/auth/register', { method: 'POST', body: b }),
  login:    (b) => api.req('/auth/login',    { method: 'POST', body: b }),
  me:       ()  => api.req('/auth/me', { auth: true }),

  // Roadmaps
  roadmaps:        ()      => api.req('/roadmaps'),
  roadmap:         (slug)  => api.req('/roadmaps/' + slug),
  topics:          (slug)  => api.req('/roadmaps/' + slug + '/topics'),
  items:           (slug, tid) => api.req('/roadmaps/' + slug + '/topics/' + tid + '/items'),

  // Progress
  progress:        ()         => api.req('/progress', { auth: true }),
  setProgress:     (itemId, status) => api.req('/progress/' + itemId, { method: 'POST', auth: true, body: { status } }),
  removeProgress:  (itemId)   => api.req('/progress/' + itemId, { method: 'DELETE', auth: true }),

  // Notes
  notes:           ()         => api.req('/notes', { auth: true }),
  createNote:      (b)        => api.req('/notes', { method: 'POST', auth: true, body: b }),
  note:            (id)       => api.req('/notes/' + id, { auth: true }),
  updateNote:      (id, b)    => api.req('/notes/' + id, { method: 'PUT', auth: true, body: b }),
  deleteNote:      (id)       => api.req('/notes/' + id, { method: 'DELETE', auth: true }),

  // Users
  users:           ()         => api.req('/users', { auth: true }),
  updateUser:      (id, b)    => api.req('/users/' + id, { method: 'PUT', auth: true, body: b }),

  // AI
  tutor:           (msg)     => api.req('/ai/tutor', { method: 'POST', body: { message: msg } }),
  quiz:            (topic, count) => api.req('/ai/quiz', { method: 'POST', body: { topic, count } }),
};

/* ─── 3. Auth ──────────────────────────────────────────────────────── */

function loadAuth() {
  state.token = localStorage.getItem('ms_token');
  try {
    state.user = JSON.parse(localStorage.getItem('ms_user') || 'null');
  } catch (_) { state.user = null; }
}

function saveAuth(token, user) {
  state.token = token;
  state.user = user;
  localStorage.setItem('ms_token', token);
  localStorage.setItem('ms_user', JSON.stringify(user));
  renderNavActions();
}

function clearAuth() {
  state.token = null;
  state.user = null;
  localStorage.removeItem('ms_token');
  localStorage.removeItem('ms_user');
  renderNavActions();
}

async function refreshMe() {
  if (!state.token) return;
  try {
    const j = await api.me();
    if (j.user) {
      state.user = j.user;
      localStorage.setItem('ms_user', JSON.stringify(j.user));
      renderNavActions();
    }
  } catch (e) {
    if (e.status === 401) clearAuth();
  }
}

function requireAuth() {
  if (!state.token) {
    location.hash = '#/login';
    return false;
  }
  return true;
}

/* ─── 4. Router ────────────────────────────────────────────────────── */

const routes = [
  { path: /^\/?$/,                  view: viewHome },
  { path: /^\/login\/?$/,           view: viewLogin },
  { path: /^\/register\/?$/,        view: viewLogin },
  { path: /^\/roadmaps\/?$/,        view: viewRoadmaps },
  { path: /^\/roadmap\/([^/]+)\/?$/,                view: viewRoadmapDetail },
  { path: /^\/roadmap\/([^/]+)\/topic\/(\d+)\/?$/,  view: viewTopic },
  { path: /^\/roadmap\/([^/]+)\/topic\/(\d+)\/item\/(\d+)\/?$/, view: viewLesson },
  { path: /^\/notes\/?$/,           view: viewNotes },
  { path: /^\/notes\/new\/?$/,      view: viewNoteEdit },
  { path: /^\/notes\/(\d+)\/edit\/?$/, view: viewNoteEdit },
  { path: /^\/tutor\/?$/,           view: viewTutor },
  { path: /^\/progress\/?$/,        view: viewProgress },
  { path: /^\/profile\/?$/,         view: viewProfile },
];

function currentPath() {
  let h = location.hash || '#/';
  if (h.startsWith('#')) h = h.slice(1);
  if (!h.startsWith('/')) h = '/' + h;
  return h;
}

function navigate(path) {
  if (!path.startsWith('/')) path = '/' + path;
  location.hash = '#' + path;
}

async function router() {
  const path = currentPath();
  // Active nav link
  $$('.nav-links a, .bottomnav a').forEach(a => {
    a.classList.toggle('active', a.getAttribute('href') === '#' + path ||
                                 (path === '/' && a.getAttribute('href') === '#/roadmaps'));
  });

  // Find matching route
  let match = null, view = null;
  for (const r of routes) {
    const m = path.match(r.path);
    if (m) { match = m; view = r.view; break; }
  }

  const root = $('#view');
  root.className = 'view';
  root.innerHTML = '<div class="loading-skeleton"><span class="spinner"></span>Loading…</div>';

  if (!view) {
    root.innerHTML = '';
    root.appendChild(view404());
    return;
  }

  try {
    await view(root, ...(match.slice(1)));
  } catch (e) {
    console.error(e);
    root.innerHTML = '';
    root.appendChild(viewError(e));
  }
  window.scrollTo({ top: 0, behavior: 'instant' });
}

/* ─── 5. Views ─────────────────────────────────────────────────────── */

function view404() {
  return el('div', { class: 'empty' },
    el('div', { class: 'empty-icon' }, '🧭'),
    el('h3', {}, 'Page not found'),
    el('p', {}, 'The route you tried doesn’t exist.'),
    el('a', { class: 'btn', href: '#/' }, 'Back home'),
  );
}

function viewError(e) {
  const needLogin = e.status === 401;
  return el('div', { class: 'empty' },
    el('div', { class: 'empty-icon' }, needLogin ? '🔒' : '⚠️'),
    el('h3', {}, needLogin ? 'Login required' : 'Something went wrong'),
    el('p', {}, e.message || 'Unknown error'),
    needLogin
      ? el('a', { class: 'btn', href: '#/login' }, 'Login')
      : el('a', { class: 'btn', href: '#/' }, 'Back home'),
  );
}

/* ── Home ─────────────────────────────────────────────────────────── */

async function viewHome(root) {
  // Ensure we have roadmaps cached for the featured grid
  if (!state.roadmaps) {
    const j = await api.roadmaps();
    state.roadmaps = j.roadmaps || [];
  }
  const featured = state.roadmaps.filter(r => r.featured).slice(0, 6);
  const totalTopics = state.roadmaps.reduce((s, r) => s + (r.topic_count || 0), 0);

  root.innerHTML = '';
  root.appendChild(
    el('section', { class: 'hero' },
      el('h1', {}, 'Learn anything, step by step.'),
      el('p', { class: 'lead' },
        'modifiedS is a learning platform with structured roadmaps, AI tutor, ' +
        'study notes and progress tracking — built on the Bantu programming language.'),
      el('div', { class: 'hero-cta' },
        el('a', { class: 'btn btn-lg', href: '#/roadmaps' }, 'Browse roadmaps'),
        el('a', { class: 'btn btn-secondary btn-lg', href: '#/tutor' }, 'Ask the AI tutor'),
      ),
    )
  );

  // Stats
  root.appendChild(
    el('div', { class: 'grid grid-3 mb-3' },
      el('div', { class: 'stat-card' },
        el('div', { class: 'stat-value' }, String(state.roadmaps.length)),
        el('div', { class: 'stat-label' }, 'Roadmaps'),
      ),
      el('div', { class: 'stat-card' },
        el('div', { class: 'stat-value' }, String(totalTopics)),
        el('div', { class: 'stat-label' }, 'Topics'),
      ),
      el('div', { class: 'stat-card' },
        el('div', { class: 'stat-value' }, '100%'),
        el('div', { class: 'stat-label' }, 'Free forever'),
      ),
    )
  );

  // Featured
  if (featured.length) {
    root.appendChild(
      el('div', { class: 'section-head mt-3' },
        el('div', {},
          el('h2', {}, 'Featured roadmaps'),
          el('p', { class: 'sub' }, 'Hand-picked learning paths to get you started.'),
        ),
        el('a', { class: 'btn btn-ghost', href: '#/roadmaps' }, 'See all →'),
      )
    );
    root.appendChild(
      el('div', { class: 'grid grid-3' }, ...featured.map(rmCard))
    );
  }

  // What you can do
  root.appendChild(
    el('div', { class: 'section-head mt-3' },
      el('h2', {}, 'What you can do here')
    )
  );
  root.appendChild(
    el('div', { class: 'grid grid-3' },
      featCard('📚', 'Follow roadmaps', 'Pick from ' + state.roadmaps.length + ' structured paths across dev, math, science and languages.'),
      featCard('🤖', 'Ask the AI tutor', 'Get instant explanations on any topic. Rule-based, runs offline, no API key.'),
      featCard('📝', 'Take notes', 'Attach notes to lessons or keep them standalone. Edit and review anytime.'),
      featCard('📈', 'Track progress', 'Mark lessons as in-progress or done. See your streak and completion stats.'),
      featCard('🧪', 'Quiz yourself', 'Generate short quizzes from any topic to test your understanding.'),
      featCard('🔐', 'Own your data', 'Your account, notes and progress live in a SQLite file you control.'),
    )
  );

  // Footer
  root.appendChild(footerEl());
}

function featCard(icon, title, body) {
  return el('div', { class: 'card' },
    el('div', { style: 'font-size:28px;margin-bottom:10px' }, icon),
    el('div', { class: 'card-title' }, title),
    el('div', { class: 'card-sub' }, body),
  );
}

function rmCard(r) {
  return el('a', {
    class: 'card hoverable rm-card',
    href: '#/roadmap/' + r.slug,
    style: '--rm-color:' + ({
      rose: '#f43f5e', pink: '#ec4899', violet: '#8b5cf6', indigo: '#6366f1',
      blue: '#3b82f6', sky: '#0ea5e9', cyan: '#06b6d4', teal: '#14b8a6',
      green: '#10b981', emerald: '#10b981', lime: '#84cc16', yellow: '#eab308',
      amber: '#f59e0b', orange: '#f97316', red: '#ef4444', slate: '#64748b',
    }[r.color] || '#6366f1'),
  },
    el('div', { class: 'rm-icon' }, r.icon || '📘'),
    el('div', { class: 'rm-title' }, r.title),
    el('div', { class: 'rm-desc' }, r.description || ''),
    el('div', { class: 'rm-meta' },
      el('span', { class: 'badge ' + diffColor(r.difficulty) }, r.difficulty || ''),
      el('span', {}, (r.topic_count || 0) + ' topics'),
    ),
  );
}

/* ── Roadmaps browse ──────────────────────────────────────────────── */

async function viewRoadmaps(root) {
  if (!state.roadmaps) {
    const j = await api.roadmaps();
    state.roadmaps = j.roadmaps || [];
  }
  const all = state.roadmaps;

  const cats = Array.from(new Set(all.map(r => r.category).filter(Boolean))).sort();

  root.innerHTML = '';
  root.appendChild(
    el('div', { class: 'section-head' },
      el('div', {},
        el('h2', {}, 'All roadmaps'),
        el('p', { class: 'sub' }, all.length + ' structured learning paths across ' + cats.length + ' categories.'),
      ),
    )
  );

  // Filter bar
  const searchInput = el('input', {
    class: 'search-input',
    type: 'search',
    placeholder: 'Search roadmaps…',
    oninput: () => applyFilter(),
  });
  const chipBar = el('div', { class: 'flex gap-1 wrap' },
    el('button', {
      class: 'chip active',
      onclick: (e) => { setActiveChip(e.target); applyFilter(); },
    }, 'All'),
    ...cats.map(c => el('button', {
      class: 'chip',
      onclick: (e) => { setActiveChip(e.target); applyFilter(); },
    }, c)),
  );
  root.appendChild(el('div', { class: 'filter-bar' }, searchInput, chipBar));

  const grid = el('div', { class: 'grid grid-3' });
  root.appendChild(grid);

  function setActiveChip(b) {
    chipBar.querySelectorAll('.chip').forEach(c => c.classList.remove('active'));
    b.classList.add('active');
  }
  function applyFilter() {
    const q = searchInput.value.trim().toLowerCase();
    const activeCat = chipBar.querySelector('.chip.active')?.textContent || 'All';
    const filtered = all.filter(r => {
      const matchesQ = !q || (r.title || '').toLowerCase().includes(q) || (r.description || '').toLowerCase().includes(q);
      const matchesC = activeCat === 'All' || r.category === activeCat;
      return matchesQ && matchesC;
    });
    grid.innerHTML = '';
    filtered.forEach(r => grid.appendChild(rmCard(r)));
    if (!filtered.length) {
      grid.appendChild(el('div', { class: 'empty', style: 'grid-column:1/-1' },
        el('div', { class: 'empty-icon' }, '🔍'),
        el('h3', {}, 'No roadmaps match'),
        el('p', {}, 'Try a different search or category.'),
      ));
    }
  }
  applyFilter();
}

/* ── Roadmap detail ───────────────────────────────────────────────── */

async function viewRoadmapDetail(root, slug) {
  // Try cache first for instant paint
  let r = state.roadmapCache.get(slug);
  if (!r) {
    const j = await api.roadmap(slug);
    r = j.roadmap;
    state.roadmapCache.set(slug, r);
  }
  // Always fetch fresh topics in background
  let topics = [];
  try {
    const tj = await api.topics(slug);
    topics = tj.topics || [];
  } catch (_) { /* ignore */ }

  // Progress (if logged in)
  let progressMap = new Map();
  if (state.token) {
    try {
      const pj = await api.progress();
      (pj.progress || []).forEach(p => progressMap.set(String(p.item_id), p.status));
    } catch (_) {}
  }

  const colorVar = ({
    rose: '#f43f5e', pink: '#ec4899', violet: '#8b5cf6', indigo: '#6366f1',
    blue: '#3b82f6', sky: '#0ea5e9', cyan: '#06b6d4', teal: '#14b8a6',
    green: '#10b981', emerald: '#10b981', lime: '#84cc16', yellow: '#eab308',
    amber: '#f59e0b', orange: '#f97316', red: '#ef4444', slate: '#64748b',
  }[r.color] || '#6366f1');

  root.innerHTML = '';

  // Breadcrumb
  root.appendChild(breadcrumb('Roadmaps', '#/roadmaps', r.title));

  // Hero
  root.appendChild(
    el('div', { class: 'rm-hero', style: '--rm-color:' + colorVar },
      el('div', { class: 'rm-hero-icon' }, r.icon || '📘'),
      el('h1', {}, r.title),
      el('p', { class: 'lead' }, r.description || ''),
      el('div', { class: 'flex gap-1 wrap' },
        el('span', { class: 'badge ' + diffColor(r.difficulty) }, r.difficulty || ''),
        el('span', { class: 'badge brand' }, r.category || 'general'),
        el('span', { class: 'badge' }, (r.topic_count || topics.length || 0) + ' topics'),
      ),
    )
  );

  // Topics list
  if (!topics.length) {
    root.appendChild(
      el('div', { class: 'empty' },
        el('div', { class: 'empty-icon' }, '🚧'),
        el('h3', {}, 'No topics yet'),
        el('p', {}, 'This roadmap hasn’t been populated with topics yet.'),
      )
    );
    return;
  }

  root.appendChild(
    el('div', { class: 'section-head' },
      el('h2', {}, 'Topics'),
      el('p', { class: 'sub' }, topics.length + ' topic' + (topics.length === 1 ? '' : 's') + ' in this roadmap'),
    )
  );

  const list = el('div', {});
  topics.forEach((t, i) => {
    // Count items done in this topic — we don’t have that without fetching, so just show ordinal + title
    list.appendChild(
      el('a', {
        class: 'topic-row',
        href: '#/roadmap/' + slug + '/topic/' + t.id,
      },
        el('div', { class: 'ord' }, String(i + 1)),
        el('div', { class: 'flex-1' },
          el('div', { class: 'title' }, t.title),
          el('div', { class: 'meta' }, 'Topic ' + (i + 1) + ' · ' + (t.slug || '')),
        ),
        el('span', { class: 'text-muted' }, '→'),
      )
    );
  });
  root.appendChild(list);
  root.appendChild(footerEl());
}

/* ── Topic view (lists items) ─────────────────────────────────────── */

async function viewTopic(root, slug, topicId) {
  let r = state.roadmapCache.get(slug);
  if (!r) {
    try {
      const j = await api.roadmap(slug);
      r = j.roadmap;
      state.roadmapCache.set(slug, r);
    } catch (_) { r = { title: 'Roadmap', icon: '📘' }; }
  }
  let items = [];
  try {
    const j = await api.items(slug, topicId);
    items = j.items || [];
  } catch (e) {
    if (e.status === 404) {
      root.innerHTML = '';
      root.appendChild(viewError(e));
      return;
    }
    throw e;
  }

  // Progress map
  let progressMap = new Map();
  if (state.token) {
    try {
      const pj = await api.progress();
      (pj.progress || []).forEach(p => progressMap.set(String(p.item_id), p.status));
    } catch (_) {}
  }

  root.innerHTML = '';
  root.appendChild(breadcrumb('Roadmaps', '#/roadmaps', r.title, '#/roadmap/' + slug, 'Topic'));

  root.appendChild(
    el('div', { class: 'card mb-3' },
      el('h1', { style: 'font-size:24px;margin-bottom:6px' }, items[0]?.title ? items[0].title : 'Topic'),
      el('p', { class: 'text-muted' }, items.length + ' lesson' + (items.length === 1 ? '' : 's') + ' in this topic.'),
    )
  );

  if (!items.length) {
    root.appendChild(
      el('div', { class: 'empty' },
        el('div', { class: 'empty-icon' }, '📭'),
        el('h3', {}, 'No lessons here yet'),
        el('p', {}, 'This topic hasn’t been populated yet.'),
      )
    );
    return;
  }

  const list = el('div', {});
  items.forEach((it, i) => {
    const status = progressMap.get(String(it.id));
    list.appendChild(
      el('a', {
        class: 'topic-row' + (status === 'done' ? ' done' : ''),
        href: '#/roadmap/' + slug + '/topic/' + topicId + '/item/' + it.id,
      },
        el('div', { class: 'ord' }, status === 'done' ? '✓' : String(i + 1)),
        el('div', { class: 'flex-1' },
          el('div', { class: 'title' }, it.title),
          el('div', { class: 'meta' },
            it.kind || 'lesson',
            status ? ' · ' + status : '',
          ),
        ),
        el('span', { class: 'text-muted' }, '→'),
      )
    );
  });
  root.appendChild(list);
}

/* ── Lesson view ──────────────────────────────────────────────────── */

async function viewLesson(root, slug, topicId, itemId) {
  let r = state.roadmapCache.get(slug);
  if (!r) {
    try {
      const j = await api.roadmap(slug);
      r = j.roadmap;
      state.roadmapCache.set(slug, r);
    } catch (_) { r = { title: 'Roadmap', icon: '📘' }; }
  }
  let items = [];
  try {
    const j = await api.items(slug, topicId);
    items = j.items || [];
  } catch (e) {
    root.innerHTML = '';
    root.appendChild(viewError(e));
    return;
  }
  const item = items.find(i => String(i.id) === String(itemId));
  if (!item) {
    root.innerHTML = '';
    root.appendChild(viewError({ message: 'Lesson not found', status: 404 }));
    return;
  }
  const idx = items.findIndex(i => String(i.id) === String(itemId));
  const prev = items[idx - 1];
  const next = items[idx + 1];

  // Existing progress
  let status = null;
  if (state.token) {
    try {
      const pj = await api.progress();
      const found = (pj.progress || []).find(p => String(p.item_id) === String(itemId));
      status = found?.status || null;
    } catch (_) {}
  }

  root.innerHTML = '';
  root.appendChild(breadcrumb('Roadmaps', '#/roadmaps', r.title, '#/roadmap/' + slug, 'Lesson'));

  const lessonCard = el('article', { class: 'lesson' },
    el('h1', {}, item.title),
    el('div', { class: 'lesson-meta' },
      (item.kind || 'lesson') + ' · topic ' + topicId + ' · lesson ' + (idx + 1) + ' of ' + items.length,
    ),
    el('div', { class: 'lesson-body', html: renderMarkdown(item.content || '*No content yet.*') }),
  );

  // Actions
  const actions = el('div', { class: 'lesson-actions' });
  if (state.token) {
    const statusBtn = el('button', {
      class: 'btn ' + (status === 'done' ? 'btn-secondary' : ''),
      onclick: async () => {
        try {
          const newStatus = status === 'done' ? 'in-progress' : 'done';
          await api.setProgress(itemId, newStatus);
          status = newStatus;
          toast(newStatus === 'done' ? 'Marked as done 🎉' : 'Marked in-progress', 'success');
          // Re-render action buttons
          lessonCard.contains(actions) && lessonCard.removeChild(actions);
          lessonCard.appendChild(buildLessonActions());
        } catch (e) { toast(e.message, 'error'); }
      },
    }, status === 'done' ? '✓ Done — click to revisit' : 'Mark as done');
    actions.appendChild(statusBtn);

    actions.appendChild(
      el('button', {
        class: 'btn btn-secondary',
        onclick: () => navigate('/notes/new?item=' + itemId + '&title=' + encodeURIComponent(item.title)),
      }, '📝 Take a note'),
    );
  } else {
    actions.appendChild(
      el('a', { class: 'btn btn-secondary', href: '#/login' }, 'Login to track progress'),
    );
  }
  // Prev / next
  if (prev) actions.appendChild(el('a', { class: 'btn btn-ghost', href: '#/roadmap/' + slug + '/topic/' + topicId + '/item/' + prev.id }, '← Previous'));
  if (next) actions.appendChild(el('a', { class: 'btn btn-ghost', href: '#/roadmap/' + slug + '/topic/' + topicId + '/item/' + next.id }, 'Next →'));
  lessonCard.appendChild(actions);

  function buildLessonActions() {
    // Same as above, rebuilt
    const a = el('div', { class: 'lesson-actions' });
    if (state.token) {
      a.appendChild(el('button', {
        class: 'btn ' + (status === 'done' ? 'btn-secondary' : ''),
        onclick: async () => {
          try {
            const ns = status === 'done' ? 'in-progress' : 'done';
            await api.setProgress(itemId, ns);
            status = ns;
            toast(ns === 'done' ? 'Marked as done 🎉' : 'Marked in-progress', 'success');
            lessonCard.removeChild(a);
            lessonCard.appendChild(buildLessonActions());
          } catch (e) { toast(e.message, 'error'); }
        },
      }, status === 'done' ? '✓ Done — click to revisit' : 'Mark as done'));
      a.appendChild(el('button', {
        class: 'btn btn-secondary',
        onclick: () => navigate('/notes/new?item=' + itemId + '&title=' + encodeURIComponent(item.title)),
      }, '📝 Take a note'));
    } else {
      a.appendChild(el('a', { class: 'btn btn-secondary', href: '#/login' }, 'Login to track progress'));
    }
    if (prev) a.appendChild(el('a', { class: 'btn btn-ghost', href: '#/roadmap/' + slug + '/topic/' + topicId + '/item/' + prev.id }, '← Previous'));
    if (next) a.appendChild(el('a', { class: 'btn btn-ghost', href: '#/roadmap/' + slug + '/topic/' + topicId + '/item/' + next.id }, 'Next →'));
    return a;
  }

  root.appendChild(lessonCard);
  root.appendChild(footerEl());
}

/* ── Notes ────────────────────────────────────────────────────────── */

async function viewNotes(root) {
  if (!requireAuth()) return;

  let notes = [];
  try {
    const j = await api.notes();
    notes = j.notes || [];
  } catch (e) {
    root.innerHTML = '';
    root.appendChild(viewError(e));
    return;
  }

  root.innerHTML = '';
  root.appendChild(
    el('div', { class: 'section-head' },
      el('div', {},
        el('h2', {}, 'My notes'),
        el('p', { class: 'sub' }, notes.length + ' note' + (notes.length === 1 ? '' : 's')),
      ),
      el('a', { class: 'btn', href: '#/notes/new' }, '+ New note'),
    )
  );

  if (!notes.length) {
    root.appendChild(
      el('div', { class: 'empty' },
        el('div', { class: 'empty-icon' }, '📝'),
        el('h3', {}, 'No notes yet'),
        el('p', {}, 'Take notes while learning or jot down standalone ideas.'),
        el('a', { class: 'btn', href: '#/notes/new' }, 'Write your first note'),
      )
    );
    return;
  }

  const grid = el('div', { class: 'grid grid-3' });
  notes.forEach(n => {
    grid.appendChild(
      el('div', { class: 'note-card' },
        el('div', { class: 'note-title' }, n.title || 'Untitled'),
        el('div', { class: 'note-body' }, n.body || ''),
        el('div', { class: 'note-meta' },
          el('span', {}, timeAgo(n.updated_at || n.created_at)),
          el('div', { class: 'note-actions' },
            el('a', { class: 'btn btn-ghost btn-sm', href: '#/notes/' + n.id + '/edit' }, 'Edit'),
            el('button', {
              class: 'btn btn-ghost btn-sm',
              onclick: async () => {
                if (!confirm('Delete this note?')) return;
                try {
                  await api.deleteNote(n.id);
                  toast('Note deleted', 'success');
                  viewNotes(root);
                } catch (e) { toast(e.message, 'error'); }
              },
            }, 'Delete'),
          ),
        ),
      )
    );
  });
  root.appendChild(grid);
}

async function viewNoteEdit(root, noteId) {
  if (!requireAuth()) return;

  // Parse query from hash (for ?item=…&title=…)
  const queryStr = location.hash.split('?')[1] || '';
  const params = new URLSearchParams(queryStr);
  const presetItemId = params.get('item');
  const presetTitle  = params.get('title') || '';

  let note = null;
  if (noteId) {
    try {
      const j = await api.note(noteId);
      note = j.note;
    } catch (e) {
      root.innerHTML = '';
      root.appendChild(viewError(e));
      return;
    }
  }

  root.innerHTML = '';
  root.appendChild(breadcrumb('Notes', '#/notes', note ? 'Edit' : 'New'));

  const card = el('div', { class: 'card' },
    el('h2', { style: 'margin-bottom:16px' }, note ? 'Edit note' : 'New note'),
  );

  const titleInput = el('input', { type: 'text', placeholder: 'Title', value: note?.title || presetTitle });
  const bodyInput  = el('textarea', { placeholder: 'Write your note…' }, note?.body || '');
  card.appendChild(el('div', { class: 'field' }, el('label', {}, 'Title'), titleInput));
  card.appendChild(el('div', { class: 'field' }, el('label', {}, 'Body'), bodyInput));

  const actions = el('div', { class: 'flex gap-2', style: 'justify-content:flex-end;margin-top:8px' });
  actions.appendChild(el('a', { class: 'btn btn-ghost', href: '#/notes' }, 'Cancel'));
  const saveBtn = el('button', { class: 'btn' }, 'Save');
  saveBtn.onclick = async () => {
    saveBtn.disabled = true;
    saveBtn.textContent = 'Saving…';
    try {
      const body = bodyInput.value.trim();
      const title = titleInput.value.trim();
      if (!body) { toast('Note body is empty', 'error'); return; }
      if (note) {
        await api.updateNote(note.id, { title, body });
        toast('Note updated', 'success');
      } else {
        await api.createNote({ title, body, itemId: presetItemId ? Number(presetItemId) : null });
        toast('Note created', 'success');
      }
      navigate('/notes');
    } catch (e) {
      toast(e.message, 'error');
    } finally {
      saveBtn.disabled = false;
      saveBtn.textContent = 'Save';
    }
  };
  actions.appendChild(saveBtn);
  card.appendChild(actions);

  root.appendChild(card);
}

/* ── AI Tutor ─────────────────────────────────────────────────────── */

async function viewTutor(root) {
  root.innerHTML = '';

  root.appendChild(
    el('div', { class: 'section-head' },
      el('div', {},
        el('h2', {}, 'AI Tutor'),
        el('p', { class: 'sub' }, 'Ask anything. Rule-based tutor running on Bantu — no API key, no quota.'),
      ),
    )
  );

  const messages = el('div', { class: 'chat-messages' });
  messages.appendChild(
    el('div', { class: 'msg bot' },
      el('div', { class: 'role' }, 'Tutor'),
      'Hi! I’m your AI tutor. Ask me about programming, math, science, or learning roadmaps. ' +
      'Try “how do I learn react?” or “explain recursion”.'
    )
  );

  const input = el('textarea', { placeholder: 'Ask a question…', rows: 1 });
  const sendBtn = el('button', { class: 'btn' }, 'Send');

  async function send() {
    const text = input.value.trim();
    if (!text) return;
    input.value = '';
    input.style.height = 'auto';
    messages.appendChild(
      el('div', { class: 'msg user' },
        el('div', { class: 'role' }, 'You'),
        text,
      )
    );
    messages.scrollTop = messages.scrollHeight;

    const thinking = el('div', { class: 'msg bot' },
      el('div', { class: 'role' }, 'Tutor'),
      'Thinking…',
    );
    messages.appendChild(thinking);
    messages.scrollTop = messages.scrollHeight;

    try {
      const j = await api.tutor(text);
      thinking.removeChild(thinking.lastChild);
      thinking.appendChild(document.createTextNode(j.reply || '(no reply)'));
    } catch (e) {
      thinking.removeChild(thinking.lastChild);
      thinking.appendChild(document.createTextNode('⚠️ ' + e.message));
    }
    messages.scrollTop = messages.scrollHeight;
  }

  sendBtn.onclick = send;
  input.onkeydown = (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      send();
    }
  };
  input.oninput = () => {
    input.style.height = 'auto';
    input.style.height = Math.min(input.scrollHeight, 120) + 'px';
  };

  const chatWindow = el('div', { class: 'chat-window' },
    el('div', { class: 'chat-header' }, '💬 Chat'),
    messages,
    el('div', { class: 'chat-input' }, input, sendBtn),
  );

  // Sidebar with suggestions + quiz
  const suggestList = el('div', { class: 'suggest-list' });
  ['How do I learn react?',
   'Explain recursion like I’m 5',
   'What’s the difference between SQL and NoSQL?',
   'How do I prepare for Form 4 math exams?',
   'Teach me about variables in Python',
  ].forEach(q => suggestList.appendChild(
    el('div', { class: 'suggest-item', onclick: () => { input.value = q; send(); } }, q)
  ));

  // Mini quiz widget
  const quizTopicInput = el('input', {
    class: 'search-input',
    placeholder: 'Topic (optional)',
    style: 'margin-bottom:8px',
  });
  const quizBtn = el('button', { class: 'btn btn-secondary btn-block' }, 'Generate quiz');
  const quizOut = el('div', { style: 'margin-top:10px' });
  quizBtn.onclick = async () => {
    quizBtn.disabled = true;
    quizBtn.textContent = 'Generating…';
    quizOut.innerHTML = '';
    try {
      const j = await api.quiz(quizTopicInput.value.trim() || null, 3);
      (j.quiz || []).forEach((q, i) => {
        const block = el('div', { class: 'card', style: 'padding:14px;margin-bottom:8px' },
          el('div', { style: 'font-weight:600;margin-bottom:6px' }, (i + 1) + '. ' + q.question),
        );
        (q.options || []).forEach((opt, oi) => {
          const isCorrect = q.answer === oi || q.answer === opt;
          block.appendChild(
            el('div', {
              class: 'chip',
              style: 'margin:3px;cursor:default;white-space:normal',
              onclick: (e) => {
                if (isCorrect) {
                  e.target.style.background = 'var(--ok)';
                  e.target.style.color = '#fff';
                } else {
                  e.target.style.background = 'var(--err)';
                  e.target.style.color = '#fff';
                }
              },
            }, String.fromCharCode(65 + oi) + '. ' + opt),
          );
        });
        quizOut.appendChild(block);
      });
    } catch (e) {
      quizOut.appendChild(el('div', { class: 'text-muted' }, '⚠️ ' + e.message));
    } finally {
      quizBtn.disabled = false;
      quizBtn.textContent = 'Generate quiz';
    }
  };

  const sidebar = el('aside', { class: 'tutor-sidebar card' },
    el('h3', {}, 'Try asking'),
    suggestList,
    el('h3', {}, 'Quick quiz'),
    quizTopicInput,
    quizBtn,
    quizOut,
  );

  root.appendChild(el('div', { class: 'tutor-wrap' }, chatWindow, sidebar));
}

/* ── Progress dashboard ───────────────────────────────────────────── */

async function viewProgress(root) {
  if (!requireAuth()) return;

  let progress = [];
  try {
    const j = await api.progress();
    progress = j.progress || [];
  } catch (e) {
    root.innerHTML = '';
    root.appendChild(viewError(e));
    return;
  }

  // Also load roadmaps so we can group progress by roadmap
  if (!state.roadmaps) {
    try {
      const rj = await api.roadmaps();
      state.roadmaps = rj.roadmaps || [];
    } catch (_) {}
  }

  root.innerHTML = '';
  root.appendChild(
    el('div', { class: 'section-head' },
      el('div', {},
        el('h2', {}, 'My progress'),
        el('p', { class: 'sub' }, 'Everything you’ve learned so far.'),
      ),
    )
  );

  const done = progress.filter(p => p.status === 'done').length;
  const inProg = progress.filter(p => p.status === 'in-progress').length;
  const pending = progress.filter(p => p.status === 'pending').length;

  root.appendChild(
    el('div', { class: 'grid grid-3 mb-3' },
      el('div', { class: 'stat-card' },
        el('div', { class: 'stat-value', style: 'color:var(--ok)' }, String(done)),
        el('div', { class: 'stat-label' }, 'Completed'),
      ),
      el('div', { class: 'stat-card' },
        el('div', { class: 'stat-value', style: 'color:var(--warn)' }, String(inProg)),
        el('div', { class: 'stat-label' }, 'In progress'),
      ),
      el('div', { class: 'stat-card' },
        el('div', { class: 'stat-value' }, String(pending)),
        el('div', { class: 'stat-label' }, 'Pending'),
      ),
    )
  );

  if (!progress.length) {
    root.appendChild(
      el('div', { class: 'empty' },
        el('div', { class: 'empty-icon' }, '📈'),
        el('h3', {}, 'No progress yet'),
        el('p', {}, 'Start a roadmap and mark lessons as done to see your progress here.'),
        el('a', { class: 'btn', href: '#/roadmaps' }, 'Browse roadmaps'),
      )
    );
    return;
  }

  // List of progress rows
  const list = el('div', {});
  progress.forEach(p => {
    const status = p.status || 'pending';
    const statusClass = status === 'done' ? 'beg' : status === 'in-progress' ? 'int' : '';
    list.appendChild(
      el('div', { class: 'card mb-1', style: 'padding:14px 18px;display:flex;align-items:center;gap:12px' },
        el('span', { class: 'badge ' + statusClass }, status),
        el('div', { class: 'flex-1' },
          el('div', { style: 'font-weight:600' }, p.item_title || ('Item #' + p.item_id)),
          el('div', { class: 'text-xs text-muted' }, 'Updated ' + timeAgo(p.updated_at)),
        ),
        el('button', {
          class: 'btn btn-ghost btn-sm',
          onclick: async () => {
            try {
              await api.removeProgress(p.item_id);
              toast('Progress cleared', 'success');
              viewProgress(root);
            } catch (e) { toast(e.message, 'error'); }
          },
        }, '✕ Clear'),
      )
    );
  });
  root.appendChild(list);
}

/* ── Profile ──────────────────────────────────────────────────────── */

async function viewProfile(root) {
  if (!requireAuth()) return;
  const u = state.user || {};

  root.innerHTML = '';
  root.appendChild(
    el('div', { class: 'profile-header' },
      el('div', { class: 'avatar-lg' }, initials(u.display_name || u.username || 'U')),
      el('div', {},
        el('h1', {}, u.display_name || u.username || 'User'),
        el('div', { class: 'meta' }, '@' + (u.username || '') + ' · ' + (u.email || '')),
        el('div', { class: 'meta mt-1' }, 'Role: ' + (u.role || 'student') + ' · Joined ' + timeAgo(u.created_at)),
      ),
    )
  );

  // Edit form
  const card = el('div', { class: 'card' }, el('h2', {}, 'Edit profile'));
  const nameInput = el('input', { type: 'text', value: u.display_name || '' });
  const bioInput  = el('textarea', { placeholder: 'Tell us about yourself…' }, u.bio || '');
  const avatarInput = el('input', { type: 'text', placeholder: 'https://…', value: u.avatar_url || '' });
  card.appendChild(el('div', { class: 'field' }, el('label', {}, 'Display name'), nameInput));
  card.appendChild(el('div', { class: 'field' }, el('label', {}, 'Bio'), bioInput));
  card.appendChild(el('div', { class: 'field' }, el('label', {}, 'Avatar URL'), avatarInput));
  const saveBtn = el('button', { class: 'btn' }, 'Save');
  saveBtn.onclick = async () => {
    saveBtn.disabled = true;
    saveBtn.textContent = 'Saving…';
    try {
      const j = await api.updateUser(u.id, {
        display_name: nameInput.value.trim(),
        bio: bioInput.value.trim(),
        avatar_url: avatarInput.value.trim(),
      });
      if (j.user) {
        state.user = j.user;
        localStorage.setItem('ms_user', JSON.stringify(j.user));
        renderNavActions();
      }
      toast('Profile saved', 'success');
      viewProfile(root);
    } catch (e) {
      toast(e.message, 'error');
    } finally {
      saveBtn.disabled = false;
      saveBtn.textContent = 'Save';
    }
  };
  card.appendChild(saveBtn);
  root.appendChild(card);

  // Logout
  const logoutCard = el('div', { class: 'card mt-3' },
    el('h2', {}, 'Session'),
    el('p', { class: 'text-muted' }, 'You’re logged in. Logging out clears your local token but keeps your data on the server.'),
    el('button', {
      class: 'btn btn-danger',
      onclick: () => {
        clearAuth();
        toast('Logged out', 'success');
        navigate('/');
      },
    }, 'Log out'),
  );
  root.appendChild(logoutCard);
}

/* ── Login / Register ─────────────────────────────────────────────── */

async function viewLogin(root) {
  const path = currentPath();
  const mode = path.startsWith('/register') ? 'register' : 'login';
  if (state.token) {
    navigate('/');
    return;
  }

  root.innerHTML = '';
  const card = el('div', { class: 'card auth-card' });
  const tabs = el('div', { class: 'auth-tabs' },
    el('button', { class: mode === 'login' ? 'active' : '', onclick: () => navigate('/login') }, 'Login'),
    el('button', { class: mode === 'register' ? 'active' : '', onclick: () => navigate('/register') }, 'Register'),
  );
  card.appendChild(tabs);

  card.appendChild(el('h1', {}, mode === 'login' ? 'Welcome back' : 'Create your account'));
  card.appendChild(el('p', { class: 'sub' }, mode === 'login'
    ? 'Login to track progress and take notes.'
    : 'Start tracking your learning in seconds.'));

  const errBox = el('div', { class: 'field-error', style: 'margin-bottom:10px' });

  if (mode === 'register') {
    const username = el('input', { type: 'text', placeholder: 'Username' });
    const email    = el('input', { type: 'email', placeholder: 'Email' });
    const password = el('input', { type: 'password', placeholder: 'Password' });
    card.appendChild(el('div', { class: 'field' }, el('label', {}, 'Username'), username));
    card.appendChild(el('div', { class: 'field' }, el('label', {}, 'Email'), email));
    card.appendChild(el('div', { class: 'field' }, el('label', {}, 'Password'), password));
    const btn = el('button', { class: 'btn btn-block btn-lg' }, 'Create account');
    btn.onclick = async () => {
      errBox.textContent = '';
      if (!username.value.trim() || !email.value.trim() || !password.value) {
        errBox.textContent = 'All fields are required.'; return;
      }
      btn.disabled = true; btn.textContent = 'Creating…';
      try {
        const j = await api.register({
          username: username.value.trim(),
          email: email.value.trim(),
          password: password.value,
        });
        saveAuth(j.token, j.user);
        toast('Welcome, ' + (j.user.username || 'friend') + '!', 'success');
        navigate('/');
      } catch (e) {
        errBox.textContent = e.message;
      } finally {
        btn.disabled = false; btn.textContent = 'Create account';
      }
    };
    card.appendChild(errBox);
    card.appendChild(btn);
    card.appendChild(el('div', { class: 'auth-switch' },
      'Already have an account? ', el('a', { href: '#/login' }, 'Login'),
    ));
  } else {
    const email    = el('input', { type: 'email', placeholder: 'Email' });
    const password = el('input', { type: 'password', placeholder: 'Password' });
    card.appendChild(el('div', { class: 'field' }, el('label', {}, 'Email'), email));
    card.appendChild(el('div', { class: 'field' }, el('label', {}, 'Password'), password));
    const btn = el('button', { class: 'btn btn-block btn-lg' }, 'Login');
    btn.onclick = async () => {
      errBox.textContent = '';
      if (!email.value.trim() || !password.value) {
        errBox.textContent = 'Email and password are required.'; return;
      }
      btn.disabled = true; btn.textContent = 'Logging in…';
      try {
        const j = await api.login({
          email: email.value.trim(),
          password: password.value,
        });
        saveAuth(j.token, j.user);
        toast('Welcome back, ' + (j.user.username || 'friend') + '!', 'success');
        navigate('/');
      } catch (e) {
        errBox.textContent = e.message;
      } finally {
        btn.disabled = false; btn.textContent = 'Login';
      }
    };
    card.appendChild(errBox);
    card.appendChild(btn);
    card.appendChild(el('div', { class: 'auth-switch' },
      'No account? ', el('a', { href: '#/register' }, 'Register'),
    ));
  }

  root.appendChild(card);
}

/* ─── Helpers (breadcrumb, footer, nav) ───────────────────────────── */

function breadcrumb(...parts) {
  const wrap = el('div', { class: 'flex items-center gap-1 text-sm text-muted mb-2', style: 'flex-wrap:wrap' });
  parts.forEach((p, i) => {
    if (i % 2 === 0 && i > 0) {
      wrap.appendChild(el('span', { class: 'text-soft' }, '/'));
    }
    if (i % 2 === 0) {
      // label
      wrap.appendChild(el('span', {}, p));
    } else {
      // link
      wrap.appendChild(el('a', { href: '#' + p, class: 'text-muted' }, parts[i - 1]));
      // Replace the previous text node with the link's text — easier: clear and re-add
    }
  });
  // Simplify: rebuild
  wrap.innerHTML = '';
  for (let i = 0; i < parts.length; i += 2) {
    const label = parts[i];
    const href  = parts[i + 1];
    if (i > 0) wrap.appendChild(el('span', { class: 'text-soft' }, '›'));
    if (href) {
      wrap.appendChild(el('a', { href: '#' + href, class: 'text-muted' }, label));
    } else {
      wrap.appendChild(el('span', { class: 'text-muted' }, label));
    }
  }
  return wrap;
}

function footerEl() {
  return el('footer', { class: 'footer' },
    el('div', {},
      'modifiedS · Bantu v1.2.2 + Sua + SQLite · ',
      el('a', { href: 'https://github.com/AsseySilivestir/modifiedS', target: '_blank', rel: 'noopener' }, 'GitHub'),
    ),
    el('div', {}, 'Backend rewrite of Splannes (Next.js)'),
  );
}

function renderNavActions() {
  const wrap = $('#nav-actions');
  if (!wrap) return;
  wrap.innerHTML = '';
  if (state.token && state.user) {
    wrap.appendChild(
      el('a', { class: 'user-chip', href: '#/profile' },
        el('div', { class: 'avatar' }, initials(state.user.display_name || state.user.username || 'U')),
        state.user.username || 'Account',
      )
    );
  } else {
    wrap.appendChild(el('a', { class: 'btn btn-ghost btn-sm', href: '#/login' }, 'Login'));
    wrap.appendChild(el('a', { class: 'btn btn-sm', href: '#/register' }, 'Sign up'));
  }
}

/* ─── 6. Boot ─────────────────────────────────────────────────────── */

function boot() {
  loadAuth();
  renderNavActions();

  // Hash change → route
  window.addEventListener('hashchange', router);

  // Initial route
  if (!location.hash) location.hash = '#/';
  router();

  // Background refresh of user (validates token)
  if (state.token) refreshMe();
}

document.addEventListener('DOMContentLoaded', boot);
