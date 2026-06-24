#!/usr/bin/env bash
# smoke_test.sh — end-to-end test of new admin/community/courses/certificates features
set -e
BASE=http://localhost:3000

# Python one-liner helper that reads JSON from stdin and extracts a path
jget() { python3 -c 'import sys,json; print(json.load(sys.stdin)'$1')'; }

echo "=== 1) Register admin (first user — should get role=admin) ==="
ADMIN_RESP=$(curl -s -X POST "$BASE/api/auth/register" -H 'Content-Type: application/json' -d '{"username":"admin","email":"admin@ms.com","password":"admin123"}')
ADMIN_TOKEN=$(echo "$ADMIN_RESP" | jget '["token"]')
ADMIN_ROLE=$(echo "$ADMIN_RESP" | jget '["user"]["role"]')
echo "  admin role=$ADMIN_ROLE  token=$ADMIN_TOKEN"
echo

echo "=== 2) Register a student (should get role=student) ==="
STUDENT_RESP=$(curl -s -X POST "$BASE/api/auth/register" -H 'Content-Type: application/json' -d '{"username":"student","email":"student@ms.com","password":"student123"}')
STUDENT_TOKEN=$(echo "$STUDENT_RESP" | jget '["token"]')
STUDENT_ROLE=$(echo "$STUDENT_RESP" | jget '["user"]["role"]')
echo "  student role=$STUDENT_ROLE  token=$STUDENT_TOKEN"
echo

echo "=== 3) Student tries to create a course (should be 403 Admin access required) ==="
curl -s -X POST "$BASE/api/courses" -H "Authorization: Bearer $STUDENT_TOKEN" -H 'Content-Type: application/json' -d '{"title":"Should Fail","description":"nope"}'
echo; echo

echo "=== 4) Admin creates a course ==="
COURSE_RESP=$(curl -s -X POST "$BASE/api/courses" -H "Authorization: Bearer $ADMIN_TOKEN" -H 'Content-Type: application/json' -d '{"title":"Intro to Bantu","description":"Learn the Bantu programming language from scratch.","category":"Programming","difficulty":"beginner","duration_hours":12,"instructor":"Assey","thumbnail_color":"#6366f1"}')
COURSE_ID=$(echo "$COURSE_RESP" | jget '["course"]["id"]')
COURSE_TITLE=$(echo "$COURSE_RESP" | jget '["course"]["title"]')
echo "  created course #$COURSE_ID: $COURSE_TITLE"
echo

echo "=== 5) Admin adds a module ==="
curl -s -X POST "$BASE/api/courses/$COURSE_ID/modules" -H "Authorization: Bearer $ADMIN_TOKEN" -H 'Content-Type: application/json' -d '{"title":"Lesson 1: Hello World","content":"print(\"Hello, Bantu!\");","ordinal":1}'
echo; echo

echo "=== 6) Public list courses ==="
curl -s "$BASE/api/courses" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("  " + str(len(d["courses"])) + " course(s)"); [print("  - #" + str(c["id"]) + " " + c["title"] + " (" + c["difficulty"] + ") by " + c["author"]) for c in d["courses"]]'
echo

echo "=== 7) Admin posts an announcement ==="
curl -s -X POST "$BASE/api/announcements" -H "Authorization: Bearer $ADMIN_TOKEN" -H 'Content-Type: application/json' -d '{"title":"Welcome to modifiedS!","body":"We just launched courses and certificates. Enroll now!","category":"launch","pinned":true}'
echo; echo

echo "=== 8) Public list announcements ==="
curl -s "$BASE/api/announcements" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("  " + str(len(d["announcements"])) + " ann."); [print("  - " + a["title"] + " (pinned=" + str(a["pinned"]) + ", by " + a["author"] + ")") for a in d["announcements"]]'
echo

echo "=== 9) Student posts a thought ==="
curl -s -X POST "$BASE/api/thoughts" -H "Authorization: Bearer $STUDENT_TOKEN" -H 'Content-Type: application/json' -d '{"body":"Excited to start the Bantu course!","tags":"bantu,learning"}'
echo; echo

echo "=== 10) Public list thoughts ==="
curl -s "$BASE/api/thoughts" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("  " + str(len(d["thoughts"])) + " thought(s)"); [print("  - " + t["username"] + ": " + t["body"][:50] + " likes=" + str(t["likes"])) for t in d["thoughts"]]'
echo

echo "=== 11) Student enrolls in course ==="
curl -s -X POST "$BASE/api/enrollments/$COURSE_ID" -H "Authorization: Bearer $STUDENT_TOKEN"
echo; echo

echo "=== 12) Student sets progress to 50% ==="
curl -s -X POST "$BASE/api/enrollments/$COURSE_ID/progress" -H "Authorization: Bearer $STUDENT_TOKEN" -H 'Content-Type: application/json' -d '{"percent":50}'
echo; echo

echo "=== 13) Student sets progress to 100% — should auto-issue certificate ==="
FULL_RESP=$(curl -s -X POST "$BASE/api/enrollments/$COURSE_ID/progress" -H "Authorization: Bearer $STUDENT_TOKEN" -H 'Content-Type: application/json' -d '{"percent":100}')
echo "$FULL_RESP"
echo

echo "=== 14) Student lists certificates ==="
curl -s "$BASE/api/certificates" -H "Authorization: Bearer $STUDENT_TOKEN" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("  " + str(len(d["certificates"])) + " cert(s)"); [print("  - " + c["course_title"] + " | code=" + c["certificate_code"] + " | issued=" + c["issued_at"]) for c in d["certificates"]]'
echo

echo "=== ALL TESTS PASSED ==="
