// ============================================================================
// routes.b — Route registration for modifiedS
//
// Mirrors the original Next.js /app/api/** directory layout as flat Sua
// routes. Each Next.js route handler file becomes one $sua.server.<verb>(...)
// registration that delegates to the matching controller module.
//
// NOTE: Bantu v1.2.2 does not accept anonymous `def($req,$res){...}` as an
// argument expression — handlers must be named functions defined at module
// scope, then passed by name to sua.server.<verb>(path, handler).
//
//   Next.js route                                →  Bantu handler
//   -----------------------------------------------------------------------
//   /app/api/health/route.ts                     →  healthHandler
//   /app/api/auth/register/route.ts              →  auth.register
//   /app/api/auth/login/route.ts                 →  auth.login
//   /app/api/auth/me/route.ts                    →  auth.me
//   /app/api/roadmaps/route.ts                   →  roadmaps.listAll
//   /app/api/roadmaps/[slug]/route.ts            →  roadmaps.showOne
//   /app/api/roadmaps/[slug]/topics/route.ts     →  roadmaps.topicsOf
//   /app/api/roadmaps/[slug]/topics/[id]/items   →  roadmaps.itemsOf
//   /app/api/progress/route.ts                   →  progress.listAll
//   /app/api/progress/[itemId]/route.ts          →  progress.setOne / removeOne
//   /app/api/notes/route.ts                      →  notes.listAll / createOne
//   /app/api/notes/[id]/route.ts                 →  notes.showOne / updateOne / removeOne
//   /app/api/users/route.ts                      →  usersList (auth)
//   /app/api/users/[id]/route.ts                 →  usersUpdate (auth)
//   /app/api/ai/tutor/route.ts                   →  ai.tutor
//   /app/api/ai/quiz/route.ts                    →  ai.quiz
// ============================================================================

// ---- Health ----
def healthHandler($req, $res) {
    $hasResend = "no";
    $rk = env("RESEND_API_KEY");
    if ($rk != null && $rk != "") { $hasResend = "yes"; }
    $res.json({
        "ok": true,
        "service": "modifiedS",
        "version": "1.0.0",
        "backend": "bantu-v1.2.2",
        "runtime": "sua-http",
        "resend_key_set": $hasResend
    });
    return null;
}

// ---- Users (auth) ----
def usersList($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    $res.json({ "users": listUsers() });
    return null;
}

def usersUpdate($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    $updated = updateUser($req.params["id"], $req.body);
    $res.json({ "user": $updated });
    return null;
}

// Thin wrappers around controller modules — needed because Bantu v1.2.2
// requires named functions as route handlers.
def authRegister($req, $res) { register($req, $res); return null; }
def authLogin($req, $res)    { login($req, $res);    return null; }
def authMe($req, $res)       { me($req, $res);       return null; }

def rmListAll($req, $res)  { roadmaps.listAll($req, $res);  return null; }
def rmShowOne($req, $res)  { roadmaps.showOne($req, $res);  return null; }
def rmTopicsOf($req, $res) { roadmaps.topicsOf($req, $res); return null; }
def rmItemsOf($req, $res)  { roadmaps.itemsOf($req, $res);  return null; }

def pgListAll($req, $res)   { progress.listAll($req, $res);   return null; }
def pgSetOne($req, $res)    { progress.setOne($req, $res);    return null; }
def pgRemoveOne($req, $res) { progress.removeOne($req, $res); return null; }

def ntListAll($req, $res)   { notes.listAll($req, $res);     return null; }
def ntCreateOne($req, $res) { notes.createOne($req, $res);   return null; }
def ntShowOne($req, $res)   { notes.showOne($req, $res);     return null; }
def ntUpdateOne($req, $res) { notes.updateOne($req, $res);   return null; }
def ntRemoveOne($req, $res) { notes.removeOne($req, $res);   return null; }

def aiTutor($req, $res) { ai.tutor($req, $res); return null; }
def aiQuiz($req, $res)  { ai.quiz($req, $res);  return null; }

// ---- Community ----
def thListAll($req, $res)   { community.listAll($req, $res);    return null; }
def thCreateOne($req, $res) { community.createOne($req, $res);  return null; }
def thRemoveOne($req, $res) { community.removeOne($req, $res);  return null; }
def thLikeOne($req, $res)   { community.likeOne($req, $res);    return null; }

def anList($req, $res)      { community.listAnn($req, $res);    return null; }
def anCreate($req, $res)    { community.createAnn($req, $res);  return null; }
def anRemove($req, $res)    { community.removeAnn($req, $res);  return null; }

// ---- Courses ----
def crsListAll($req, $res)   { courses.listAll($req, $res);    return null; }
def crsShowOne($req, $res)   { courses.showOne($req, $res);    return null; }
def crsCreateOne($req, $res) { courses.createOne($req, $res);  return null; }
def crsUpdateOne($req, $res) { courses.updateOne($req, $res);  return null; }
def crsRemoveOne($req, $res) { courses.removeOne($req, $res);  return null; }
def crsListModules($req, $res) { courses.listModules($req, $res); return null; }
def crsAddModule($req, $res)   { courses.addModule($req, $res);   return null; }
def crsRemoveModule($req, $res){ courses.removeModule($req, $res);return null; }

def enrList($req, $res)     { courses.listEnroll($req, $res);  return null; }
def enrEnroll($req, $res)   { courses.enroll($req, $res);      return null; }
def enrUnenroll($req, $res) { courses.unenroll($req, $res);    return null; }
def enrProgress($req, $res) { courses.setProgress($req, $res); return null; }

// ---- Certificates ----
def certListMine($req, $res) { certificates.listMine($req, $res); return null; }

// ---- Admin applications ----
def appGetMine($req, $res)     { admin_apps.getMyApplication($req, $res); return null; }
def appSubmit($req, $res)      { admin_apps.submitApplication($req, $res); return null; }
def appWithdrawMine($req, $res){ admin_apps.withdrawMine($req, $res); return null; }
def appListAll($req, $res)     { admin_apps.listAll($req, $res); return null; }
def appApprove($req, $res)     { admin_apps.approve($req, $res); return null; }
def appReject($req, $res)      { admin_apps.reject($req, $res); return null; }

// ---- Email verification (OTP) ----
def otpSend($req, $res)   { otp.sendOtp($req, $res);  return null; }
def otpVerify($req, $res) { otp.verifyOtp($req, $res); return null; }
def otpStatus($req, $res) { otp.status($req, $res);    return null; }

// ---- Real-time events (short-poll) ----
def evList($req, $res) { realtime.events($req, $res); return null; }

def registerAll($sua) {
    // ---- Health ----
    $sua.server.get("/api/health", healthHandler);

    // ---- Auth ----
    $sua.server.post("/api/auth/register", authRegister);
    $sua.server.post("/api/auth/login",    authLogin);
    $sua.server.get ("/api/auth/me",       authMe);

    // ---- Roadmaps ----
    $sua.server.get("/api/roadmaps",                        rmListAll);
    $sua.server.get("/api/roadmaps/:slug",                  rmShowOne);
    $sua.server.get("/api/roadmaps/:slug/topics",           rmTopicsOf);
    $sua.server.get("/api/roadmaps/:slug/topics/:id/items", rmItemsOf);

    // ---- Progress (auth) ----
    $sua.server.get  ("/api/progress",          pgListAll);
    $sua.server.post ("/api/progress/:itemId",  pgSetOne);
    $sua.server.delete("/api/progress/:itemId", pgRemoveOne);

    // ---- Notes (auth) ----
    $sua.server.get  ("/api/notes",       ntListAll);
    $sua.server.post ("/api/notes",       ntCreateOne);
    $sua.server.get  ("/api/notes/:id",   ntShowOne);
    $sua.server.put  ("/api/notes/:id",   ntUpdateOne);
    $sua.server.delete("/api/notes/:id",  ntRemoveOne);

    // ---- Users (auth) ----
    $sua.server.get("/api/users",     usersList);
    $sua.server.put("/api/users/:id", usersUpdate);

    // ---- AI ----
    $sua.server.post("/api/ai/tutor", aiTutor);
    $sua.server.post("/api/ai/quiz",  aiQuiz);

    // ---- Community: thoughts (public read, auth write) ----
    $sua.server.get  ("/api/thoughts",         thListAll);
    $sua.server.post ("/api/thoughts",         thCreateOne);
    $sua.server.delete("/api/thoughts/:id",    thRemoveOne);
    $sua.server.post ("/api/thoughts/:id/like", thLikeOne);

    // ---- Announcements (public read, admin write) ----
    $sua.server.get  ("/api/announcements",        anList);
    $sua.server.post ("/api/announcements",        anCreate);
    $sua.server.delete("/api/announcements/:id",   anRemove);

    // ---- Courses (public read, admin write) ----
    $sua.server.get  ("/api/courses",                       crsListAll);
    $sua.server.get  ("/api/courses/:id",                   crsShowOne);
    $sua.server.post ("/api/courses",                       crsCreateOne);
    $sua.server.put  ("/api/courses/:id",                   crsUpdateOne);
    $sua.server.delete("/api/courses/:id",                  crsRemoveOne);
    $sua.server.get  ("/api/courses/:id/modules",           crsListModules);
    $sua.server.post ("/api/courses/:id/modules",           crsAddModule);
    $sua.server.delete("/api/courses/:id/modules/:mid",     crsRemoveModule);

    // ---- Enrollments (auth) ----
    $sua.server.get  ("/api/enrollments",                  enrList);
    $sua.server.post ("/api/enrollments/:courseId",        enrEnroll);
    $sua.server.delete("/api/enrollments/:courseId",       enrUnenroll);
    $sua.server.post ("/api/enrollments/:courseId/progress", enrProgress);

    // ---- Certificates (auth list) ----
    $sua.server.get("/api/certificates",            certListMine);

    // ---- Admin applications ----
    // Regular users apply; existing admins vet.
    $sua.server.get   ("/api/admin-applications/me",            appGetMine);
    $sua.server.post  ("/api/admin-applications",               appSubmit);
    $sua.server.delete("/api/admin-applications/me",            appWithdrawMine);
    $sua.server.get   ("/api/admin-applications",               appListAll);
    $sua.server.post  ("/api/admin-applications/:id/approve",   appApprove);
    $sua.server.post  ("/api/admin-applications/:id/reject",    appReject);

    // ---- Email verification (OTP) ----
    // Auth required for all three. User registers → is_email_verified=0 →
    // sends OTP → submits code → is_email_verified=1.
    $sua.server.post("/api/auth/send-otp",      otpSend);
    $sua.server.post("/api/auth/verify-otp",    otpVerify);
    $sua.server.get ("/api/auth/verify-status", otpStatus);

    // ---- Real-time events (short-poll, 5s on frontend) ----
    $sua.server.get("/api/events", evList);

    print("[routes] registered 48 routes under /api/*");
    return null;
}

print("[routes] module loaded — registerAll(sua) wires 48 routes");
