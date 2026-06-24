// ============================================================================
// roadmaps.b — Roadmap controllers for modifiedS
//
// Replaces the Next.js route handlers:
//   /app/api/roadmaps/route.ts          (GET /api/roadmaps)
//   /app/api/roadmaps/[slug]/route.ts   (GET /api/roadmaps/:slug)
//   /app/api/roadmaps/[slug]/topics/route.ts
//   /app/api/roadmaps/[slug]/topics/[id]/items/route.ts
//
// Exposes:
//   list($req, $res)                       GET  /api/roadmaps
//   show($req, $res)                       GET  /api/roadmaps/:slug
//   listTopics($req, $res)                 GET  /api/roadmaps/:slug/topics
//   listItems($req, $res)                  GET  /api/roadmaps/:slug/topics/:id/items
// ============================================================================

def listAll($req, $res) {
    $rows = listRoadmaps();
    $res.json({ "roadmaps": $rows });
}

def showOne($req, $res) {
    $slug = $req.params["slug"];
    $rm = getRoadmapBySlug($slug);
    if ($rm == null) {
        // Fall back to id lookup
        $rm = getRoadmapById($slug);
    }
    if ($rm == null) {
        $res.status(404);
        $res.json({ "error": "Roadmap not found" });
        return null;
    }
    $topics = listTopics($rm["id"]);
    $totalItems = 0;
    each ($t in $topics) {
        $totalItems = $totalItems + $t["items_count"];
    }
    $rm["totalItems"] = $totalItems;
    $rm["completedItems"] = 0;
    $rm["progressPercentage"] = 0;
    $res.json({ "roadmap": $rm, "topics": $topics });
}

def topicsOf($req, $res) {
    $slug = $req.params["slug"];
    $rm = getRoadmapBySlug($slug);
    if ($rm == null) { $rm = getRoadmapById($slug); }
    if ($rm == null) {
        $res.status(404);
        $res.json({ "error": "Roadmap not found" });
        return null;
    }
    $res.json({ "topics": listTopics($rm["id"]) });
}

def itemsOf($req, $res) {
    $topicId = $req.params["id"];
    $res.json({ "items": listItems($topicId) });
}

print("[roadmaps] module loaded — list / show / topics / items");
