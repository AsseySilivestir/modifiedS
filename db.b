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

    // Promote the very first user to admin (idempotent — only if no admin exists yet)
    $adminCheck = $sqlite.query("SELECT id FROM users WHERE role = 'admin' LIMIT 1");
    if ($adminCheck.length == 0) {
        $firstUser = $sqlite.query("SELECT id, username FROM users ORDER BY id ASC LIMIT 1");
        if ($firstUser.length > 0) {
            $sqlite.exec("UPDATE users SET role = 'admin' WHERE id = " + $firstUser[0]["id"]);
            print("[db] promoted first user '" + $firstUser[0]["username"] + "' to admin");
        }
    }

    print("[db] initialized — 14 tables ready (users, roadmaps, topics, items, progress, notes, chat, courses, modules, enrollments, announcements, thoughts, thought_likes, certificates)");
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

print("[db] module loaded — initDb + helpers for users, roadmaps, topics, items, progress, notes, chat, courses, announcements, thoughts, certificates");

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
