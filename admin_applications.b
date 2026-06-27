// ============================================================================
// admin_applications.b — Admin application vetting flow
//
// Regular users (role='student') apply to become admins. Existing admins
// (role='admin') review and approve/reject applications. On approval, the
// applicant's role is flipped to 'admin' and they immediately gain access
// to the admin panel.
//
// Endpoints:
//   GET    /api/admin-applications/me          getMyApplication   (auth)
//   POST   /api/admin-applications             submitApplication  (auth, non-admin)
//   DELETE /api/admin-applications/me          withdrawMine       (auth)
//   GET    /api/admin-applications             listAll            (admin)
//   POST   /api/admin-applications/:id/approve approve            (admin)
//   POST   /api/admin-applications/:id/reject  reject             (admin)
//
// Notes:
//   - The first registered user is auto-admin (see db.b initDb).
//   - A user may have only ONE pending application at a time.
//   - Admins cannot apply (they already are admins).
//   - Approving a pending app atomically promotes the user.
// ============================================================================

// ---------- My application (auth) ----------

def getMyApplication($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    $app = getMyLatestAdminApplication($user["id"]);
    $res.json({ "application": $app, "role": $user["role"] });
    return null;
}

def submitApplication($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    // Admins cannot apply (they already are admins)
    if ($user["role"] == "admin") {
        $res.status(400);
        $res.json({ "error": "You are already an admin" });
        return null;
    }
    // One pending application at a time
    if (hasPendingAdminApplication($user["id"])) {
        $res.status(409);
        $res.json({ "error": "You already have a pending application. Wait for an admin to review it, or withdraw it first." });
        return null;
    }
    $reason     = $req.body["reason"];
    $experience = $req.body["experience"];
    if ($reason == null || $reason == "" || ("" + $reason).trim() == "") {
        $res.status(400);
        $res.json({ "error": "Please tell us why you want to be an admin (reason is required)" });
        return null;
    }
    if ($experience == null) { $experience = ""; }
    // Reason field length guard — Bantu v1.2.2 has no .length on numbers,
    // so coerce to string first.
    if (("" + $reason).length > 2000) {
        $res.status(400);
        $res.json({ "error": "Reason is too long (max 2000 characters)" });
        return null;
    }
    if (("" + $experience).length > 2000) {
        $res.status(400);
        $res.json({ "error": "Experience is too long (max 2000 characters)" });
        return null;
    }
    $app = submitAdminApplication($user["id"], $reason, $experience);
    $res.status(201);
    $res.json({ "application": $app });
}

def withdrawMine($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    $app = withdrawMyAdminApplication($user["id"]);
    $res.json({ "application": $app });
}

// ---------- Admin review (admin) ----------

def listAll($req, $res) {
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
    // Optional status filter via ?status=pending
    $status = "all";
    if ($req.query != null) {
        $status = $req.query["status"];
    }
    $apps = listAdminApplications($status);
    $res.json({ "applications": $apps });
}

def approve($req, $res) {
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
    $appId = $req.params["id"];
    $note  = $req.body["note"];
    $app = approveAdminApplication($appId, $user["id"], $note);
    if ($app == null) {
        $res.status(404);
        $res.json({ "error": "Application not found or already reviewed" });
        return null;
    }
    $res.json({ "application": $app });
}

def reject($req, $res) {
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
    $appId = $req.params["id"];
    $note  = $req.body["note"];
    $app = rejectAdminApplication($appId, $user["id"], $note);
    if ($app == null) {
        $res.status(404);
        $res.json({ "error": "Application not found or already reviewed" });
        return null;
    }
    $res.json({ "application": $app });
}

print("[admin_applications] module loaded — submit/withdraw (auth) + list/approve/reject (admin)");
