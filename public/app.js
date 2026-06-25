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

// Wrapper around fetch that retries on network errors (Render free-tier
// sleeps after 15 min of inactivity, so the first request after sleep may
// fail with "Failed to fetch" while the server is spinning back up).
async function fetchWithRetry(url, opts, attempts = 3, delayMs = 1500) {
  let lastErr;
  for (let i = 0; i < attempts; i++) {
    try {
      const ctrl = new AbortController();
      const t = setTimeout(() => ctrl.abort(), 20000); // 20s timeout per attempt
      const r = await fetch(url, { ...opts, signal: ctrl.signal });
      clearTimeout(t);
      return r;
    } catch (e) {
      lastErr = e;
      // Only retry on network errors (not on HTTP error responses)
      const isNetwork = e.name === 'AbortError' ||
                        e.message === 'Failed to fetch' ||
                        e.message.includes('Network') ||
                        e.message.includes('network');
      if (!isNetwork || i === attempts - 1) throw e;
      // Wait before retrying (linear backoff)
      await new Promise(res => setTimeout(res, delayMs * (i + 1)));
    }
  }
  throw lastErr;
}

const api = {
  async req(path, { method = 'GET', body, auth = false } = {}) {
    const headers = { 'Content-Type': 'application/json' };
    if (auth && state.token) headers['Authorization'] = 'Bearer ' + state.token;
    const opts = { method, headers };
    if (body !== undefined) opts.body = JSON.stringify(body);
    let r;
    try {
      r = await fetchWithRetry('/api' + path, opts);
    } catch (e) {
      // Give a friendlier error message for cold-start failures
      const msg = e.message === 'Failed to fetch' || e.message.includes('Network')
        ? 'Server is starting up (or offline). Please wait a few seconds and try again.'
        : 'Network error: ' + e.message;
      throw new Error(msg);
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

  // Community — thoughts
  thoughts:        ()        => api.req('/thoughts'),
  postThought:     (b)       => api.req('/thoughts', { method: 'POST', auth: true, body: b }),
  deleteThought:   (id)      => api.req('/thoughts/' + id, { method: 'DELETE', auth: true }),
  likeThought:     (id)      => api.req('/thoughts/' + id + '/like', { method: 'POST', auth: true }),

  // Announcements
  announcements:   ()        => api.req('/announcements'),
  createAnnouncement: (b)    => api.req('/announcements', { method: 'POST', auth: true, body: b }),
  deleteAnnouncement: (id)   => api.req('/announcements/' + id, { method: 'DELETE', auth: true }),

  // Courses
  courses:         ()        => api.req('/courses'),
  course:          (id)      => api.req('/courses/' + id),
  createCourse:    (b)       => api.req('/courses', { method: 'POST', auth: true, body: b }),
  updateCourse:    (id, b)   => api.req('/courses/' + id, { method: 'PUT', auth: true, body: b }),
  deleteCourse:    (id)      => api.req('/courses/' + id, { method: 'DELETE', auth: true }),
  courseModules:   (id)      => api.req('/courses/' + id + '/modules'),
  addCourseModule: (id, b)   => api.req('/courses/' + id + '/modules', { method: 'POST', auth: true, body: b }),
  removeCourseModule: (cid, mid) => api.req('/courses/' + cid + '/modules/' + mid, { method: 'DELETE', auth: true }),

  // Enrollments
  enrollments:     ()              => api.req('/enrollments', { auth: true }),
  enroll:          (cid)           => api.req('/enrollments/' + cid, { method: 'POST', auth: true }),
  unenroll:        (cid)           => api.req('/enrollments/' + cid, { method: 'DELETE', auth: true }),
  setProgress:     (cid, percent)  => api.req('/enrollments/' + cid + '/progress', { method: 'POST', auth: true, body: { percent } }),

  // Certificates
  certificates:    ()        => api.req('/certificates', { auth: true }),
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
  // New in v1.1 — admin panel + community + courses + certificates
  { path: /^\/courses\/?$/,                  view: viewCourses },
  { path: /^\/course\/(\d+)\/?$/,             view: viewCourseDetail },
  { path: /^\/community\/?$/,                 view: viewCommunity },
  { path: /^\/announcements\/?$/,             view: viewAnnouncements },
  { path: /^\/certificates\/?$/,              view: viewCertificates },
  { path: /^\/admin\/?$/,                     view: viewAdmin },
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
  const isNetwork = !e.status && (e.message.includes('starting up') || e.message.includes('Network'));
  return el('div', { class: 'empty' },
    el('div', { class: 'empty-icon' }, needLogin ? '🔒' : (isNetwork ? '⏳' : '⚠️')),
    el('h3', {}, needLogin ? 'Login required' : (isNetwork ? 'Server is waking up' : 'Something went wrong')),
    el('p', {}, e.message || 'Unknown error'),
    isNetwork
      ? el('div', { class: 'flex gap-2' },
          el('button', { class: 'btn', onclick: () => location.reload() }, 'Retry now'),
          el('a', { class: 'btn btn-ghost', href: '#/' }, 'Back home'),
        )
      : (needLogin
          ? el('a', { class: 'btn', href: '#/login' }, 'Login')
          : el('a', { class: 'btn', href: '#/' }, 'Back home')),
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
        // Backend returns `choices`, but older caches may have `options` — accept both
        const opts = q.choices || q.options || [];
        opts.forEach((opt, oi) => {
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

/* ── v1.1 views: Courses / Course detail / Community / Announcements / Certificates / Admin ── */

async function viewCourses(root) {
  root.classList.add('view-courses');
  let data;
  try {
    data = await api.courses();
  } catch (e) { root.innerHTML = ''; root.appendChild(viewError(e)); return; }
  const courses = data.courses || [];

  root.appendChild(el('div', { class: 'page-head' },
    el('h1', {}, 'Courses'),
    el('p', {}, 'Browse courses published by the modifiedS team. Enroll, track your progress, and earn a certificate on completion.'),
  ));

  if (state.user && state.user.role === 'admin') {
    root.appendChild(el('a', { class: 'btn', href: '#/admin' }, '+ Manage courses (Admin)'));
  }

  if (courses.length === 0) {
    root.appendChild(el('div', { class: 'empty' },
      el('div', { class: 'empty-icon' }, '🎓'),
      el('h3', {}, 'No courses yet'),
      el('p', {}, state.user && state.user.role === 'admin'
        ? 'Head to the Admin panel to publish your first course.'
        : 'Check back soon — new courses are on the way.'),
    ));
    return;
  }

  const grid = el('div', { class: 'course-grid' });
  for (const c of courses) {
    const color = c.thumbnail_color || '#6366f1';
    grid.appendChild(el('a', { class: 'course-card', href: '#/course/' + c.id },
      el('div', { class: 'course-thumb', style: 'background:' + color },
        el('span', { class: 'course-thumb-emoji' }, '📘'),
      ),
      el('div', { class: 'course-body' },
        el('div', { class: 'course-tags' },
          el('span', { class: 'pill pill-' + diffColor(c.difficulty) }, c.difficulty || 'beginner'),
          el('span', { class: 'pill' }, c.category || 'General'),
        ),
        el('h3', {}, c.title),
        el('p', { class: 'course-desc' }, c.description || ''),
        el('div', { class: 'course-meta' },
          el('span', {}, '⏱ ' + (c.duration_hours || 0) + 'h'),
          el('span', {}, '👤 ' + escapeHtml(c.author || 'modifiedS')),
        ),
      ),
    ));
  }
  root.appendChild(grid);
}

async function viewCourseDetail(root, courseId) {
  root.classList.add('view-course-detail');
  let data;
  try {
    data = await api.course(courseId);
  } catch (e) { root.innerHTML = ''; root.appendChild(viewError(e)); return; }
  const c = data.course;
  const modules = data.modules || [];

  root.appendChild(el('a', { class: 'back-link', href: '#/courses' }, '← Back to courses'));
  const color = c.thumbnail_color || '#6366f1';

  root.appendChild(el('div', { class: 'course-hero', style: '--accent:' + color },
    el('div', { class: 'course-hero-tags' },
      el('span', { class: 'pill pill-' + diffColor(c.difficulty) }, c.difficulty || 'beginner'),
      el('span', { class: 'pill' }, c.category || 'General'),
    ),
    el('h1', {}, c.title),
    el('p', { class: 'course-hero-desc' }, c.description || ''),
    el('div', { class: 'course-hero-meta' },
      el('span', {}, '⏱ ' + (c.duration_hours || 0) + ' hours'),
      el('span', {}, '👤 ' + escapeHtml(c.instructor || c.author || 'modifiedS')),
      el('span', {}, '📦 ' + modules.length + ' module' + (modules.length === 1 ? '' : 's')),
    ),
  ));

  // Enrollment + progress
  let enrollment = null;
  if (state.token) {
    try {
      const en = await api.enrollments();
      enrollment = (en.enrollments || []).find(e => String(e.course_id) === String(courseId));
    } catch (_) {}
  }

  const actionsBar = el('div', { class: 'course-actions' });
  if (!state.token) {
    actionsBar.appendChild(el('a', { class: 'btn', href: '#/login' }, 'Login to enroll'));
  } else if (!enrollment) {
    const btn = el('button', { class: 'btn', onclick: async () => {
      try { await api.enroll(courseId); toast('Enrolled! Good luck 🎯'); router(); }
      catch (e) { toast(e.message, 'error'); }
    }}, 'Enroll now');
    actionsBar.appendChild(btn);
  } else {
    const pct = enrollment.progress_percent || 0;
    actionsBar.appendChild(el('div', { class: 'progress-inline' },
      el('div', { class: 'progress-bar' },
        el('div', { class: 'progress-bar-fill', style: 'width:' + pct + '%' }),
      ),
      el('span', { class: 'progress-pct' }, pct + '%'),
    ));
    if (pct < 100) {
      const pctInput = el('input', { type: 'range', min: '0', max: '100', value: String(pct), style: 'width:220px' });
      pctInput.addEventListener('change', async () => {
        try {
          const r = await api.setProgress(courseId, parseInt(pctInput.value, 10));
          toast('Progress saved: ' + pctInput.value + '%');
          if (r.certificate) {
            toast('🎉 Course complete! Your certificate is ready.', 'success');
          }
          router();
        } catch (e) { toast(e.message, 'error'); }
      });
      actionsBar.appendChild(pctInput);
      actionsBar.appendChild(el('span', { class: 'muted' }, 'Mark my progress'));
    } else {
      actionsBar.appendChild(el('span', { class: 'pill pill-success' }, '✓ Completed'));
      actionsBar.appendChild(el('a', { class: 'btn btn-ghost', href: '#/certificates' }, 'View certificate →'));
    }
    const unenrollBtn = el('button', { class: 'btn btn-ghost btn-sm', onclick: async () => {
      if (!confirm('Unenroll from this course? Your progress will be lost.')) return;
      try { await api.unenroll(courseId); toast('Unenrolled'); router(); }
      catch (e) { toast(e.message, 'error'); }
    }}, 'Unenroll');
    actionsBar.appendChild(unenrollBtn);
  }
  root.appendChild(actionsBar);

  // Modules
  root.appendChild(el('h2', { class: 'section-title' }, 'Course content'));
  if (modules.length === 0) {
    root.appendChild(el('div', { class: 'empty' },
      el('p', {}, 'No modules yet. Check back soon.'),
    ));
  } else {
    const list = el('div', { class: 'module-list' });
    modules.forEach((m, i) => {
      list.appendChild(el('details', { class: 'module-item' },
        el('summary', {},
          el('span', { class: 'module-num' }, String(i + 1).padStart(2, '0')),
          el('span', { class: 'module-title' }, m.title),
        ),
        el('div', { class: 'module-content', html: renderMarkdown(m.content || '') }),
      ));
    });
    root.appendChild(list);
  }
}

async function viewCommunity(root) {
  root.classList.add('view-community');
  let data;
  try {
    data = await api.thoughts();
  } catch (e) { root.innerHTML = ''; root.appendChild(viewError(e)); return; }
  const thoughts = data.thoughts || [];

  root.appendChild(el('div', { class: 'page-head' },
    el('h1', {}, 'Community'),
    el('p', {}, 'Share what you are learning, ask questions, and inspire each other.'),
  ));

  // Composer
  if (state.token) {
    const ta = el('textarea', { class: 'thought-input', placeholder: 'Share a thought, aha-moment, or question… (max 1000 chars)', maxlength: '1000', rows: '3' });
    const tagInput = el('input', { class: 'thought-tags', placeholder: 'Tags (comma-separated, optional)' });
    const postBtn = el('button', { class: 'btn', onclick: async () => {
      const body = ta.value.trim();
      if (!body) { toast('Write something first ✍️', 'error'); return; }
      postBtn.disabled = true;
      postBtn.textContent = 'Posting…';
      try {
        await api.postThought({ body, tags: tagInput.value.trim() });
        ta.value = ''; tagInput.value = '';
        toast('Posted 🎉');
        router();
      } catch (e) { toast(e.message, 'error'); }
      finally { postBtn.disabled = false; postBtn.textContent = 'Post thought'; }
    }}, 'Post thought');
    root.appendChild(el('div', { class: 'thought-composer' },
      ta, tagInput, postBtn));
  } else {
    root.appendChild(el('div', { class: 'banner' },
      el('a', { href: '#/login' }, 'Login'), ' to share your thoughts.'));
  }

  // Feed
  if (thoughts.length === 0) {
    root.appendChild(el('div', { class: 'empty' },
      el('div', { class: 'empty-icon' }, '💬'),
      el('h3', {}, 'No thoughts yet'),
      el('p', {}, 'Be the first to share something with the community.'),
    ));
    return;
  }

  const feed = el('div', { class: 'thought-feed' });
  for (const t of thoughts) {
    const displayName = t.display_name || t.username || 'Anonymous';
    const avatar = el('div', { class: 'avatar avatar-sm' }, initials(displayName));
    const card = el('div', { class: 'thought-card' },
      el('div', { class: 'thought-head' },
        avatar,
        el('div', { class: 'thought-meta' },
          el('span', { class: 'thought-author' }, displayName),
          el('span', { class: 'thought-time' }, timeAgo(t.created_at)),
        ),
      ),
      el('p', { class: 'thought-body' }, t.body),
    );
    if (t.tags && t.tags !== '') {
      card.appendChild(el('div', { class: 'thought-tags-row' },
        t.tags.split(',').map(s => s.trim()).filter(Boolean).map(tag =>
          el('span', { class: 'pill pill-soft' }, '#' + tag))));
    }
    const footer = el('div', { class: 'thought-foot' });
    if (state.token) {
      const likeBtn = el('button', { class: 'btn btn-ghost btn-sm', onclick: async () => {
        likeBtn.disabled = true;
        try { await api.likeThought(t.id); router(); }
        catch (e) { toast(e.message, 'error'); }
        finally { likeBtn.disabled = false; }
      }}, '❤ ' + (t.likes || 0));
      footer.appendChild(likeBtn);
    } else {
      footer.appendChild(el('span', { class: 'muted' }, '❤ ' + (t.likes || 0) + ' likes'));
    }
    if (state.user && (state.user.id === t.user_id || state.user.role === 'admin')) {
      footer.appendChild(el('button', { class: 'btn btn-ghost btn-sm', onclick: async () => {
        if (!confirm('Delete this thought?')) return;
        try { await api.deleteThought(t.id); toast('Deleted'); router(); }
        catch (e) { toast(e.message, 'error'); }
      }}, 'Delete'));
    }
    card.appendChild(footer);
    feed.appendChild(card);
  }
  root.appendChild(feed);
}

async function viewAnnouncements(root) {
  root.classList.add('view-announcements');
  let data;
  try {
    data = await api.announcements();
  } catch (e) { root.innerHTML = ''; root.appendChild(viewError(e)); return; }
  const items = data.announcements || [];

  root.appendChild(el('div', { class: 'page-head' },
    el('h1', {}, 'Announcements'),
    el('p', {}, 'Latest news from the modifiedS team.'),
  ));

  if (items.length === 0) {
    root.appendChild(el('div', { class: 'empty' },
      el('div', { class: 'empty-icon' }, '📢'),
      el('h3', {}, 'No announcements'),
      el('p', {}, 'Stay tuned — official updates will appear here.'),
    ));
    return;
  }

  const list = el('div', { class: 'announcement-list' });
  for (const a of items) {
    const card = el('div', { class: 'announcement-card' + (a.pinned ? ' pinned' : '') },
      el('div', { class: 'announcement-head' },
        el('span', { class: 'pill pill-' + (a.pinned ? 'success' : 'soft') }, a.pinned ? '📌 Pinned' : (a.category || 'general')),
        el('span', { class: 'announcement-time' }, timeAgo(a.created_at)),
      ),
      el('h3', {}, a.title),
      el('div', { class: 'announcement-body', html: renderMarkdown(a.body) }),
      el('div', { class: 'announcement-author' }, '— ' + escapeHtml(a.author || 'modifiedS')),
    );
    if (state.user && state.user.role === 'admin') {
      card.appendChild(el('button', { class: 'btn btn-ghost btn-sm', onclick: async () => {
        if (!confirm('Delete this announcement?')) return;
        try { await api.deleteAnnouncement(a.id); toast('Deleted'); router(); }
        catch (e) { toast(e.message, 'error'); }
      }}, 'Delete'));
    }
    list.appendChild(card);
  }
  root.appendChild(list);
}

async function viewCertificates(root) {
  root.classList.add('view-certificates');
  if (!requireAuth()) return;

  let data;
  try {
    data = await api.certificates();
  } catch (e) { root.innerHTML = ''; root.appendChild(viewError(e)); return; }
  const certs = data.certificates || [];

  root.appendChild(el('div', { class: 'page-head' },
    el('h1', {}, 'My Certificates'),
    el('p', {}, 'Every time you complete a course (100% progress), a certificate is automatically issued. Click to view and print or save as PDF.'),
  ));

  if (certs.length === 0) {
    root.appendChild(el('div', { class: 'empty' },
      el('div', { class: 'empty-icon' }, '🏅'),
      el('h3', {}, 'No certificates yet'),
      el('p', {}, 'Enroll in a course and mark your progress to 100% to earn your first certificate.'),
      el('a', { class: 'btn', href: '#/courses' }, 'Browse courses'),
    ));
    return;
  }

  const grid = el('div', { class: 'cert-grid' });
  for (const ct of certs) {
    grid.appendChild(el('div', { class: 'cert-card' },
      el('div', { class: 'cert-badge-tag' }, '★ Verified'),
      el('div', { class: 'cert-seal' }, '★'),
      el('h3', {}, ct.course_title || 'Course'),
      el('div', { class: 'cert-code' }, 'Code: ' + ct.certificate_code),
      el('div', { class: 'cert-issued' }, 'Issued ' + timeAgo(ct.issued_at)),
      el('div', { class: 'cert-actions' },
        el('button', { class: 'btn btn-sm', onclick: () => openCertificatePrintWindow(ct) }, 'View / Print'),
        el('button', { class: 'btn btn-ghost btn-sm', onclick: () => downloadCertificatePDF(ct) }, 'Download PDF'),
      ),
    ));
  }
  root.appendChild(grid);
}

/** Opens a new window with a printable certificate HTML and triggers print dialog.
 *  User can choose "Save as PDF" in the print dialog to download. */
function openCertificatePrintWindow(ct) {
  const displayName = ct.display_name || ct.username || 'Learner';
  const courseTitle = ct.course_title || 'Course';
  const instructor  = ct.instructor || 'modifiedS Academy';
  const issuedAt    = (ct.issued_at || '').replace('T', ' ').replace('Z', '');
  const duration    = ct.duration_hours || 0;
  const code        = ct.certificate_code || '';
  const w = window.open('', '_blank', 'width=920,height=720');
  if (!w) { toast('Popup blocked — please allow popups for this site.', 'error'); return; }
  w.document.open();
  w.document.write(`<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Certificate — ${escapeHtml(courseTitle)}</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Georgia', 'Times New Roman', serif; background: #f5f5f7; min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 24px; }
  .cert { background: #fff; max-width: 920px; width: 100%; padding: 64px 56px; border: 12px double #6366f1; position: relative; box-shadow: 0 12px 40px rgba(99,102,241,0.15); }
  .cert::before, .cert::after { content: ''; position: absolute; left: 12px; right: 12px; height: 1px; background: linear-gradient(90deg, transparent, #c7d2fe, transparent); }
  .cert::before { top: 12px; } .cert::after { bottom: 12px; }
  .ribbon { text-align: center; font-size: 12px; letter-spacing: 4px; text-transform: uppercase; color: #6366f1; font-weight: 600; margin-bottom: 16px; }
  h1 { text-align: center; font-size: 38px; color: #1f2937; margin-bottom: 8px; font-weight: 400; letter-spacing: 1px; }
  .subtitle { text-align: center; font-size: 16px; color: #6b7280; margin-bottom: 48px; font-style: italic; }
  .name { text-align: center; font-size: 42px; color: #4f46e5; font-weight: 700; margin-bottom: 32px; padding-bottom: 16px; border-bottom: 2px solid #e0e7ff; }
  .desc { text-align: center; font-size: 16px; color: #4b5563; line-height: 1.7; margin-bottom: 16px; }
  .course-name { font-weight: 700; color: #1f2937; font-size: 22px; display: block; margin-top: 8px; }
  .meta { display: flex; justify-content: space-between; margin-top: 56px; padding-top: 32px; border-top: 1px solid #e5e7eb; }
  .meta-item { text-align: center; flex: 1; }
  .meta-label { font-size: 11px; letter-spacing: 2px; text-transform: uppercase; color: #9ca3af; margin-bottom: 6px; }
  .meta-value { font-size: 14px; color: #1f2937; font-weight: 600; word-break: break-all; }
  .seal { position: absolute; bottom: 40px; right: 40px; width: 96px; height: 96px; border: 3px solid #6366f1; border-radius: 50%; display: flex; flex-direction: column; align-items: center; justify-content: center; color: #6366f1; font-size: 10px; text-align: center; transform: rotate(-8deg); }
  .seal-star { font-size: 22px; line-height: 1; }
  .actions { text-align: center; margin-top: 24px; }
  .print-btn { background: #6366f1; color: #fff; border: none; padding: 12px 24px; font-size: 14px; border-radius: 8px; cursor: pointer; font-family: inherit; }
  .print-btn:hover { background: #4f46e5; }
  @media print { body { background: #fff; padding: 0; } .cert { box-shadow: none; max-width: 100%; } .actions { display: none; } }
</style></head><body>
<div class="cert">
  <div class="ribbon">modifiedS Academy</div>
  <h1>Certificate of Completion</h1>
  <p class="subtitle">This certificate is proudly presented to</p>
  <div class="name">${escapeHtml(displayName)}</div>
  <p class="desc">For successfully completing all required modules and demonstrating proficiency in</p>
  <p class="desc"><span class="course-name">${escapeHtml(courseTitle)}</span></p>
  <p class="desc">A ${escapeHtml(String(duration))}-hour course instructed by ${escapeHtml(instructor)}.</p>
  <div class="meta">
    <div class="meta-item"><div class="meta-label">Date Issued</div><div class="meta-value">${escapeHtml(issuedAt)}</div></div>
    <div class="meta-item"><div class="meta-label">Certificate Code</div><div class="meta-value">${escapeHtml(code)}</div></div>
    <div class="meta-item"><div class="meta-label">Verify At</div><div class="meta-value">modifiedS.app</div></div>
  </div>
  <div class="seal"><div class="seal-star">&#9733;</div><div>OFFICIAL<br/>SEAL</div></div>
</div>
<div class="actions"><button class="print-btn" onclick="window.print()">Print / Save as PDF</button></div>
<script>window.onload = function() { setTimeout(function(){ window.print(); }, 400); };<\/script>
</body></html>`);
  w.document.close();
}

/**
 * Generates a true PDF certificate using jsPDF and triggers a direct download.
 * Layout (A4 landscape, 297×210 mm):
 *   - Outer double border in indigo
 *   - Corner ornaments
 *   - Top center: college badge (circular emblem with crest + ribbon)
 *   - "CERTIFICATE OF COMPLETION" title
 *   - "This certificate is proudly presented to"
 *   - Recipient NAME (large, indigo, underlined)
 *   - Course name + description
 *   - Bottom: 3-column meta (Date issued · Certificate code · Verify at)
 *   - Bottom-right: official gold seal
 *   - Bottom-left: signature line
 *   - Diagonal watermarks across the page ("modifiedS ACADEMY · OFFICIAL")
 */
function downloadCertificatePDF(ct) {
  if (typeof window.jspdf === 'undefined' || !window.jspdf.jsPDF) {
    toast('PDF library failed to load — using print view instead.', 'error');
    openCertificatePrintWindow(ct);
    return;
  }
  const { jsPDF } = window.jspdf;

  const displayName = ct.display_name || ct.username || 'Learner';
  const courseTitle = ct.course_title || 'Course';
  const instructor  = ct.instructor || 'modifiedS Academy';
  const issuedRaw   = ct.issued_at || new Date().toISOString();
  const issuedAt    = issuedRaw.replace('T', ' ').replace('Z', '').substring(0, 19);
  const duration    = ct.duration_hours || 0;
  const code        = ct.certificate_code || ('MSR-' + Date.now());

  // A4 landscape: 297 × 210 mm
  const doc = new jsPDF({ orientation: 'landscape', unit: 'mm', format: 'a4' });
  const W = 297, H = 210;

  // -------- Background: subtle cream wash --------
  doc.setFillColor(252, 252, 248);
  doc.rect(0, 0, W, H, 'F');

  // -------- Watermarks (drawn first so they sit behind everything) --------
  // Large diagonal watermark text across the page
  doc.setTextColor(99, 102, 241);       // indigo-500
  doc.setGState(new doc.GState({ opacity: 0.06 }));
  doc.setFont('times', 'italic', 'bold');
  doc.setFontSize(72);
  doc.text('modifiedS', W / 2, H / 2, { align: 'center', angle: 35 });
  doc.setFontSize(28);
  doc.text('ACADEMY · OFFICIAL', W / 2, H / 2 + 22, { align: 'center', angle: 35 });
  // Repeat along the diagonal axis for full coverage
  doc.setFontSize(48);
  doc.text('CERTIFIED', 60, 60, { align: 'center', angle: 35 });
  doc.text('CERTIFIED', W - 60, H - 50, { align: 'center', angle: 35 });
  doc.setGState(new doc.GState({ opacity: 1 }));

  // -------- Outer double border --------
  doc.setDrawColor(99, 102, 241);
  doc.setLineWidth(2);
  doc.rect(8, 8, W - 16, H - 16);
  doc.setLineWidth(0.4);
  doc.rect(12, 12, W - 24, H - 24);

  // Corner ornaments (small diamonds at each corner)
  const corners = [[14, 14], [W - 14, 14], [14, H - 14], [W - 14, H - 14]];
  for (const [cx, cy] of corners) {
    doc.setFillColor(99, 102, 241);
    doc.triangle(cx - 2.5, cy, cx, cy - 2.5, cx + 2.5, cy, 'F');
    doc.triangle(cx - 2.5, cy, cx, cy + 2.5, cx + 2.5, cy, 'F');
  }

  // -------- Top ribbon --------
  doc.setFillColor(99, 102, 241);
  doc.roundedRect(W / 2 - 50, 20, 100, 9, 2, 2, 'F');
  doc.setTextColor(255, 255, 255);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(10);
  doc.text('modifiedS  ACADEMY', W / 2, 26, { align: 'center' });

  // -------- College badge (circular emblem with crest + ribbon tails) --------
  drawCollegeBadge(doc, W / 2, 48, 16);

  // -------- Title --------
  doc.setTextColor(31, 41, 55);
  doc.setFont('times', 'normal');
  doc.setFontSize(34);
  doc.text('Certificate of Completion', W / 2, 84, { align: 'center' });

  // Decorative line under title
  doc.setDrawColor(199, 210, 254);
  doc.setLineWidth(0.5);
  doc.line(W / 2 - 50, 88, W / 2 + 50, 88);

  // -------- "presented to" --------
  doc.setTextColor(107, 114, 128);
  doc.setFont('times', 'italic');
  doc.setFontSize(13);
  doc.text('This certificate is proudly presented to', W / 2, 100, { align: 'center' });

  // -------- Recipient name --------
  doc.setTextColor(79, 70, 229);
  doc.setFont('times', 'bold');
  doc.setFontSize(38);
  doc.text(displayName, W / 2, 116, { align: 'center' });

  // Name underline (gradient-look using overlapping segments)
  doc.setLineWidth(1);
  doc.setDrawColor(199, 210, 254);
  doc.line(W / 2 - 70, 120, W / 2 + 70, 120);
  doc.setDrawColor(99, 102, 241);
  doc.line(W / 2 - 40, 120, W / 2 + 40, 120);

  // -------- Course description block --------
  doc.setTextColor(75, 85, 99);
  doc.setFont('times', 'normal');
  doc.setFontSize(13);
  doc.text('For successfully completing all required modules and demonstrating proficiency in', W / 2, 134, { align: 'center' });

  doc.setTextColor(31, 41, 55);
  doc.setFont('times', 'bold');
  doc.setFontSize(20);
  doc.text(courseTitle, W / 2, 144, { align: 'center' });

  doc.setTextColor(75, 85, 99);
  doc.setFont('times', 'italic');
  doc.setFontSize(11);
  const durText = duration > 0
    ? 'A ' + duration + '-hour course'
    : 'A self-paced course';
  doc.text(durText + '  ·  Instructed by ' + instructor, W / 2, 152, { align: 'center' });

  // -------- Meta row (3 columns) --------
  const metaY = 172;
  doc.setDrawColor(229, 231, 235);
  doc.setLineWidth(0.3);
  doc.line(28, metaY - 6, W - 28, metaY - 6);

  const cols = [
    { label: 'DATE ISSUED',     value: issuedAt },
    { label: 'CERTIFICATE CODE', value: code },
    { label: 'VERIFY AT',       value: 'modifiedS.app' },
  ];
  const colW = (W - 56) / 3;
  for (let i = 0; i < 3; i++) {
    const cx = 28 + colW * i + colW / 2;
    doc.setTextColor(156, 163, 175);
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(8);
    doc.text(cols[i].label, cx, metaY, { align: 'center' });
    doc.setTextColor(31, 41, 55);
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(11);
    doc.text(cols[i].value, cx, metaY + 6, { align: 'center' });
  }

  // -------- Signature line (bottom-left) --------
  const sigX = 50, sigY = 188;
  doc.setDrawColor(31, 41, 55);
  doc.setLineWidth(0.4);
  doc.line(sigX, sigY, sigX + 60, sigY);
  doc.setTextColor(31, 41, 55);
  doc.setFont('times', 'italic');
  doc.setFontSize(12);
  doc.text('Academic Director', sigX + 30, sigY - 3, { align: 'center' });
  doc.setTextColor(107, 114, 128);
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  doc.text('modifiedS Academy', sigX + 30, sigY + 4, { align: 'center' });

  // -------- Official gold seal (bottom-right) --------
  drawGoldSeal(doc, W - 48, sigY - 4, 13);

  // -------- Footer brand --------
  doc.setTextColor(156, 163, 175);
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(7);
  doc.text('This certificate can be verified at modifiedS.app/verify using the certificate code above.', W / 2, H - 8, { align: 'center' });

  // -------- Download --------
  const filename = 'modifiedS-Certificate-' + sanitizeFilename(courseTitle) + '.pdf';
  doc.save(filename);
  toast('Certificate PDF downloaded 📄', 'success');
}

/** Draws a circular college badge centered at (cx, cy) with radius r. */
function drawCollegeBadge(doc, cx, cy, r) {
  // Outer gold ring
  doc.setFillColor(212, 175, 55);     // gold
  doc.circle(cx, cy, r + 1.2, 'F');
  // Inner indigo disc
  doc.setFillColor(79, 70, 229);      // indigo-600
  doc.circle(cx, cy, r, 'F');
  // Cream center disc
  doc.setFillColor(252, 252, 248);
  doc.circle(cx, cy, r - 2, 'F');

  // Crest: open book (a "V" shape)
  doc.setDrawColor(31, 41, 55);
  doc.setLineWidth(0.7);
  doc.line(cx - r * 0.55, cy - r * 0.15, cx, cy + r * 0.05);
  doc.line(cx, cy + r * 0.05, cx + r * 0.55, cy - r * 0.15);
  doc.line(cx, cy + r * 0.05, cx, cy + r * 0.45);

  // Star above book
  doc.setFillColor(212, 175, 55);
  drawStar(doc, cx, cy - r * 0.5, r * 0.22);

  // Ribbon tails below the badge
  doc.setFillColor(212, 175, 55);
  doc.triangle(cx - r * 0.45, cy + r * 0.9, cx - r * 0.15, cy + r * 0.9, cx - r * 0.30, cy + r * 1.4, 'F');
  doc.triangle(cx + r * 0.45, cy + r * 0.9, cx + r * 0.15, cy + r * 0.9, cx + r * 0.30, cy + r * 1.4, 'F');
  doc.setFillColor(99, 102, 241);
  doc.rect(cx - r * 0.4, cy + r * 0.7, r * 0.8, r * 0.25, 'F');

  // "EST. 2024" text inside ribbon
  doc.setTextColor(255, 255, 255);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(5);
  doc.text('EST. 2024', cx, cy + r * 0.85, { align: 'center' });

  // "M" letter at top of ring
  doc.setTextColor(212, 175, 55);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(6);
  doc.text('★ MODIFIEDS ACADEMY ★', cx, cy - r - 2.5, { align: 'center' });
}

/** Draws an official gold seal at (cx, cy) with radius r. */
function drawGoldSeal(doc, cx, cy, r) {
  // Serrated outer edge (12 points)
  doc.setFillColor(212, 175, 55);
  const points = 12;
  const pts = [];
  for (let i = 0; i < points * 2; i++) {
    const angle = (Math.PI * 2 * i) / (points * 2) - Math.PI / 2;
    const rad = (i % 2 === 0) ? r : r * 0.85;
    pts.push([cx + Math.cos(angle) * rad, cy + Math.sin(angle) * rad]);
  }
  // Draw polygon
  for (let i = 0; i < pts.length; i++) {
    const a = pts[i], b = pts[(i + 1) % pts.length];
    doc.line(a[0], a[1], b[0], b[1]);
  }
  doc.setFillColor(212, 175, 55);
  doc.circle(cx, cy, r * 0.75, 'F');

  // Inner indigo ring
  doc.setDrawColor(79, 70, 229);
  doc.setLineWidth(0.5);
  doc.circle(cx, cy, r * 0.6, 'S');
  doc.setFillColor(79, 70, 229);
  doc.circle(cx, cy, r * 0.5, 'F');

  // Star center
  drawStar(doc, cx, cy + 1, r * 0.3);
  doc.setTextColor(255, 255, 255);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(4.5);
  doc.text('OFFICIAL', cx, cy - r * 0.7, { align: 'center' });
  doc.text('SEAL', cx, cy + r * 0.7, { align: 'center' });

  // Rotation text around seal
  doc.setFontSize(3.5);
  doc.setTextColor(212, 175, 55);
  doc.text('CERTIFIED · VERIFIED · SEALED', cx, cy + r + 2, { align: 'center' });
}

/** Draws a 5-point star centered at (cx, cy) with radius r. */
function drawStar(doc, cx, cy, r) {
  const pts = [];
  for (let i = 0; i < 10; i++) {
    const angle = (Math.PI * i) / 5 - Math.PI / 2;
    const rad = (i % 2 === 0) ? r : r * 0.4;
    pts.push([cx + Math.cos(angle) * rad, cy + Math.sin(angle) * rad]);
  }
  // Construct polygon path using lines + fill via triangles
  for (let i = 1; i < pts.length - 1; i++) {
    doc.triangle(pts[0][0], pts[0][1], pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], 'F');
  }
}

function sanitizeFilename(s) {
  return String(s || 'certificate').replace(/[^a-z0-9_-]+/gi, '_').replace(/_+/g, '_').substring(0, 60);
}


async function viewAdmin(root) {
  root.classList.add('view-admin');
  if (!requireAuth()) return;
  if (!state.user || state.user.role !== 'admin') {
    root.innerHTML = '';
    root.appendChild(el('div', { class: 'empty' },
      el('div', { class: 'empty-icon' }, '🚫'),
      el('h3', {}, 'Admin access required'),
      el('p', {}, 'Only the first registered account (or promoted admins) can access this panel.'),
    ));
    return;
  }

  root.appendChild(el('div', { class: 'page-head' },
    el('h1', {}, 'Admin Panel'),
    el('p', {}, 'Publish courses, post announcements, and manage the community. The first user to register is automatically an admin.'),
  ));

  // Tab bar
  const tabs = [
    { id: 'courses', label: 'Courses' },
    { id: 'announcements', label: 'Announcements' },
    { id: 'stats', label: 'Stats' },
  ];
  const tabBar = el('div', { class: 'tab-bar' });
  const panel = el('div', { class: 'tab-panel' });
  let active = 'courses';

  function renderTab() {
    tabBar.innerHTML = '';
    for (const t of tabs) {
      const b = el('button', { class: 'tab-btn' + (active === t.id ? ' active' : ''), onclick: () => {
        active = t.id; renderTab();
      }}, t.label);
      tabBar.appendChild(b);
    }
    panel.innerHTML = '';
    if (active === 'courses') panel.appendChild(renderCoursesAdmin());
    else if (active === 'announcements') panel.appendChild(renderAnnouncementsAdmin());
    else if (active === 'stats') panel.appendChild(renderStatsAdmin());
  }

  function renderCoursesAdmin() {
    const wrap = el('div', { class: 'admin-section' });
    wrap.appendChild(el('h2', {}, 'Publish a new course'));
    const f = el('form', { class: 'admin-form' });
    const title = el('input', { type: 'text', placeholder: 'Course title', required: '' });
    const description = el('textarea', { placeholder: 'Short description (what learners will be able to do after this course)', rows: '3', required: '' });
    const category = el('input', { type: 'text', placeholder: 'Category (e.g. Web, Data, Design)', value: 'General' });
    const difficulty = el('select', {},
      el('option', { value: 'beginner' }, 'beginner'),
      el('option', { value: 'intermediate' }, 'intermediate'),
      el('option', { value: 'advanced' }, 'advanced'));
    const duration = el('input', { type: 'number', min: '0', placeholder: 'Duration (hours)', value: '10' });
    const instructor = el('input', { type: 'text', placeholder: 'Instructor name', value: state.user.username || '' });
    const color = el('input', { type: 'color', value: '#6366f1' });
    const submit = el('button', { class: 'btn', type: 'submit' }, 'Publish course');
    f.append(
      field('Title', title),
      field('Description', description),
      el('div', { class: 'form-row' }, field('Category', category), field('Difficulty', difficulty)),
      el('div', { class: 'form-row' }, field('Duration (hours)', duration), field('Instructor', instructor), field('Color', color)),
      submit);
    f.addEventListener('submit', async (e) => {
      e.preventDefault();
      submit.disabled = true; submit.textContent = 'Publishing…';
      try {
        await api.createCourse({
          title: title.value.trim(),
          description: description.value.trim(),
          category: category.value.trim() || 'General',
          difficulty: difficulty.value,
          duration_hours: parseInt(duration.value, 10) || 0,
          instructor: instructor.value.trim(),
          thumbnail_color: color.value,
        });
        toast('Course published 🎉');
        f.reset();
        renderTab();
      } catch (err) { toast(err.message, 'error'); }
      finally { submit.disabled = false; submit.textContent = 'Publish course'; }
    });
    wrap.appendChild(f);

    wrap.appendChild(el('h3', { class: 'mt-l' }, 'Manage existing courses'));
    api.courses().then(d => {
      const list = el('div', { class: 'admin-list' });
      (d.courses || []).forEach(c => {
        const row = el('div', { class: 'admin-row' },
          el('div', { class: 'admin-row-main' },
            el('strong', {}, c.title),
            el('span', { class: 'muted' }, ' · ' + c.category + ' · ' + c.difficulty + ' · ' + c.duration_hours + 'h'),
          ),
          el('a', { class: 'btn btn-ghost btn-sm', href: '#/course/' + c.id }, 'View'),
        );
        const del = el('button', { class: 'btn btn-ghost btn-sm', onclick: async () => {
          if (!confirm('Delete course "' + c.title + '"? This also removes its modules and enrollments.')) return;
          try { await api.deleteCourse(c.id); toast('Deleted'); renderTab(); }
          catch (e) { toast(e.message, 'error'); }
        }}, 'Delete');
        row.appendChild(del);
        list.appendChild(row);
      });
      if ((d.courses || []).length === 0) list.appendChild(el('p', { class: 'muted' }, 'No courses published yet.'));
      wrap.appendChild(list);
    }).catch(e => wrap.appendChild(viewError(e)));
    return wrap;
  }

  function renderAnnouncementsAdmin() {
    const wrap = el('div', { class: 'admin-section' });
    wrap.appendChild(el('h2', {}, 'Post a new announcement'));
    const f = el('form', { class: 'admin-form' });
    const title = el('input', { type: 'text', placeholder: 'Headline', required: '' });
    const body = el('textarea', { placeholder: 'Announcement body (markdown supported)', rows: '4', required: '' });
    const category = el('input', { type: 'text', placeholder: 'Category', value: 'general' });
    const pinned = el('input', { type: 'checkbox' });
    const submit = el('button', { class: 'btn', type: 'submit' }, 'Post announcement');
    f.append(
      field('Title', title),
      field('Body', body),
      el('div', { class: 'form-row' }, field('Category', category), el('label', { class: 'field' }, el('span', { class: 'field-label' }, 'Pinned'), el('span', { class: 'checkbox-row' }, pinned, el('span', {}, 'Pin to top')))),
      submit);
    f.addEventListener('submit', async (e) => {
      e.preventDefault();
      submit.disabled = true; submit.textContent = 'Posting…';
      try {
        await api.createAnnouncement({
          title: title.value.trim(),
          body: body.value.trim(),
          category: category.value.trim() || 'general',
          pinned: pinned.checked,
        });
        toast('Announcement posted 📢');
        f.reset();
      } catch (err) { toast(err.message, 'error'); }
      finally { submit.disabled = false; submit.textContent = 'Post announcement'; }
    });
    wrap.appendChild(f);

    wrap.appendChild(el('h3', { class: 'mt-l' }, 'Manage announcements'));
    api.announcements().then(d => {
      const list = el('div', { class: 'admin-list' });
      (d.announcements || []).forEach(a => {
        const row = el('div', { class: 'admin-row' },
          el('div', { class: 'admin-row-main' },
            el('strong', {}, (a.pinned ? '📌 ' : '') + a.title),
            el('span', { class: 'muted' }, ' · ' + (a.category || 'general') + ' · ' + timeAgo(a.created_at)),
          ),
          el('button', { class: 'btn btn-ghost btn-sm', onclick: async () => {
            if (!confirm('Delete announcement?')) return;
            try { await api.deleteAnnouncement(a.id); toast('Deleted'); renderTab(); }
            catch (e) { toast(e.message, 'error'); }
          }}, 'Delete'),
        );
        list.appendChild(row);
      });
      if ((d.announcements || []).length === 0) list.appendChild(el('p', { class: 'muted' }, 'No announcements yet.'));
      wrap.appendChild(list);
    }).catch(e => wrap.appendChild(viewError(e)));
    return wrap;
  }

  function renderStatsAdmin() {
    const wrap = el('div', { class: 'admin-section' });
    wrap.appendChild(el('h2', {}, 'Platform stats'));
    wrap.appendChild(el('p', { class: 'muted' }, 'Quick snapshot of activity on your modifiedS instance.'));
    api.users().then(d => {
      wrap.appendChild(el('div', { class: 'stat-grid' },
        statCard('👥', (d.users || []).length, 'Registered users'),
        statCard('🎓', null, 'Loading courses…'),
      ));
      return api.courses();
    }).then(d => {
      wrap.appendChild(statCard('🎓', (d.courses || []).length, 'Courses published'));
      return api.thoughts();
    }).then(d => {
      wrap.appendChild(statCard('💬', (d.thoughts || []).length, 'Community thoughts'));
      return api.announcements();
    }).then(d => {
      wrap.appendChild(statCard('📢', (d.announcements || []).length, 'Announcements'));
    }).catch(e => wrap.appendChild(viewError(e)));
    return wrap;
  }

  root.appendChild(tabBar);
  root.appendChild(panel);
  renderTab();
}

function field(label, input) {
  return el('label', { class: 'field' },
    el('span', { class: 'field-label' }, label),
    input);
}

function statCard(emoji, value, label) {
  return el('div', { class: 'stat-card' },
    el('div', { class: 'stat-emoji' }, emoji),
    el('div', { class: 'stat-value' }, value === null ? '…' : String(value)),
    el('div', { class: 'stat-label' }, label));
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

  // Show or hide admin nav link based on role
  const adminLink = document.getElementById('nav-admin-link');
  if (adminLink) {
    adminLink.style.display = (state.user && state.user.role === 'admin') ? '' : 'none';
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
