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

def initDb() {
    $sqlite.open("modifiedS.db");

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

    print("[db] initialized — 8 tables ready");
}

// ---------- Users ----------

def listUsers() {
    return $sqlite.query("SELECT id, username, email, display_name, bio, avatar_url, role, created_at FROM users ORDER BY id ASC");
}

def getUserById($id) {
    $rows = $sqlite.query("SELECT id, username, email, display_name, bio, avatar_url, role, created_at FROM users WHERE id = " + $id);
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def getUserByEmail($email) {
    $rows = $sqlite.query("SELECT * FROM users WHERE email = '" + $email + "'");
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def getUserByName($name) {
    $rows = $sqlite.query("SELECT * FROM users WHERE username = '" + $name + "'");
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def createUser($username, $email, $password) {
    $sqlite.exec("INSERT INTO users (username, email, password, display_name) VALUES ('"
        + $username + "', '" + $email + "', '" + $password + "', '" + $username + "')");
    print("[db] created user: " + $username);
    return getUserByName($username);
}

def updateUser($id, $fields) {
    $display = $fields["display_name"];
    $bio     = $fields["bio"];
    $avatar  = $fields["avatar_url"];
    $sqlite.exec("UPDATE users SET display_name = '" + $display + "', bio = '" + $bio
        + "', avatar_url = '" + $avatar + "', updated_at = CURRENT_TIMESTAMP WHERE id = " + $id);
    return getUserById($id);
}

// ---------- Roadmaps ----------

def listRoadmaps() {
    return $sqlite.query("SELECT id, title, slug, description, category, icon, color, difficulty, featured, topic_count, created_at, updated_at FROM roadmaps ORDER BY featured DESC, title ASC");
}

def getRoadmapById($id) {
    $rows = $sqlite.query("SELECT * FROM roadmaps WHERE id = '" + $id + "'");
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def getRoadmapBySlug($slug) {
    $rows = $sqlite.query("SELECT * FROM roadmaps WHERE slug = '" + $slug + "'");
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def insertRoadmap($r) {
    $featured = "0";
    if ($r["featured"] == true) { $featured = "1"; }
    $sqlite.exec("INSERT OR IGNORE INTO roadmaps (id, title, slug, description, category, icon, color, difficulty, featured, topic_count) VALUES ('"
        + $r["id"] + "', '" + $r["title"] + "', '" + $r["slug"] + "', '"
        + $r["description"] + "', '" + $r["category"] + "', '"
        + $r["icon"] + "', '" + $r["color"] + "', '" + $r["difficulty"]
        + "', " + $featured + ", " + $r["topicCount"] + ")");
}

def countRoadmaps() {
    $rows = $sqlite.query("SELECT COUNT(*) AS n FROM roadmaps");
    if ($rows.length == 0) { return 0; }
    return $rows[0]["n"];
}

// ---------- Topics & Items ----------

def listTopics($roadmapId) {
    return $sqlite.query("SELECT id, roadmap_id, title, slug, ordinal FROM topics WHERE roadmap_id = '" + $roadmapId + "' ORDER BY ordinal ASC");
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
        $sqlite.exec("INSERT INTO progress (user_id, item_id, status) VALUES (" + $userId + ", " + $itemId + ", '" + $status + "')");
    } else {
        $sqlite.exec("UPDATE progress SET status = '" + $status + "', updated_at = CURRENT_TIMESTAMP WHERE id = " + $existing["id"]);
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
    $sqlite.exec("INSERT INTO notes (user_id, item_id, title, body) VALUES (" + $userId + ", " + $itemClause + ", '" + $title + "', '" + $body + "')");
    $rows = $sqlite.query("SELECT * FROM notes WHERE user_id = " + $userId + " ORDER BY id DESC LIMIT 1");
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def updateNote($userId, $noteId, $title, $body) {
    $sqlite.exec("UPDATE notes SET title = '" + $title + "', body = '" + $body + "', updated_at = CURRENT_TIMESTAMP WHERE id = " + $noteId + " AND user_id = " + $userId);
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
    $sqlite.exec("INSERT INTO chat_sessions (user_id, title) VALUES (" + $userId + ", '" + $title + "')");
    $rows = $sqlite.query("SELECT * FROM chat_sessions WHERE user_id = " + $userId + " ORDER BY id DESC LIMIT 1");
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

def listChatMessages($sessionId) {
    return $sqlite.query("SELECT id, session_id, role, body, created_at FROM chat_messages WHERE session_id = " + $sessionId + " ORDER BY id ASC");
}

def createChatMessage($sessionId, $role, $body) {
    $sqlite.exec("INSERT INTO chat_messages (session_id, role, body) VALUES (" + $sessionId + ", '" + $role + "', '" + $body + "')");
    $rows = $sqlite.query("SELECT * FROM chat_messages WHERE session_id = " + $sessionId + " ORDER BY id DESC LIMIT 1");
    if ($rows.length == 0) { return null; }
    return $rows[0];
}

print("[db] module loaded — initDb + helpers for users, roadmaps, topics, items, progress, notes, chat");
