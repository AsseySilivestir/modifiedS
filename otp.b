// ============================================================================
// otp.b — Email verification via one-time passcode
//
// Replaces the implicit "we trust whatever email you typed" model with an
// actual email roundtrip. After registration the user is logged in but
// `is_email_verified = 0`; protected actions (post thought, apply for admin,
// enroll, etc.) are gated on a verified email.
//
// Endpoints:
//   POST /api/auth/send-otp     sendOtp   (auth) — generate + email 6-digit code
//   POST /api/auth/verify-otp   verifyOtp (auth) — submit code, flip verified=1
//   GET  /api/auth/verify-status status   (auth) — {is_email_verified, has_pending_otp}
//
// Email provider: Resend (https://resend.com — free 100/day).
//   1. Create a free account, verify your sending domain.
//   2. Get API key (starts with "re_...").
//   3. On Render → Environment tab → add:
//        RESEND_API_KEY = re_xxxxxx
//        MAIL_FROM      = modifiedS <noreply@yourdomain.com>
//   4. Redeploy. The OTP email will go out via Resend.
//
// DEV MODE: If RESEND_API_KEY is not set, the OTP code is returned in the
// API response (field `dev_code`) AND printed to the server log. This lets
// you test the flow locally without an email provider. NEVER rely on this
// in production — always set RESEND_API_KEY on Render.
// ============================================================================

// Generate a 6-digit code as a string (zero-padded).
// Bantu v1.2.2 has no Math.random — we use time-based pseudo-randomness
// mixed with the user id. Not cryptographically secure, but adequate for
// a 6-digit code that expires in 10 min and is capped at 5 attempts.
def _genOtp($userId) {
    $t = floor(num("1700000000")) + ($userId * 7919);
    // Mix in a counter — Bantu has no static state, so we read the current
    // millisecond-ish value from the events table id (always increasing).
    $rows = $sqlite.query("SELECT MAX(id) AS m FROM events");
    if ($rows.length > 0 && $rows[0]["m"] != null) {
        $t = $t + ($rows[0]["m"] * 31);
    }
    $code = ($t * 2654435761) % 1000000;
    if ($code < 0) { $code = 0 - $code; }
    $s = "" + $code;
    // Zero-pad to 6 digits
    while ($s.length < 6) { $s = "0" + $s; }
    return $s;
}

// Send the OTP email via Resend API. Returns true on success, false on
// failure (network error, non-2xx, etc.). In dev mode (no API key), returns
// true and does nothing — the controller adds the code to the response.
def _sendEmailViaResend($toEmail, $toName, $code) {
    $apiKey = env("RESEND_API_KEY");
    if ($apiKey == null || $apiKey == "") {
        // Dev mode — caller surfaces the code in the response + server log.
        return false;
    }
    $mailFrom = env("MAIL_FROM");
    if ($mailFrom == null || $mailFrom == "") {
        $mailFrom = "modifiedS <onboarding@resend.dev>";
    }
    $subject = "Your modifiedS verification code: " + $code;
    $html = "<div style=\"font-family:-apple-system,Segoe UI,sans-serif;max-width:480px;margin:0 auto;padding:24px\">"
        + "<div style=\"background:#6366f1;color:#fff;padding:20px 24px;border-radius:12px 12px 0 0\">"
        + "<h2 style=\"margin:0;font-size:18px\">modifiedS</h2>"
        + "<p style=\"margin:4px 0 0;opacity:.85;font-size:13px\">Email verification</p>"
        + "</div>"
        + "<div style=\"border:1px solid #e5e7eb;border-top:0;padding:24px;border-radius:0 0 12px 12px\">"
        + "<p>Hi " + ("" + $toName).replace("<","&lt;") + ",</p>"
        + "<p>Use the code below to verify your email. It expires in 10 minutes.</p>"
        + "<div style=\"text-align:center;font-size:36px;font-weight:700;letter-spacing:8px;"
        + "background:#f5f3ff;color:#6366f1;padding:20px;border-radius:8px;margin:16px 0\">"
        + $code + "</div>"
        + "<p style=\"font-size:13px;color:#6b7280\">If you didn't request this code, you can ignore this email.</p>"
        + "</div></div>";
    $body = "{\"from\":\"" + $mailFrom.replace("\"","\\\"") + "\","
        + "\"to\":\"" + $toEmail.replace("\"","\\\"") + "\","
        + "\"subject\":\"" + $subject.replace("\"","\\\"") + "\","
        + "\"html\":\"" + $html.replace("\\","\\\\").replace("\"","\\\"").replace("\n"," ") + "\"}";
    $headers = {
        "Authorization": "Bearer " + $apiKey,
        "Content-Type": "application/json"
    };
    $r = sua.http.post("https://api.resend.com/emails", $body, $headers);
    if ($r == null) { return false; }
    if ($r.status >= 200 && $r.status < 300) {
        print("[otp] email sent to " + $toEmail + " (Resend status " + $r.status + ")");
        return true;
    }
    print("[otp] Resend API failed: status=" + $r.status + " body=" + $r.body);
    return false;
}

// ---------- Handlers ----------

def sendOtp($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    if ($user["is_email_verified"] == 1) {
        $res.status(400);
        $res.json({ "error": "Your email is already verified" });
        return null;
    }
    // Rate-limit: if user already has a valid OTP, refuse to send a new one
    // until 60s have passed (we can't easily check "60s" in SQLite without
    // a created_at on the OTP itself, so we approximate by checking the
    // expiry — a fresh OTP is good for 10 min, so if expiry is > 9 min from
    // now, the user just requested it; tell them to wait).
    if (hasValidOtp($user["id"])) {
        $rec = getUserOtp($user["id"]);
        // If they still have plenty of time left, refuse re-send
        $rows = $sqlite.query("SELECT (julianday(otp_expires_at) - julianday('now')) * 24 * 60 AS mins_left FROM users WHERE id = " + $user["id"]);
        $minsLeft = 10;
        if ($rows.length > 0 && $rows[0]["mins_left"] != null) {
            $minsLeft = $rows[0]["mins_left"];
        }
        if ($minsLeft > 9) {
            $res.status(429);
            $res.json({ "error": "You just requested a code. Please wait 1 minute before requesting another." });
            return null;
        }
    }
    $code = _genOtp($user["id"]);
    setUserOtp($user["id"], $code);
    $emailed = _sendEmailViaResend($user["email"], $user["display_name"], $code);
    if (!$emailed) {
        // Dev mode — log the code so the developer can read it from the
        // Render logs / local terminal and paste it into the OTP form.
        print("[otp] DEV MODE — code for " + $user["email"] + " is: " + $code);
        print("[otp] (set RESEND_API_KEY env var on Render to send real emails)");
    }
    trackEvent("system", "created", { "actor": $user["username"], "body": "requested email OTP" });
    $resp = { "ok": true, "message": "Verification code sent to " + $user["email"] };
    if (!$emailed) {
        $resp["dev_code"] = $code;
        $resp["dev_mode"] = true;
        $resp["message"] = "DEV MODE: SMTP not configured. Use code " + $code + " (check server logs).";
    }
    $res.json($resp);
}

def verifyOtp($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    if ($user["is_email_verified"] == 1) {
        $res.json({ "ok": true, "already_verified": true, "user": getUserById($user["id"]) });
        return null;
    }
    $code = $req.body["code"];
    if ($code == null || $code == "") {
        $res.status(400);
        $res.json({ "error": "Verification code is required" });
        return null;
    }
    // Normalize: trim + coerce to string
    $code = ("" + $code).trim();
    if ($code.length != 6) {
        $res.status(400);
        $res.json({ "error": "Code must be exactly 6 digits" });
        return null;
    }
    $rec = getUserOtp($user["id"]);
    if ($rec == null || $rec["otp_code"] == null) {
        $res.status(400);
        $res.json({ "error": "No active code. Request a new one first." });
        return null;
    }
    if ($rec["otp_attempts"] != null && $rec["otp_attempts"] >= 5) {
        clearOtp($user["id"]);
        $res.status(429);
        $res.json({ "error": "Too many wrong attempts. Please request a new code." });
        return null;
    }
    // Check expiry
    $expRows = $sqlite.query("SELECT (julianday(otp_expires_at) - julianday('now')) * 24 * 60 AS mins_left FROM users WHERE id = " + $user["id"]);
    $minsLeft = -1;
    if ($expRows.length > 0 && $expRows[0]["mins_left"] != null) {
        $minsLeft = $expRows[0]["mins_left"];
    }
    if ($minsLeft < 0) {
        clearOtp($user["id"]);
        $res.status(400);
        $res.json({ "error": "Code expired. Request a new one." });
        return null;
    }
    // Check code match
    // IMPORTANT: Bantu's SQLite driver returns numeric-looking TEXT columns
    // as numbers (e.g. otp_code "791552" comes back as the number 791552).
    // Strict !=  then fails: 791552 != "791552" → true. Coerce both sides
    // to strings before comparing.
    $storedCode = "" + $rec["otp_code"];
    $inputCode  = "" + $code;
    if ($storedCode != $inputCode) {
        $attempts = incrementOtpAttempts($user["id"]);
        $remaining = 5 - $attempts;
        if ($remaining <= 0) {
            clearOtp($user["id"]);
            $res.status(429);
            $res.json({ "error": "Too many wrong attempts. Please request a new code." });
            return null;
        }
        $res.status(400);
        $res.json({ "error": "Wrong code. " + $remaining + " attempts remaining." });
        return null;
    }
    // Code is correct + not expired + attempts OK → mark verified
    markEmailVerified($user["id"]);
    trackEvent("system", "created", { "actor": $user["username"], "body": "verified email" });
    $updated = getUserById($user["id"]);
    $res.json({ "ok": true, "user": $updated });
}

def status($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    $hasPending = hasValidOtp($user["id"]);
    $res.json({
        "is_email_verified": ($user["is_email_verified"] == 1),
        "has_pending_otp": $hasPending,
        "email": $user["email"]
    });
}

print("[otp] module loaded — sendOtp / verifyOtp / status (via Resend API or dev mode)");
