// ============================================================================
// courses.b — Course catalog + enrollments + modules controllers
//
// Endpoints:
//   GET    /api/courses                       listAll          (public)
//   GET    /api/courses/:id                   showOne          (public)
//   POST   /api/courses                       createOne        (admin)
//   PUT    /api/courses/:id                   updateOne        (admin)
//   DELETE /api/courses/:id                   removeOne        (admin)
//   GET    /api/courses/:id/modules           listModules      (public)
//   POST   /api/courses/:id/modules           addModule        (admin)
//   DELETE /api/courses/:id/modules/:mid      removeModule     (admin)
//
//   GET    /api/enrollments                   listEnrollments  (auth)
//   POST   /api/enrollments/:courseId         enroll           (auth)
//   DELETE /api/enrollments/:courseId         unenroll         (auth)
//   POST   /api/enrollments/:courseId/progress setProgress    (auth)
// ============================================================================

def listAll($req, $res) {
    $res.json({ "courses": listCourses() });
    return null;
}

def showOne($req, $res) {
    $id = $req.params["id"];
    $course = getCourseById($id);
    if ($course == null) {
        $res.status(404);
        $res.json({ "error": "Course not found" });
        return null;
    }
    $modules = listCourseModules($id);
    $res.json({ "course": $course, "modules": $modules });
    return null;
}

def createOne($req, $res) {
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
    if ($req.body["title"] == null || $req.body["title"] == "") {
        $res.status(400);
        $res.json({ "error": "Title is required" });
        return null;
    }
    if ($req.body["description"] == null || $req.body["description"] == "") {
        $res.status(400);
        $res.json({ "error": "Description is required" });
        return null;
    }
    $c = createCourse($user["id"], $req.body);
    if ($c == null) {
        $res.status(500);
        $res.json({ "error": "Failed to create course — check server logs (often caused by special characters in title/description)" });
        return null;
    }
    $res.status(201);
    $res.json({ "course": $c });
}

def updateOne($req, $res) {
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
    $id = $req.params["id"];
    $c = updateCourse($id, $req.body);
    $res.json({ "course": $c });
}

def removeOne($req, $res) {
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
    deleteCourse($req.params["id"]);
    $res.json({ "ok": true });
}

def listModules($req, $res) {
    $id = $req.params["id"];
    $res.json({ "modules": listCourseModules($id) });
}

def addModule($req, $res) {
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
    $courseId = $req.params["id"];
    $title   = $req.body["title"];
    $content = $req.body["content"];
    $ordinal = $req.body["ordinal"];
    if ($title == null || $title == "") {
        $res.status(400);
        $res.json({ "error": "Module title is required" });
        return null;
    }
    if ($content == null) { $content = ""; }
    $m = addCourseModule($courseId, $title, $content, $ordinal);
    $res.status(201);
    $res.json({ "module": $m });
}

def removeModule($req, $res) {
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
    deleteCourseModule($req.params["mid"]);
    $res.json({ "ok": true });
}

// ---------- Enrollments ----------

def listEnroll($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    $res.json({ "enrollments": listEnrollments($user["id"]) });
}

def enroll($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    $courseId = $req.params["courseId"];
    $course = getCourseById($courseId);
    if ($course == null) {
        $res.status(404);
        $res.json({ "error": "Course not found" });
        return null;
    }
    $e = enrollUser($user["id"], $courseId);
    $res.json({ "enrollment": $e });
}

def unenroll($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    unenrollUser($user["id"], $req.params["courseId"]);
    $res.json({ "ok": true });
}

def setProgress($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    $courseId = $req.params["courseId"];
    $percent  = $req.body["percent"];
    if ($percent == null || $percent == "") { $percent = "0"; }
    $enrollment = getEnrollment($user["id"], $courseId);
    if ($enrollment == null) {
        $res.status(404);
        $res.json({ "error": "Not enrolled in this course" });
        return null;
    }
    $updated = updateEnrollmentProgress($user["id"], $courseId, $percent);
    // Auto-issue certificate when course is completed
    $cert = null;
    if (floor(num($percent)) >= 100) {
        $cert = issueCertificate($user["id"], $courseId);
    }
    $res.json({ "enrollment": $updated, "certificate": $cert });
}

print("[courses] module loaded — list/show/create/update/delete + modules + enroll/progress");
