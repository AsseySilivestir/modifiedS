// ============================================================================
// community.b — Thoughts + Announcements controllers
//
// Public endpoints:
//   GET    /api/thoughts                 listThoughts   (public)
//   POST   /api/thoughts                 createThought  (auth)
//   DELETE /api/thoughts/:id             removeThought  (auth, owner only)
//   POST   /api/thoughts/:id/like        likeThought    (auth, toggle)
//
//   GET    /api/announcements            listAnnouncements (public)
//   POST   /api/announcements            createAnnouncement (admin only)
//   DELETE /api/announcements/:id        removeAnnouncement (admin only)
// ============================================================================

// ---------- Thoughts ----------

def listAll($req, $res) {
    $res.json({ "thoughts": listThoughts() });
    return null;
}

def createOne($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    $body = $req.body["body"];
    $tags = $req.body["tags"];
    if ($body == null || $body == "") {
        $res.status(400);
        $res.json({ "error": "Thought body cannot be empty" });
        return null;
    }
    if ($tags == null) { $tags = ""; }
    if ($body.length > 1000) {
        $res.status(400);
        $res.json({ "error": "Thought must be 1000 characters or fewer" });
        return null;
    }
    $t = createThought($user["id"], $body, $tags);
    $res.status(201);
    $res.json({ "thought": $t, "author": { "username": $user["username"], "display_name": $user["display_name"], "avatar_url": $user["avatar_url"] } });
}

def removeOne($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    $id = $req.params["id"];
    // Admins can delete anyone's thought; users can only delete their own
    if ($user["role"] == "admin") {
        $sqlite.exec("DELETE FROM thought_likes WHERE thought_id = " + $id);
        $sqlite.exec("DELETE FROM thoughts WHERE id = " + $id);
    } else {
        $sqlite.exec("DELETE FROM thought_likes WHERE thought_id = " + $id + " AND user_id = " + $user["id"]);
        deleteThought($user["id"], $id);
    }
    $res.json({ "ok": true });
}

def likeOne($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    $id = $req.params["id"];
    $liked = likeThought($user["id"], $id);
    $res.json({ "ok": true, "liked": $liked });
}

// ---------- Announcements ----------

def listAnn($req, $res) {
    $res.json({ "announcements": listAnnouncements() });
    return null;
}

def createAnn($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    if ($user["role"] != "admin") {
        $res.status(403);
        $res.json({ "error": "Admin access required" });
        return null;
    }
    $title    = $req.body["title"];
    $body     = $req.body["body"];
    $category = $req.body["category"];
    $pinned   = $req.body["pinned"];
    if ($title == null || $title == "" || $body == null || $body == "") {
        $res.status(400);
        $res.json({ "error": "Title and body are required" });
        return null;
    }
    $a = createAnnouncement($user["id"], $title, $body, $category, $pinned);
    $res.status(201);
    $res.json({ "announcement": $a });
}

def removeAnn($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    if ($user["role"] != "admin") {
        $res.status(403);
        $res.json({ "error": "Admin access required" });
        return null;
    }
    deleteAnnouncement($req.params["id"]);
    $res.json({ "ok": true });
}

print("[community] module loaded — thoughts (list/create/remove/like) + announcements (list/create/remove)");
