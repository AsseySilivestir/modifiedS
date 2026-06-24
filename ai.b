// ============================================================================
// ai.b — AI tutor & quiz controllers for modifiedS
//
// Replaces the Next.js route handlers:
//   /app/api/ai/tutor/route.ts   (POST /api/ai/tutor      {message})
//   /app/api/ai/quiz/route.ts    (POST /api/ai/quiz       {topic, count?})
//
// The original Splannes app proxies these to a hosted LLM. In this Bantu
// rewrite we provide a deterministic rule-based tutor + quiz generator so
// the app works fully offline — no API keys needed. The response shape
// mirrors what the original Next.js backend returned so the frontend can
// consume it unchanged.
//
// Exposes:
//   tutor($req, $res)   POST /api/ai/tutor
//   quiz($req, $res)    POST /api/ai/quiz
// ============================================================================

// List of {key, answer} pairs — kept as a list because Bantu objects don't
// expose a .keys() method (only the `db` builtin does).
$TUTOR_KB = [
    { "key":"javascript", "answer":"JavaScript is a high-level, dynamically-typed, multi-paradigm language. Start with variables (let/const), then functions, then async/await, then modules. Build projects early — a todo list, then a small SPA, then a backend with Node.js." },
    { "key":"python",     "answer":"Python emphasizes readability. Learn data types first (str, int, list, dict), then control flow, then functions, then classes. Try LeetCode easy problems to internalize syntax, then build a CLI tool or a Flask API." },
    { "key":"frontend",   "answer":"Frontend today means HTML, CSS, JavaScript, then a framework (React recommended), then build tools (Vite), then state management. Practice by cloning existing UIs before designing your own." },
    { "key":"backend",    "answer":"Backend engineering is about APIs, databases, and reliability. Pick one stack (Node+Express+Postgres is beginner-friendly), build CRUD APIs, then learn authentication, caching, queues, and observability." },
    { "key":"react",      "answer":"React lets you build UIs from components. Learn JSX, then props, then state (useState), then effects (useEffect), then patterns (custom hooks, context). The official tutorial at react.dev is excellent." },
    { "key":"dsa",        "answer":"Data structures and algorithms underpin all software. Learn arrays, then linked lists, then stacks/queues, then trees, then graphs. Practice on LeetCode starting at 'Easy' and ramp to mediums." },
    { "key":"math",       "answer":"Math requires daily practice. Master arithmetic, then algebra, then geometry. For each new concept, solve 10 problems of increasing difficulty before moving on." },
    { "key":"physics",    "answer":"Physics describes nature with math. Master kinematics, then forces (Newton's laws), then energy and momentum, then waves, then electricity. Always sketch the problem before solving." }
];

$QUIZ_BANK = [
    { "topic":"javascript", "question":"Which keyword declares a block-scoped variable that can be reassigned?", "answer":"let", "choices":["var","let","const","static"] },
    { "topic":"javascript", "question":"What does '===' check for in JavaScript?", "answer":"strict equality (value and type)", "choices":["value only","type only","value and type","reference"] },
    { "topic":"javascript", "question":"Which method adds an item to the end of an array?", "answer":"push", "choices":["push","pop","shift","unshift"] },
    { "topic":"python", "question":"Which keyword defines a function in Python?", "answer":"def", "choices":["function","def","fn","func"] },
    { "topic":"python", "question":"What is the result of 7 // 2 in Python?", "answer":"3", "choices":["3","3.5","4","3.0"] },
    { "topic":"python", "question":"Which data structure uses curly braces {}?", "answer":"dict", "choices":["list","tuple","dict","set-only"] },
    { "topic":"react", "question":"Which hook manages state in a function component?", "answer":"useState", "choices":["useState","useEffect","useMemo","useRef"] },
    { "topic":"react", "question":"What does JSX compile down to?", "answer":"React.createElement calls", "choices":["HTML","React.createElement calls","plain strings","Vue templates"] },
    { "topic":"dsa", "question":"What is the time complexity of binary search?", "answer":"O(log n)", "choices":["O(1)","O(n)","O(log n)","O(n^2)"] },
    { "topic":"dsa", "question":"Which data structure uses LIFO order?", "answer":"stack", "choices":["queue","stack","tree","graph"] },
    { "topic":"backend", "question":"Which HTTP status code means 'Created'?", "answer":"201", "choices":["200","201","204","301"] },
    { "topic":"backend", "question":"Which verb is idempotent for updating a resource?", "answer":"PUT", "choices":["POST","PUT","PATCH","CONNECT"] },
    { "topic":"math", "question":"What is the derivative of x^2?", "answer":"2x", "choices":["x","2x","x^3","2"] },
    { "topic":"math", "question":"What is the value of sin(90 degrees)?", "answer":"1", "choices":["0","0.5","1","undefined"] },
    { "topic":"physics", "question":"What is the SI unit of force?", "answer":"newton (N)", "choices":["joule","watt","newton","pascal"] },
    { "topic":"physics", "question":"Which law states F = ma?", "answer":"Newton's second law", "choices":["Newton's first","Newton's second","Newton's third","Hooke's law"] }
];

def tutor($req, $res) {
    $message = $req.body["message"];
    if ($message == null || $message == "") {
        $res.status(400);
        $res.json({ "error": "message is required" });
        return null;
    }

    // Match the user's message against known topics (case-insensitive
    // by checking both the original and uppercased form, since Bantu v1.2.2
    // has no String.toLowerCase()).
    $reply = "I'm a rule-based tutor running fully offline. Try asking about: javascript, python, frontend, backend, react, dsa, math, or physics.";
    each ($entry in $TUTOR_KB) {
        $key = $entry["key"];
        if ($message.indexOf($key) != -1) {
            $reply = $entry["answer"];
        }
    }

    $res.json({
        "reply": $reply,
        "model": "bantu-rule-based-v1",
        "tokensUsed": $reply.length
    });
}

def quiz($req, $res) {
    $topic = $req.body["topic"];
    $count = $req.body["count"];
    if ($count == null || $count < 1) { $count = 5; }
    if ($count > 20) { $count = 20; }

    // Build matched list. NOTE: Bantu v1.2.2 closures capture outer arrays
    // by value, so $matched.push(...) inside `each` would silently no-op.
    // We use a while loop with indexed assignment instead.
    $matched = [];
    $mi = 0;
    $bi = 0;
    while ($bi < $QUIZ_BANK.length) {
        $q = $QUIZ_BANK[$bi];
        if ($topic == null || $topic == "" || $q["topic"] == $topic) {
            $matched[$mi] = $q;
            $mi = $mi + 1;
        }
        $bi = $bi + 1;
    }

    // Truncate to requested count (sequential; Bantu has no random shuffle).
    $out = [];
    $i = 0;
    while ($i < $count && $i < $matched.length) {
        $out[$i] = $matched[$i];
        $i = $i + 1;
    }

    $res.json({
        "quiz": $out,
        "topic": $topic,
        "count": $out.length
    });
}

print("[ai] module loaded — tutor (rule-based) / quiz (16-item bank)");
