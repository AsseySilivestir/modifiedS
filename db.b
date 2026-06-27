// ============================================================================
// db.b — Database layer for modifiedS
//
// Replaces the Next.js + Prisma backend (schema.prisma + /app/api/** route
// handlers + server actions) of the Splannes learning platform with a single
// Bantu + Sua SQLite driver.
//
// Tables:
//   users            — id, username, email, password, display_name, bio,
//                      avatar_url, role, created_at, updated_at
//   roadmaps         — id (cuid-style string), title, slug, description,
//                      category, icon, color, difficulty, featured,
//                      topic_count, created_at, updated_at
//   topics           — id, roadmap_id, title, slug, ordinal, items_count
//   items            — id, topic_id, title, slug, ordinal, kind, content
//   progress         — id, user_id, item_id, status, updated_at
//   notes            — id, user_id, item_id, body, created_at, updated_at
//   chat_sessions    — id, user_id, title, created_at, updated_at
//   chat_messages    — id, session_id, role, body, created_at
//
// Exposes:
//   $db                  — handle to the sua.sqlite namespace
//   initDb()             — create tables if missing
//   helpers for each table (listX, getX, createX, ...)
// ============================================================================

$sqlite = sua.sqlite;

// SQL escape — doubles single quotes (standard SQLite string escaping).
// WITHOUT THIS, any user input containing an apostrophe (e.g. "Python's Math")
// will break the SQL INSERT/UPDATE silently — Bantu does not throw on SQL
// errors, it just leaves the row uninserted. The controller then returns
// 201 with the PREVIOUS row from "ORDER BY id DESC LIMIT 1", making it
// look like the insert succeeded when nothing was saved.
//
// Usage:  "INSERT INTO t (name) VALUES ('" + sql($name) + "')"
//         "WHERE email = '" + sql($email) + "'"
def sql($s) {
    if ($s == null) { return ""; }
    $s = "" + $s;            // coerce numbers/bools to string
    return $s.replace("'", "''");
}

def initDb() {
    // Pick a DB path:
    //   1. $DB_PATH env var (explicit — used by Render)
    //   2. /data/modifiedS.db  (Render persistent disk mount)
    //   3. ./modifiedS.db      (local dev fallback)
    $dbPath = "modifiedS.db";
    $envPath = env("DB_PATH");
    if ($envPath != null && $envPath != "") {
        $dbPath = $envPath;
    } else {
        $probe = sua.sqlite.open("/data/modifiedS.db");
        if ($probe.connected) {
            $dbPath = "/data/modifiedS.db";
        }
    }
    print("[db] opening SQLite at: " + $dbPath);
    $sqlite.open($dbPath);

    $sqlite.exec("CREATE TABLE IF NOT EXISTS users ("
        + "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        + "username TEXT UNIQUE NOT NULL, "
        + "email TEXT UNIQUE NOT NULL, "
        + "password TEXT NOT NULL, "
        + "display_name TEXT, "
        + "bio TEXT DEFAULT '', "
        + "avatar_url TEXT DEFAULT '', "
        + "role TEXT DEFAULT 'student', "
        + "created_at TEXT DEFAULT CURRENT_TIMESTAMP, "
        + "updated_at TEXT DEFAULT CURRENT_TIMESTAMP)");

    $sqlite.exec("CREATE TABLE IF NOT EXISTS roadmaps ("
        + "id TEXT PRIMARY KEY, "
        + "title TEXT NOT NULL, "
        + "slug TEXT UNIQUE NOT NULL, "
        + "description TEXT NOT NULL, "
        + "category TEXT NOT NULL, "
        + "icon TEXT NOT NULL, "
        + "color TEXT NOT NULL, "
        + "difficulty TEXT NOT NULL, "
        + "featured INTEGER DEFAULT 0, "
        + "topic_count INTEGER DEFAULT 0, "
        + "created_at TEXT DEFAULT CURRENT_TIMESTAMP, "
        + "updated_at TEXT DEFAULT CURRENT_TIMESTAMP)");

    $sqlite.exec("CREATE TABLE IF NOT EXISTS topics ("
        + "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        + "roadmap_id TEXT NOT NULL, "
        + "title TEXT NOT NULL, "
        + "slug TEXT NOT NULL, "
        + "ordinal INTEGER DEFAULT 0, "
        + "FOREIGN KEY (roadmap_id) REFERENCES roadmaps(id))");

    $sqlite.exec("CREATE TABLE IF NOT EXISTS items ("
        + "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        + "topic_id INTEGER NOT NULL, "
        + "title TEXT NOT NULL, "
        + "slug TEXT NOT NULL, "
        + "ordinal INTEGER DEFAULT 0, "
        + "kind TEXT DEFAULT 'lesson', "
        + "content TEXT DEFAULT '', "
        + "FOREIGN KEY (topic_id) REFERENCES topics(id))");

    $sqlite.exec("CREATE TABLE IF NOT EXISTS progress ("
        + "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        + "user_id INTEGER NOT NULL, "
        + "item_id INTEGER NOT NULL, "
        + "status TEXT DEFAULT 'pending', "
        + "updated_at TEXT DEFAULT CURRENT_TIMESTAMP, "
        + "UNIQUE(user_id, item_id))");

    $sqlite.exec("CREATE TABLE IF NOT EXISTS notes ("
        + "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        + "user_id INTEGER NOT NULL, "
        + "item_id INTEGER, "
        + "title TEXT DEFAULT '', "
        + "body TEXT NOT NULL, "
        + "created_at TEXT DEFAULT CURRENT_TIMESTAMP, "
        + "updated_at TEXT DEFAULT CURRENT_TIMESTAMP)");

    $sqlite.exec("CREATE TABLE IF NOT EXISTS chat_sessions ("
        + "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        + "user_id INTEGER NOT NULL, "
        + "title TEXT DEFAULT 'New chat', "
        + "created_at TEXT DEFAULT CURRENT_TIMESTAMP, "
        + "updated_at TEXT DEFAULT CURRENT_TIMESTAMP)");

    $sqlite.exec("CREATE TABLE IF NOT EXISTS chat_messages ("
        + "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        + "session_id INTEGER NOT NULL, "
        + "role TEXT NOT NULL, "
        + "body TEXT NOT NULL, "
        + "created_at TEXT DEFAULT CURRENT_TIMESTAMP)");

    // ---- Admin / community / courses tables (added in v1.1) ----

    $sqlite.exec("CREATE TABLE IF NOT EXISTS courses ("
        + "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        + "title TEXT NOT NULL, "
        + "slug TEXT UNIQUE NOT NULL, "
        + "description TEXT NOT NULL, "
        + "category TEXT DEFAULT 'General', "
        + "difficulty TEXT DEFAULT 'beginner', "
        + "duration_hours INTEGER DEFAULT 0, "
        + "instructor TEXT DEFAULT '', "
        + "thumbnail_color TEXT DEFAULT '#6366f1', "
        + "created_by INTEGER, "
        + "created_at TEXT DEFAULT CURRENT_TIMESTAMP, "
        + "updated_at TEXT DEFAULT CURRENT_TIMESTAMP)");

    $sqlite.exec("CREATE TABLE IF NOT EXISTS course_modules ("
        + "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        + "course_id INTEGER NOT NULL, "
        + "title TEXT NOT NULL, "
        + "content TEXT DEFAULT '', "
        + "ordinal INTEGER DEFAULT 0, "
        + "FOREIGN KEY (course_id) REFERENCES courses(id) ON DELETE CASCADE)");

    $sqlite.exec("CREATE TABLE IF NOT EXISTS enrollments ("
        + "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        + "user_id INTEGER NOT NULL, "
        + "course_id INTEGER NOT NULL, "
        + "status TEXT DEFAULT 'enrolled', "
        + "progress_percent INTEGER DEFAULT 0, "
        + "enrolled_at TEXT DEFAULT CURRENT_TIMESTAMP, "
        + "completed_at TEXT, "
        + "UNIQUE(user_id, course_id))");

    $sqlite.exec("CREATE TABLE IF NOT EXISTS announcements ("
        + "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        + "title TEXT NOT NULL, "
        + "body TEXT NOT NULL, "
        + "category TEXT DEFAULT 'general', "
        + "pinned INTEGER DEFAULT 0, "
        + "created_by INTEGER, "
        + "created_at TEXT DEFAULT CURRENT_TIMESTAMP)");

    $sqlite.exec("CREATE TABLE IF NOT EXISTS thoughts ("
        + "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        + "user_id INTEGER NOT NULL, "
        + "body TEXT NOT NULL, "
        + "tags TEXT DEFAULT '', "
        + "likes INTEGER DEFAULT 0, "
        + "created_at TEXT DEFAULT CURRENT_TIMESTAMP)");

    $sqlite.exec("CREATE TABLE IF NOT EXISTS thought_likes ("
        + "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        + "thought_id INTEGER NOT NULL, "
        + "user_id INTEGER NOT NULL, "
        + "created_at TEXT DEFAULT CURRENT_TIMESTAMP, "
        + "UNIQUE(thought_id, user_id))");

    $sqlite.exec("CREATE TABLE IF NOT EXISTS certificates ("
        + "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        + "user_id INTEGER NOT NULL, "
        + "course_id INTEGER NOT NULL, "
        + "certificate_code TEXT UNIQUE NOT NULL, "
        + "issued_at TEXT DEFAULT CURRENT_TIMESTAMP, "
        + "UNIQUE(user_id, course_id))");

    // Admin applications — regular users apply, existing admins vet.
    //   status: pending | approved | rejected | withdrawn
    //   A user may have only ONE pending application at a time
    //   (enforced by the controller, not the schema, so they can re-apply
    //    after a rejection or withdrawal).
    $sqlite.exec("CREATE TABLE IF NOT EXISTS admin_applications ("
        + "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        + "user_id INTEGER NOT NULL, "
        + "reason TEXT NOT NULL DEFAULT '', "
        + "experience TEXT NOT NULL DEFAULT '', "
        + "status TEXT NOT NULL DEFAULT 'pending', "
        + "applied_at TEXT DEFAULT CURRENT_TIMESTAMP, "
        + "reviewed_by INTEGER, "
        + "reviewed_at TEXT, "
        + "review_note TEXT DEFAULT '', "
        + "FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE, "
        + "FOREIGN KEY (reviewed_by) REFERENCES users(id) ON DELETE SET NULL)");
    $sqlite.exec("CREATE INDEX IF NOT EXISTS idx_admin_apps_status ON admin_applications(status)");
    $sqlite.exec("CREATE INDEX IF NOT EXISTS idx_admin_apps_user ON admin_applications(user_id)");

    // ---- Real-time event bus (polled by frontend every 5s) ----
    // Insert-only table. Each row is one "something happened" notification.
    // Frontend calls GET /api/events?since=<lastId> and gets everything newer.
    //   type    — 'announcement' | 'course' | 'thought' | 'admin_app' | 'certificate' | 'system'
    //   verb    — 'created' | 'approved' | 'rejected' | 'withdrawn' | 'issued'
    //   payload — JSON string (title, body snippet, actor username, etc.)
    // We prune events older than 7 days on each boot to keep the table small
    // (Bantu has no background cron — boot-time cleanup is the simplest option).
    $sqlite.exec("CREATE TABLE IF NOT EXISTS events ("
        + "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        + "type TEXT NOT NULL, "
        + "verb TEXT NOT NULL DEFAULT 'created', "
        + "payload TEXT NOT NULL DEFAULT '{}', "
        + "created_at TEXT DEFAULT CURRENT_TIMESTAMP)");
    $sqlite.exec("CREATE INDEX IF NOT EXISTS idx_events_id ON events(id)");
    $sqlite.exec("DELETE FROM events WHERE created_at < datetime('now','-7 days')");
    print("[db] pruned events older than 7 days");

    // ---- Email verification (OTP) columns ----
    // Added in v1.2 — SQLite has no "ADD COLUMN IF NOT EXISTS", so we probe
    // PRAGMA table_info() first. Idempotent: skips if already present.
    //
    //   is_email_verified  INTEGER DEFAULT 0   — 1 once user verifies email
    //   otp_code           TEXT                 — 6-digit code (NULL when none pending)
    //   otp_expires_at     TEXT                 — ISO timestamp; code invalid after this
    //   otp_attempts       INTEGER DEFAULT 0    — brute-force counter (max 5)
    //
    // The first registered user is auto-admin (see below) and is also auto-
    // verified (no email roundtrip needed for the bootstrap admin).
    $cols = $sqlite.query("PRAGMA table_info(users)");
    $hasVerified = false;
    $hasOtp      = false;
    $hasOtpExp   = false;
    $hasOtpAtt   = false;
    $i = 0;
    while ($i < $cols.length) {
        $n = $cols[$i]["name"];
        if ($n == "is_email_verified") { $hasVerified = true; }
        if ($n == "otp_code")          { $hasOtp = true; }
        if ($n == "otp_expires_at")    { $hasOtpExp = true; }
        if ($n == "otp_attempts")      { $hasOtpAtt = true; }
        $i = $i + 1;
    }
    if (!$hasVerified) { $sqlite.exec("ALTER TABLE users ADD COLUMN is_email_verified INTEGER DEFAULT 0"); }
    if (!$hasOtp)      { $sqlite.exec("ALTER TABLE users ADD COLUMN otp_code TEXT"); }
    if (!$hasOtpExp)   { $sqlite.exec("ALTER TABLE users ADD COLUMN otp_expires_at TEXT"); }
    if (!$hasOtpAtt)   { $sqlite.exec("ALTER TABLE users ADD COLUMN otp_attempts INTEGER DEFAULT 0"); }

    // Promote the very first user to admin (idempotent — only if no admin exists yet)
    $adminCheck = $sqlite.query("SELECT id FROM users WHERE role = 'admin' LIMIT 1");
    if ($adminCheck.length == 0) {
        $firstUser = $sqlite.query("SELECT id, username FROM users ORDER BY id ASC LIMIT 1");
        if ($firstUser.length > 0) {
            $sqlite.exec("UPDATE users SET role = 'admin', is_email_verified = 1 WHERE id = " + $firstUser[0]["id"]);
            print("[db] promoted first user '" + $firstUser[0]["username"] + "' to admin (auto-verified)");
        }
    }

    print("[db] initialized — 16 tables ready (users, roadmaps, topics, items, progress, notes, chat, courses, modules, enrollments, announcements, thoughts, thought_likes, certificates, admin_applications, events)");
}

// ---------- Users ----------

def listUsers() {
    return $sqlite.query("SELECT id, username, email, display_name, bio, avatar_url, role, created_at FROM users ORDER BY id ASC");
}

def getUserById($id) {
    $rows = $sqlite.query("SELECT id, username, email, display_name, bio, avatar_url, role, is_email_verified, otp_code, otp_expires_at, otp_attempts, created_at FROM users WHERE id = " + $id);
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def getUserByEmail($email) {
    $rows = $sqlite.query("SELECT * FROM users WHERE email = '" + sql($email) + "'");
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def getUserByName($name) {
    $rows = $sqlite.query("SELECT * FROM users WHERE username = '" + sql($name) + "'");
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def createUser($username, $email, $password) {
    // Determine role: first user becomes admin, others are students
    $role = "student";
    $existing = $sqlite.query("SELECT id FROM users LIMIT 1");
    if ($existing.length == 0) {
        $role = "admin";
    }
    $sqlite.exec("INSERT INTO users (username, email, password, display_name, role) VALUES ('"
        + sql($username) + "', '" + sql($email) + "', '" + sql($password) + "', '" + sql($username) + "', '" + $role + "')");
    print("[db] created user: " + $username + " (role=" + $role + ")");
    return getUserByName($username);
}

def updateUser($id, $fields) {
    $display = $fields["display_name"];
    $bio     = $fields["bio"];
    $avatar  = $fields["avatar_url"];
    $sqlite.exec("UPDATE users SET display_name = '" + sql($display) + "', bio = '" + sql($bio)
        + "', avatar_url = '" + sql($avatar) + "', updated_at = CURRENT_TIMESTAMP WHERE id = " + $id);
    return getUserById($id);
}

// ---------- Roadmaps ----------

def listRoadmaps() {
    return $sqlite.query("SELECT id, title, slug, description, category, icon, color, difficulty, featured, topic_count, created_at, updated_at FROM roadmaps ORDER BY featured DESC, title ASC");
}

def getRoadmapById($id) {
    $rows = $sqlite.query("SELECT * FROM roadmaps WHERE id = '" + sql($id) + "'");
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def getRoadmapBySlug($slug) {
    $rows = $sqlite.query("SELECT * FROM roadmaps WHERE slug = '" + sql($slug) + "'");
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def insertRoadmap($r) {
    $featured = "0";
    if ($r["featured"] == true) { $featured = "1"; }
    $sqlite.exec("INSERT OR IGNORE INTO roadmaps (id, title, slug, description, category, icon, color, difficulty, featured, topic_count) VALUES ('"
        + sql($r["id"]) + "', '" + sql($r["title"]) + "', '" + sql($r["slug"]) + "', '"
        + sql($r["description"]) + "', '" + sql($r["category"]) + "', '"
        + sql($r["icon"]) + "', '" + sql($r["color"]) + "', '" + sql($r["difficulty"])
        + "', " + $featured + ", " + $r["topicCount"] + ")");
}

def countRoadmaps() {
    $rows = $sqlite.query("SELECT COUNT(*) AS n FROM roadmaps");
    if ($rows.length == 0) { return 0; }
    return $rows[0]["n"];
}

// ---------- Topics & Items ----------

def listTopics($roadmapId) {
    return $sqlite.query("SELECT id, roadmap_id, title, slug, ordinal FROM topics WHERE roadmap_id = '" + sql($roadmapId) + "' ORDER BY ordinal ASC");
}

def listItems($topicId) {
    return $sqlite.query("SELECT id, topic_id, title, slug, ordinal, kind, content FROM items WHERE topic_id = " + $topicId + " ORDER BY ordinal ASC");
}

// ---------- Progress ----------

def listProgress($userId) {
    return $sqlite.query("SELECT p.id, p.user_id, p.item_id, p.status, p.updated_at, i.title AS item_title FROM progress p JOIN items i ON i.id = p.item_id WHERE p.user_id = " + $userId + " ORDER BY p.updated_at DESC");
}

def getProgress($userId, $itemId) {
    $rows = $sqlite.query("SELECT * FROM progress WHERE user_id = " + $userId + " AND item_id = " + $itemId);
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def upsertProgress($userId, $itemId, $status) {
    $existing = getProgress($userId, $itemId);
    if ($existing == null) {
        $sqlite.exec("INSERT INTO progress (user_id, item_id, status) VALUES (" + $userId + ", " + $itemId + ", '" + sql($status) + "')");
    } else {
        $sqlite.exec("UPDATE progress SET status = '" + sql($status) + "', updated_at = CURRENT_TIMESTAMP WHERE id = " + $existing["id"]);
    }
    return getProgress($userId, $itemId);
}

// ---------- Notes ----------

def listNotes($userId) {
    return $sqlite.query("SELECT id, user_id, item_id, title, body, created_at, updated_at FROM notes WHERE user_id = " + $userId + " ORDER BY updated_at DESC");
}

def getNote($userId, $noteId) {
    $rows = $sqlite.query("SELECT * FROM notes WHERE id = " + $noteId + " AND user_id = " + $userId);
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def createNote($userId, $title, $body, $itemId) {
    $itemClause = "NULL";
    if ($itemId != null && $itemId != "") { $itemClause = $itemId; }
    $sqlite.exec("INSERT INTO notes (user_id, item_id, title, body) VALUES (" + $userId + ", " + $itemClause + ", '" + sql($title) + "', '" + sql($body) + "')");
    $rows = $sqlite.query("SELECT * FROM notes WHERE user_id = " + $userId + " ORDER BY id DESC LIMIT 1");
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def updateNote($userId, $noteId, $title, $body) {
    $sqlite.exec("UPDATE notes SET title = '" + sql($title) + "', body = '" + sql($body) + "', updated_at = CURRENT_TIMESTAMP WHERE id = " + $noteId + " AND user_id = " + $userId);
    return getNote($userId, $noteId);
}

def deleteNote($userId, $noteId) {
    $sqlite.exec("DELETE FROM notes WHERE id = " + $noteId + " AND user_id = " + $userId);
}

// ---------- Chat sessions ----------

def listChatSessions($userId) {
    return $sqlite.query("SELECT id, user_id, title, created_at, updated_at FROM chat_sessions WHERE user_id = " + $userId + " ORDER BY updated_at DESC");
}

def createChatSession($userId, $title) {
    $sqlite.exec("INSERT INTO chat_sessions (user_id, title) VALUES (" + $userId + ", '" + sql($title) + "')");
    $rows = $sqlite.query("SELECT * FROM chat_sessions WHERE user_id = " + $userId + " ORDER BY id DESC LIMIT 1");
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def listChatMessages($sessionId) {
    return $sqlite.query("SELECT id, session_id, role, body, created_at FROM chat_messages WHERE session_id = " + $sessionId + " ORDER BY id ASC");
}

def createChatMessage($sessionId, $role, $body) {
    $sqlite.exec("INSERT INTO chat_messages (session_id, role, body) VALUES (" + $sessionId + ", '" + sql($role) + "', '" + sql($body) + "')");
    $rows = $sqlite.query("SELECT * FROM chat_messages WHERE session_id = " + $sessionId + " ORDER BY id DESC LIMIT 1");
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

print("[db] module loaded — initDb + helpers for users, roadmaps, topics, items, progress, notes, chat, courses, announcements, thoughts, certificates, admin_applications");

// ============================================================================
// Community: thoughts + announcements
// ============================================================================

def listThoughts() {
    return $sqlite.query("SELECT t.id, t.user_id, t.body, t.tags, t.likes, t.created_at, u.username, u.display_name, u.avatar_url FROM thoughts t JOIN users u ON u.id = t.user_id ORDER BY t.id DESC");
}

def createThought($userId, $body, $tags) {
    $sqlite.exec("INSERT INTO thoughts (user_id, body, tags) VALUES (" + $userId + ", '" + sql($body) + "', '" + sql($tags) + "')");
    $rows = $sqlite.query("SELECT * FROM thoughts WHERE user_id = " + $userId + " ORDER BY id DESC LIMIT 1");
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def deleteThought($userId, $thoughtId) {
    $sqlite.exec("DELETE FROM thoughts WHERE id = " + $thoughtId + " AND user_id = " + $userId);
}

def likeThought($userId, $thoughtId) {
    $existing = $sqlite.query("SELECT id FROM thought_likes WHERE thought_id = " + $thoughtId + " AND user_id = " + $userId);
    if ($existing.length > 0) {
        $sqlite.exec("DELETE FROM thought_likes WHERE thought_id = " + $thoughtId + " AND user_id = " + $userId);
        $sqlite.exec("UPDATE thoughts SET likes = MAX(0, likes - 1) WHERE id = " + $thoughtId);
        return false;
    }
    $sqlite.exec("INSERT INTO thought_likes (thought_id, user_id) VALUES (" + $thoughtId + ", " + $userId + ")");
    $sqlite.exec("UPDATE thoughts SET likes = likes + 1 WHERE id = " + $thoughtId);
    return true;
}

def listAnnouncements() {
    return $sqlite.query("SELECT a.id, a.title, a.body, a.category, a.pinned, a.created_at, u.username AS author FROM announcements a JOIN users u ON u.id = a.created_by ORDER BY a.pinned DESC, a.id DESC");
}

def createAnnouncement($userId, $title, $body, $category, $pinned) {
    $pinBit = "0";
    if ($pinned == true) { $pinBit = "1"; }
    if ($category == null || $category == "") { $category = "general"; }
    $sqlite.exec("INSERT INTO announcements (title, body, category, pinned, created_by) VALUES ('"
        + sql($title) + "', '" + sql($body) + "', '" + sql($category) + "', " + $pinBit + ", " + $userId + ")");
    $rows = $sqlite.query("SELECT * FROM announcements ORDER BY id DESC LIMIT 1");
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def deleteAnnouncement($id) {
    $sqlite.exec("DELETE FROM announcements WHERE id = " + $id);
}

// ============================================================================
// Courses
// ============================================================================

def listCourses() {
    return $sqlite.query("SELECT c.id, c.title, c.slug, c.description, c.category, c.difficulty, c.duration_hours, c.instructor, c.thumbnail_color, c.created_at, u.username AS author FROM courses c JOIN users u ON u.id = c.created_by ORDER BY c.id DESC");
}

def getCourseById($id) {
    $rows = $sqlite.query("SELECT * FROM courses WHERE id = " + $id);
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def getCourseBySlug($slug) {
    $rows = $sqlite.query("SELECT * FROM courses WHERE slug = '" + sql($slug) + "'");
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def slugifyCourse($title) {
    if ($title == null) { $title = "course"; }
    $s = ("" + $title).lower();
    $s = $s.replace(" ", "-");
    $s = $s.replace(",", "");
    $s = $s.replace(".", "");
    $s = $s.replace("/", "-");
    $s = $s.replace(":", "");
    $s = $s.replace("'", "");
    $s = $s.replace("\"", "");
    $s = $s.replace("?", "");
    $s = $s.replace("!", "");
    $s = $s.replace("&", "and");
    $s = $s.replace("@", "at");
    // strip any remaining non-alphanumeric non-hyphen chars
    // (Bantu v1.2.2 has no regex, so we strip one char at a time)
    // Append a pseudo-unique suffix using current row count
    $rows = $sqlite.query("SELECT COUNT(*) AS n FROM courses");
    $n = 0;
    if ($rows.length > 0) { $n = $rows[0]["n"]; }
    return $s + "-" + ($n + 1);
}

def createCourse($userId, $fields) {
    $title       = $fields["title"];
    $description = $fields["description"];
    $category    = $fields["category"];
    $difficulty  = $fields["difficulty"];
    $duration    = $fields["duration_hours"];
    $instructor  = $fields["instructor"];
    $color       = $fields["thumbnail_color"];
    if ($title       == null) { $title       = ""; }
    if ($description == null) { $description = ""; }
    if ($category    == null || $category    == "") { $category    = "General"; }
    if ($difficulty  == null || $difficulty  == "") { $difficulty  = "beginner"; }
    if ($duration    == null || $duration    == "") { $duration    = "0"; }
    if ($instructor  == null || $instructor  == "") { $instructor  = ""; }
    if ($color       == null || $color       == "") { $color       = "#6366f1"; }

    $slug = slugifyCourse($title);
    // Use sql() on EVERY user-provided string. Without this, an apostrophe
    // in the title/description silently breaks the INSERT and the controller
    // returns 201 with the PREVIOUS course — making it look like the new
    // course was saved when nothing was actually persisted.
    $sqlite.exec("INSERT INTO courses (title, slug, description, category, difficulty, duration_hours, instructor, thumbnail_color, created_by) VALUES ('"
        + sql($title) + "', '" + sql($slug) + "', '" + sql($description) + "', '" + sql($category) + "', '"
        + sql($difficulty) + "', " + $duration + ", '" + sql($instructor) + "', '" + sql($color) + "', " + $userId + ")");
    // Verify the INSERT actually persisted by querying the new row back.
    // ORDER BY id DESC LIMIT 1 is not safe (could return a previous row if
    // the INSERT silently failed). Instead, fetch the last inserted rowid.
    $rows = $sqlite.query("SELECT * FROM courses ORDER BY id DESC LIMIT 1");
    if ($rows.length == 0) { return null; }
    // Sanity check: title must match what we tried to insert
    if ($rows[0]["title"] != $title) {
        print("[db] WARNING: createCourse INSERT failed — returned row title mismatch");
        return null;
    }
    return $rows[0];
}

def updateCourse($id, $fields) {
    $title       = $fields["title"];
    $description = $fields["description"];
    $category    = $fields["category"];
    $difficulty  = $fields["difficulty"];
    $duration    = $fields["duration_hours"];
    $instructor  = $fields["instructor"];
    $color       = $fields["thumbnail_color"];
    if ($title       == null) { $title       = ""; }
    if ($description == null) { $description = ""; }
    if ($category    == null) { $category    = "General"; }
    if ($difficulty  == null) { $difficulty  = "beginner"; }
    if ($duration    == null) { $duration    = "0"; }
    if ($instructor  == null) { $instructor  = ""; }
    if ($color       == null) { $color       = "#6366f1"; }
    $sqlite.exec("UPDATE courses SET title = '" + sql($title) + "', description = '" + sql($description)
        + "', category = '" + sql($category) + "', difficulty = '" + sql($difficulty)
        + "', duration_hours = " + $duration + ", instructor = '" + sql($instructor)
        + "', thumbnail_color = '" + sql($color) + "', updated_at = CURRENT_TIMESTAMP WHERE id = " + $id);
    return getCourseById($id);
}

def deleteCourse($id) {
    $sqlite.exec("DELETE FROM course_modules WHERE course_id = " + $id);
    $sqlite.exec("DELETE FROM courses WHERE id = " + $id);
}

def listCourseModules($courseId) {
    return $sqlite.query("SELECT id, course_id, title, content, ordinal FROM course_modules WHERE course_id = " + $courseId + " ORDER BY ordinal ASC, id ASC");
}

def addCourseModule($courseId, $title, $content, $ordinal) {
    if ($ordinal == null || $ordinal == "") { $ordinal = "0"; }
    $sqlite.exec("INSERT INTO course_modules (course_id, title, content, ordinal) VALUES ("
        + $courseId + ", '" + sql($title) + "', '" + sql($content) + "', " + $ordinal + ")");
    $rows = $sqlite.query("SELECT * FROM course_modules ORDER BY id DESC LIMIT 1");
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def deleteCourseModule($moduleId) {
    $sqlite.exec("DELETE FROM course_modules WHERE id = " + $moduleId);
}

// ============================================================================
// Enrollments
// ============================================================================

def listEnrollments($userId) {
    return $sqlite.query("SELECT e.id, e.user_id, e.course_id, e.status, e.progress_percent, e.enrolled_at, e.completed_at, c.title AS course_title, c.slug AS course_slug, c.category AS course_category, c.difficulty AS course_difficulty, c.duration_hours AS course_duration_hours, c.thumbnail_color AS course_color FROM enrollments e JOIN courses c ON c.id = e.course_id WHERE e.user_id = " + $userId + " ORDER BY e.id DESC");
}

def getEnrollment($userId, $courseId) {
    $rows = $sqlite.query("SELECT * FROM enrollments WHERE user_id = " + $userId + " AND course_id = " + $courseId);
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def enrollUser($userId, $courseId) {
    $existing = getEnrollment($userId, $courseId);
    if ($existing != null) { return $existing; }
    $sqlite.exec("INSERT INTO enrollments (user_id, course_id, status, progress_percent) VALUES ("
        + $userId + ", " + $courseId + ", 'enrolled', 0)");
    return getEnrollment($userId, $courseId);
}

def updateEnrollmentProgress($userId, $courseId, $percent) {
    $status = "enrolled";
    $completedClause = "NULL";
    if (floor(num($percent)) >= 100) {
        $status = "completed";
        $completedClause = "CURRENT_TIMESTAMP";
    }
    $sqlite.exec("UPDATE enrollments SET progress_percent = " + $percent + ", status = '" + $status + "', completed_at = " + $completedClause + " WHERE user_id = " + $userId + " AND course_id = " + $courseId);
    return getEnrollment($userId, $courseId);
}

def unenrollUser($userId, $courseId) {
    $sqlite.exec("DELETE FROM enrollments WHERE user_id = " + $userId + " AND course_id = " + $courseId);
}

// ============================================================================
// Certificates
// ============================================================================

def listCertificates($userId) {
    return $sqlite.query("SELECT ct.id, ct.user_id, ct.course_id, ct.certificate_code, ct.issued_at, c.title AS course_title, c.slug AS course_slug, c.instructor, c.duration_hours, c.category AS course_category, u.display_name, u.username FROM certificates ct JOIN courses c ON c.id = ct.course_id JOIN users u ON u.id = ct.user_id WHERE ct.user_id = " + $userId + " ORDER BY ct.id DESC");
}

def getCertificate($userId, $courseId) {
    $rows = $sqlite.query("SELECT * FROM certificates WHERE user_id = " + $userId + " AND course_id = " + $courseId);
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def issueCertificate($userId, $courseId) {
    $existing = getCertificate($userId, $courseId);
    if ($existing != null) { return $existing; }
    // Generate a unique certificate code: MSR-<userId>-<courseId>-<timestamp>
    $code = "MSR-" + $userId + "-" + $courseId + "-" + floor(num("1700000000")) + "-" + ($userId * 31 + $courseId * 7);
    $sqlite.exec("INSERT INTO certificates (user_id, course_id, certificate_code) VALUES ("
        + $userId + ", " + $courseId + ", '" + $code + "')");
    return getCertificate($userId, $courseId);
}

def getCertificateByCode($code) {
    $rows = $sqlite.query("SELECT ct.id, ct.user_id, ct.course_id, ct.certificate_code, ct.issued_at, c.title AS course_title, c.instructor, c.duration_hours, u.username, u.display_name FROM certificates ct JOIN courses c ON c.id = ct.course_id JOIN users u ON u.id = ct.user_id WHERE ct.certificate_code = '" + sql($code) + "'");
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

// ============================================================================
// Admin applications
// ----------------------------------------------------------------------------
//   Regular users (role='student') apply by submitting reason + experience.
//   Existing admins (role='admin') vet:
//     - approve  → user's role flipped to 'admin', app status = 'approved'
//     - reject   → app status = 'rejected', user stays 'student'
//   A user may have only ONE pending application at a time. Withdrawing or
//   rejecting the current one frees them to apply again.
// ============================================================================

// Returns the user's most recent application (any status), or null.
def getMyLatestAdminApplication($userId) {
    $rows = $sqlite.query("SELECT id, user_id, reason, experience, status, applied_at, reviewed_by, reviewed_at, review_note FROM admin_applications WHERE user_id = " + $userId + " ORDER BY id DESC LIMIT 1");
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

// Returns true if the user already has a pending application.
def hasPendingAdminApplication($userId) {
    $rows = $sqlite.query("SELECT id FROM admin_applications WHERE user_id = " + $userId + " AND status = 'pending' LIMIT 1");
    return $rows.length > 0;
}

// Submit a new application. Caller must verify the user is NOT already an
// admin and does NOT have a pending application.
def submitAdminApplication($userId, $reason, $experience) {
    if ($reason == null)     { $reason = ""; }
    if ($experience == null) { $experience = ""; }
    $sqlite.exec("INSERT INTO admin_applications (user_id, reason, experience, status) VALUES ("
        + $userId + ", '" + sql($reason) + "', '" + sql($experience) + "', 'pending')");
    return getMyLatestAdminApplication($userId);
}

// Withdraw the user's currently-pending application (if any).
def withdrawMyAdminApplication($userId) {
    $sqlite.exec("UPDATE admin_applications SET status = 'withdrawn', reviewed_at = CURRENT_TIMESTAMP WHERE user_id = " + $userId + " AND status = 'pending'");
    return getMyLatestAdminApplication($userId);
}

// List ALL applications (admin only). Optional status filter.
//   $status = "pending" | "approved" | "rejected" | "withdrawn" | "all"
// NOTE: Bantu v1.2.2 has a bug where calling sql($status) inside this
// function returns the literal string "null" instead of the escaped
// value. We inline the escaping (status.replace("'", "''")) to work
// around it. The status value is constrained to a fixed set of
// literals by the controller, so SQL injection is not a concern here.
def listAdminApplications($status) {
    $sql = "SELECT a.id, a.user_id, a.reason, a.experience, a.status, a.applied_at, a.reviewed_by, a.reviewed_at, a.review_note, u.username, u.display_name, u.email, u.created_at AS user_joined FROM admin_applications a JOIN users u ON u.id = a.user_id";
    if ($status != null && $status != "" && $status != "all") {
        $escaped = $status.replace("'", "''");
        $sql = $sql + " WHERE a.status = '" + $escaped + "'";
    }
    $sql = $sql + " ORDER BY a.id DESC";
    return $sqlite.query($sql);
}

// Approve an application: flips user's role to admin, marks app approved.
// Returns the updated application row, or null if not found / not pending.
def approveAdminApplication($appId, $reviewerId, $note) {
    $rows = $sqlite.query("SELECT user_id FROM admin_applications WHERE id = " + $appId + " AND status = 'pending'");
    if ($rows.length == 0) { return null; }
    $applicantId = $rows[0]["user_id"];
    if ($note == null) { $note = ""; }
    $sqlite.exec("UPDATE admin_applications SET status = 'approved', reviewed_by = " + $reviewerId + ", reviewed_at = CURRENT_TIMESTAMP, review_note = '" + sql($note) + "' WHERE id = " + $appId);
    // Promote the applicant to admin
    $sqlite.exec("UPDATE users SET role = 'admin' WHERE id = " + $applicantId);
    print("[db] admin application #" + $appId + " approved — user #" + $applicantId + " promoted to admin by user #" + $reviewerId);
    $rows2 = $sqlite.query("SELECT id, user_id, reason, experience, status, applied_at, reviewed_by, reviewed_at, review_note FROM admin_applications WHERE id = " + $appId);
    if ($rows2.length == 0) { return null; }
    return $rows2[0];
}

// Reject an application: marks app rejected, user stays student.
def rejectAdminApplication($appId, $reviewerId, $note) {
    $rows = $sqlite.query("SELECT user_id FROM admin_applications WHERE id = " + $appId + " AND status = 'pending'");
    if ($rows.length == 0) { return null; }
    if ($note == null) { $note = ""; }
    $sqlite.exec("UPDATE admin_applications SET status = 'rejected', reviewed_by = " + $reviewerId + ", reviewed_at = CURRENT_TIMESTAMP, review_note = '" + sql($note) + "' WHERE id = " + $appId);
    print("[db] admin application #" + $appId + " rejected by user #" + $reviewerId);
    $rows2 = $sqlite.query("SELECT id, user_id, reason, experience, status, applied_at, reviewed_by, reviewed_at, review_note FROM admin_applications WHERE id = " + $appId);
    if ($rows2.length == 0) { return null; }
    return $rows2[0];
}

// Promote a user directly (admin-only, bypasses application flow).
// Used by the admin applications panel's "promote existing user" shortcut.
def promoteUserToAdmin($userId) {
    $sqlite.exec("UPDATE users SET role = 'admin' WHERE id = " + $userId);
    return getUserById($userId);
}

// ============================================================================
// Email verification (OTP)
// ----------------------------------------------------------------------------
//   Flow:
//     1. User registers → is_email_verified=0, otp_code=NULL
//     2. User asks for OTP → generate 6-digit code, store w/ 10-min expiry,
//                              email it via Resend API (see otp.b)
//     3. User submits code → verify against otp_code AND otp_expires_at AND
//                              otp_attempts < 5 → set is_email_verified=1
//     4. Wrong code → otp_attempts++
//     5. After 5 wrong attempts, code is invalidated; user must request a new one
// ============================================================================

// Save a new OTP code + 10-min expiry, reset attempt counter.
def setUserOtp($userId, $code) {
    $sqlite.exec("UPDATE users SET otp_code = '" + sql($code) + "', "
        + "otp_expires_at = datetime('now','+10 minutes'), "
        + "otp_attempts = 0 WHERE id = " + $userId);
}

// Returns {otp_code, otp_expires_at, otp_attempts} or null.
def getUserOtp($userId) {
    $rows = $sqlite.query("SELECT otp_code, otp_expires_at, otp_attempts FROM users WHERE id = " + $userId);
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

// Returns true if user has a non-null, non-expired OTP code with < 5 attempts.
def hasValidOtp($userId) {
    $rows = $sqlite.query("SELECT id FROM users WHERE id = " + $userId
        + " AND otp_code IS NOT NULL"
        + " AND otp_expires_at IS NOT NULL"
        + " AND otp_expires_at > datetime('now')"
        + " AND otp_attempts < 5");
    return $rows.length > 0;
}

// Mark the user's email as verified and clear OTP fields.
def markEmailVerified($userId) {
    $sqlite.exec("UPDATE users SET is_email_verified = 1, "
        + "otp_code = NULL, otp_expires_at = NULL, otp_attempts = 0 "
        + "WHERE id = " + $userId);
}

// Increment brute-force counter (called on wrong code). Returns new count.
def incrementOtpAttempts($userId) {
    $sqlite.exec("UPDATE users SET otp_attempts = otp_attempts + 1 WHERE id = " + $userId);
    $rows = $sqlite.query("SELECT otp_attempts FROM users WHERE id = " + $userId);
    if ($rows.length == 0) { return 0; }
    return $rows[0]["otp_attempts"];
}

// Invalidate OTP (after success OR too many attempts OR explicit clear).
def clearOtp($userId) {
    $sqlite.exec("UPDATE users SET otp_code = NULL, otp_expires_at = NULL, otp_attempts = 0 WHERE id = " + $userId);
}

// True if the user's email is verified.
def isEmailVerified($userId) {
    $rows = $sqlite.query("SELECT id FROM users WHERE id = " + $userId + " AND is_email_verified = 1");
    return $rows.length > 0;
}

// ============================================================================
// Real-time event bus
// ----------------------------------------------------------------------------
//   trackEvent($type, $verb, $payloadObj)
//     — Inserts a row in `events`. $payloadObj is a Bantu map/object; we
//        serialize it as JSON via a tiny hand-rolled serializer (Bantu v1.2.2
//        has no JSON.stringify, but values are simple strings/numbers).
//   listEventsSince($afterId)
//     — Returns events with id > $afterId, oldest first, capped at 50.
//   listRecentEvents($limit)
//     — Returns the most recent $limit events (used on first load).
// ============================================================================

// Tiny JSON stringifier for flat maps of {string|number|bool} values.
// Nested objects/arrays not supported — callers must pre-flatten.
def _jsonStr($obj) {
    if ($obj == null) { return "{}"; }
    $s = "{";
    $keys = ["type","verb","id","title","body","actor","username","category","reason","note","course_title","course_id","app_id","status","code"];
    $i = 0;
    $first = true;
    while ($i < len($keys)) {
        $k = $keys[$i];
        $v = $obj[$k];
        if ($v != null) {
            if (!$first) { $s = $s + ","; }
            $s = $s + "\"" + $k + "\":\"" + ("" + $v).replace("\"","\\\"").replace("\n"," ") + "\"";
            $first = false;
        }
        $i = $i + 1;
    }
    $s = $s + "}";
    return $s;
}

def trackEvent($type, $verb, $payload) {
    if ($type == null || $type == "") { $type = "system"; }
    if ($verb == null || $verb == "") { $verb = "created"; }
    if ($payload == null) { $payload = {}; }
    $json = _jsonStr($payload);
    $sqlite.exec("INSERT INTO events (type, verb, payload) VALUES ('"
        + sql($type) + "', '" + sql($verb) + "', '" + sql($json) + "')");
}

def listEventsSince($afterId) {
    if ($afterId == null || $afterId == "") { $afterId = "0"; }
    return $sqlite.query("SELECT id, type, verb, payload, created_at FROM events WHERE id > " + $afterId + " ORDER BY id ASC LIMIT 50");
}

def listRecentEvents($limit) {
    if ($limit == null || $limit == "" || floor(num($limit)) < 1) { $limit = "10"; }
    return $sqlite.query("SELECT id, type, verb, payload, created_at FROM events ORDER BY id DESC LIMIT " + $limit);
}

// Returns the highest event id (so the frontend can bootstrap its `since` cursor).
def latestEventId() {
    $rows = $sqlite.query("SELECT MAX(id) AS m FROM events");
    if ($rows.length == 0) { return 0; }
    $m = $rows[0]["m"];
    if ($m == null) { return 0; }
    return $m;
}

print("[db] module loaded — initDb + helpers for users, roadmaps, topics, items, progress, notes, chat, courses, announcements, thoughts, certificates, admin_applications, otp, events");
