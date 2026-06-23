// ============================================================================
// auth.b — Authentication module for modifiedS
//
// Replaces the Next.js auth route handlers:
//   /app/api/auth/login/route.ts
//   /app/api/auth/register/route.ts
//   /app/api/auth/me/route.ts
//   /app/api/auth/[...nextauth]/route.ts  (token verification middleware)
//
// Stateless token model:  bnt.<userId>.<email>.<seed>
// (Swap for HMAC-signed JWT in production — Bantu v1.3 will ship sua.crypto.)
//
// Exposes:
//   issueToken($user)     — build a token string
//   parseToken($token)    — decode token back to user row, or null
//   extractToken($req)    — pull token from Authorization header / x-auth-token
//   requireUser($req)     — return user row or null
//   register($req, $res)  — POST /api/auth/register
//   login($req, $res)     — POST /api/auth/login
//   me($req, $res)        — GET  /api/auth/me
// ============================================================================

def issueToken($user) {
    $seed = "1700000000";
    return "bnt." + $user["id"] + "." + $user["email"] + "." + $seed;
}

def parseToken($token) {
    if ($token == null || $token == "") { return null; }
    $parts = $token.split(".");
    if ($parts.length < 4) { return null; }
    if ($parts[0] != "bnt") { return null; }
    $id = $parts[1];
    return getUserById($id);
}

def extractToken($req) {
    $hdr = $req.headers["authorization"];
    if ($hdr != null && $hdr != "") {
        if ($hdr.indexOf("Bearer ") == 0) {
            return $hdr.substr(7);
        }
        return $hdr;
    }
    return $req.headers["x-auth-token"];
}

def requireUser($req) {
    $tok = extractToken($req);
    return parseToken($tok);
}

// ---------- Handlers ----------

def register($req, $res) {
    $username = $req.body["username"];
    $email    = $req.body["email"];
    $password = $req.body["password"];

    if ($username == null || $username == "" || $email == null || $email == "" || $password == null || $password == "") {
        $res.status(400);
        $res.json({ "error": "Username, email, and password are required" });
        return null;
    }
    if ($username.length < 3) {
        $res.status(400);
        $res.json({ "error": "Username must be at least 3 characters" });
        return null;
    }
    if ($password.length < 6) {
        $res.status(400);
        $res.json({ "error": "Password must be at least 6 characters" });
        return null;
    }
    if ($email.indexOf("@") == -1) {
        $res.status(400);
        $res.json({ "error": "Email is invalid" });
        return null;
    }

    if (getUserByName($username) != null) {
        $res.status(409);
        $res.json({ "error": "Username already taken" });
        return null;
    }
    if (getUserByEmail($email) != null) {
        $res.status(409);
        $res.json({ "error": "Email already registered" });
        return null;
    }

    $user = createUser($username, $email, $password);
    $token = issueToken($user);
    $res.status(201);
    $res.json({
        "user": $user,
        "token": $token
    });
}

def login($req, $res) {
    $email    = $req.body["email"];
    $password = $req.body["password"];

    if ($email == null || $email == "" || $password == null || $password == "") {
        $res.status(400);
        $res.json({ "error": "Email and password are required" });
        return null;
    }

    $user = getUserByEmail($email);
    if ($user == null || $user["password"] != $password) {
        $res.status(401);
        $res.json({ "error": "Invalid email or password" });
        return null;
    }

    $token = issueToken($user);
    $res.json({
        "user": $user,
        "token": $token
    });
}

def me($req, $res) {
    $user = requireUser($req);
    if ($user == null) {
        $res.status(401);
        $res.json({ "error": "Unauthorized" });
        return null;
    }
    $res.json({ "user": $user });
}

print("[auth] module loaded — register / login / me / requireUser");
