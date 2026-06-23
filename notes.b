// ============================================================================
// notes.b — User notes controllers for modifiedS
//
// Replaces the Next.js route handlers:
//   /app/api/notes/route.ts         (GET, POST)
//   /app/api/notes/[id]/route.ts    (GET, PUT, DELETE)
//
// All endpoints require authentication.
//
// Exposes:
//   list($req, $res)    GET    /api/notes
//   create($req, $res)  POST   /api/notes    {title, body, itemId?}
//   show($req, $res)    GET    /api/notes/:id
//   update($req, $res)  PUT    /api/notes/:id {title, body}
//   remove($req, $res)  DELETE /api/notes/:id
// ============================================================================

def listAll($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    $res.json({ "notes": listNotes($user["id"]) });
}

def createOne($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    $title = $req.body["title"];
    $body  = $req.body["body"];
    $itemId = $req.body["itemId"];
    if ($title == null) { $title = "Untitled"; }
    if ($body == null || $body == "") {
        $res.status(400);
        $res.json({ "error": "body is required" });
        return null;
    }
    $note = createNote($user["id"], $title, $body, $itemId);
    $res.status(201);
    $res.json({ "note": $note });
}

def showOne($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    $note = getNote($user["id"], $req.params["id"]);
    if ($note == null) {
        $res.status(404);
        $res.json({ "error": "Note not found" });
        return null;
    }
    $res.json({ "note": $note });
}

def updateOne($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    $title = $req.body["title"];
    $body  = $req.body["body"];
    $note = updateNote($user["id"], $req.params["id"], $title, $body);
    $res.json({ "note": $note });
}

def removeOne($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    deleteNote($user["id"], $req.params["id"]);
    $res.json({ "ok": true });
}

print("[notes] module loaded — list / create / show / update / remove");
