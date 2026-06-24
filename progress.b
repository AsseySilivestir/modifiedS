// ============================================================================
// progress.b — User progress controllers for modifiedS
//
// Replaces the Next.js route handlers:
//   /app/api/progress/route.ts            (GET    /api/progress)
//   /app/api/progress/[itemId]/route.ts   (POST   /api/progress/:itemId, PUT, DELETE)
//
// All endpoints require authentication.
//
// Exposes:
//   list($req, $res)              GET    /api/progress
//   set($req, $res)               POST   /api/progress/:itemId    {status:"done"|"pending"}
//   remove($req, $res)            DELETE /api/progress/:itemId
// ============================================================================

def listAll($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    $res.json({ "progress": listProgress($user["id"]) });
}

def setOne($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    $itemId = $req.params["itemId"];
    $status = $req.body["status"];
    if ($status == null || $status == "") { $status = "done"; }
    $p = upsertProgress($user["id"], $itemId, $status);
    $res.json({ "progress": $p });
}

def removeOne($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    $itemId = $req.params["itemId"];
    $sqlite.exec("DELETE FROM progress WHERE user_id = " + $user["id"] + " AND item_id = " + $itemId);
    $res.json({ "ok": true });
}

print("[progress] module loaded — list / set / remove");
