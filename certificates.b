// ============================================================================
// certificates.b — Certificate listing (JSON only)
//
// Endpoints:
//   GET  /api/certificates                  listMine     (auth) — list my certs
//
// The printable certificate HTML is generated client-side (frontend) using
// the JSON data returned by listMine. The frontend opens a new window and
// writes the HTML, avoiding any non-JSON $res methods.
// ============================================================================

def listMine($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    $res.json({ "certificates": listCertificates($user["id"]) });
}

print("[certificates] module loaded — listMine (JSON)");
