// ============================================================================
// realtime.b — Real-time event polling endpoint
//
// Since Bantu v1.2.2's HTTP server has no WebSocket/SSE support, we use
// short polling: the frontend calls GET /api/events?since=<lastId> every
// 5 seconds and gets any events that arrived since the last poll. This is
// cheap (single SQL SELECT), works through Render's CDN, and never blocks
// the single-threaded Bantu runtime for more than a few milliseconds.
//
// Endpoint:
//   GET /api/events?since=<id>   events  (auth) — returns new events since <id>
//
// Response shape:
//   {
//     "events": [
//       { "id": 42, "type": "announcement", "verb": "created",
//         "payload": "{\"title\":\"...\",\"actor\":\"admin\"}",
//         "created_at": "2026-06-27 12:34:56" }
//     ],
//     "latest_id": 42
//   }
//
// On first load, frontend calls /api/events?since=0 (or omits ?since) and
// gets the latest 10 events, then sets its cursor to latest_id. From then
// on it polls /api/events?since=<latest_id> every 5 seconds.
// ============================================================================

def events($req, $res) {
    // Auth required — we don't leak events to anonymous visitors
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    $since = "0";
    if ($req.query != null) {
        $q = $req.query["since"];
        if ($q != null && $q != "") {
            $since = "" + $q;
        }
    }
    // If since=0 (first load), return the last 10 events so the frontend has
    // some immediate context. Otherwise return only new events since $since.
    // NOTE: Bantu v1.2.2 arrays have no .push() method (silently no-ops), so
    // we don't reverse — frontend handles newest-first ordering fine.
    $rows = null;
    if ($since == "0") {
        $rows = listRecentEvents("10");
    } else {
        $rows = listEventsSince($since);
    }
    $latest = latestEventId();
    $res.json({ "events": $rows, "latest_id": $latest });
}

print("[realtime] module loaded — events (short-poll, 5s interval on frontend)");
