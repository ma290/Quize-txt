FROM python:3.11-slim

WORKDIR /app

RUN pip install flask python-dotenv requests

ENV PORT=8000
ENV BOT_TOKEN=""
ENV CHANNEL_ID=""

RUN mkdir -p templates backups

RUN cat > app.py << 'PYEOF'
from flask import Flask, render_template, request, redirect
import sqlite3
import os
import requests
from dotenv import load_dotenv
from datetime import datetime

load_dotenv()

BOT_TOKEN = os.getenv("BOT_TOKEN")
CHANNEL_ID = os.getenv("CHANNEL_ID")
PORT = int(os.getenv("PORT", 8000))

app = Flask(__name__)

DB_FILE = "quiz.db"

def init_db():
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()

    c.execute('''
    CREATE TABLE IF NOT EXISTS quizzes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT,
    class_name TEXT,
    subject TEXT,
    chapter TEXT,
    test_type TEXT,
    question_type TEXT,
    content TEXT
    )
    ''')

    conn.commit()
    conn.close()

init_db()

def backup_database():
    if not BOT_TOKEN or not CHANNEL_ID:
        return

    backup_name = f"backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}.db"
    os.system(f"cp {DB_FILE} {backup_name}")

    try:
        with open(backup_name, "rb") as f:
            requests.post(
                f"https://api.telegram.org/bot{BOT_TOKEN}/sendDocument",
                data={
                    "chat_id": CHANNEL_ID,
                    "caption": "Quiz DB Backup"
                },
                files={
                    "document": f
                }
            )
    except Exception as e:
        print("Telegram backup failed:", e)

def parse_quiz(text):
    lines = text.splitlines()

    data = {
        "title": "",
        "class_name": "",
        "subject": "",
        "chapter": "",
        "test_type": "",
        "question_type": "",
        "content": text
    }

    for line in lines:
        if line.startswith("TITLE:"):
            data["title"] = line.replace("TITLE:", "").strip()
        elif line.startswith("CLASS:"):
            data["class_name"] = line.replace("CLASS:", "").strip()
        elif line.startswith("SUBJECT:"):
            data["subject"] = line.replace("SUBJECT:", "").strip()
        elif line.startswith("CHAPTER:"):
            data["chapter"] = line.replace("CHAPTER:", "").strip()
        elif line.startswith("TEST_TYPE:"):
            data["test_type"] = line.replace("TEST_TYPE:", "").strip()
        elif line.startswith("QUESTION_TYPE:"):
            data["question_type"] = line.replace("QUESTION_TYPE:", "").strip()

    return data

@app.route('/')
def home():
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()

    c.execute("SELECT * FROM quizzes ORDER BY id DESC")
    quizzes = c.fetchall()

    conn.close()

    return render_template("index.html", quizzes=quizzes)

@app.route('/upload', methods=['POST'])
def upload():
    file = request.files['file']

    if file:
        content = file.read().decode("utf-8")
        data = parse_quiz(content)

        conn = sqlite3.connect(DB_FILE)
        c = conn.cursor()

        c.execute('''
        INSERT INTO quizzes
        (title, class_name, subject, chapter, test_type, question_type, content)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (
            data["title"],
            data["class_name"],
            data["subject"],
            data["chapter"],
            data["test_type"],
            data["question_type"],
            data["content"]
        ))

        conn.commit()
        conn.close()

        backup_database()

    return redirect('/')

if __name__ == '__main__':
    app.run(host="0.0.0.0", port=PORT)
PYEOF

RUN cat > templates/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">

<head>

<meta charset="UTF-8">

<meta name="viewport" content="width=device-width, initial-scale=1.0">

<title>QuizVault</title>

<style>

body{
background:#070707;
color:white;
font-family:Arial;
margin:0;
padding:40px;
}

.container{
max-width:1100px;
margin:auto;
}

h1{
font-size:60px;
margin-bottom:30px;
}

.card{
background:#151515;
border:1px solid #2a2a2a;
border-radius:20px;
padding:25px;
margin-bottom:25px;
}

input[type=file]{
width:100%;
padding:18px;
border:none;
border-radius:14px;
background:#1f1f1f;
color:white;
margin-bottom:15px;
}

button{
width:100%;
padding:16px;
border:none;
border-radius:14px;
background:white;
color:black;
font-weight:bold;
cursor:pointer;
}

.quiz{
background:#1b1b1b;
border:1px solid #2d2d2d;
border-radius:18px;
padding:20px;
margin-top:20px;
}

.tag{
display:inline-block;
padding:8px 14px;
border-radius:999px;
background:#2a2a2a;
margin:5px;
font-size:13px;
}

pre{
white-space:pre-wrap;
background:#111;
padding:15px;
border-radius:14px;
overflow-x:auto;
margin-top:15px;
}

</style>

</head>

<body>

<div class="container">

<h1>QuizVault</h1>

<div class="card">

<h2>Upload Quiz TXT</h2>

<form action="/upload" method="POST" enctype="multipart/form-data">

<input type="file" name="file" accept=".txt" required>

<button type="submit">
Upload Quiz
</button>

</form>

</div>

<div class="card">

<h2>TXT Format</h2>

<pre>
TITLE: Biology Quiz
CLASS: 10
SUBJECT: Biology
CHAPTER: Cell
TEST_TYPE: Chapterwise
QUESTION_TYPE: Normal

QUESTION: What is mitochondria?

OPTION1: Organ
OPTION2: Cell
OPTION3: Powerhouse
OPTION4: Bone

ANSWER: 3
</pre>

</div>

<div class="card">

<h2>Uploaded Quizzes</h2>

{% for q in quizzes %}

<div class="quiz">

<h3>{{ q[1] }}</h3>

<div>

<span class="tag">
Class {{ q[2] }}
</span>

<span class="tag">
{{ q[3] }}
</span>

<span class="tag">
{{ q[4] }}
</span>

<span class="tag">
{{ q[5] }}
</span>

<span class="tag">
{{ q[6] }}
</span>

</div>

<pre>{{ q[7] }}</pre>

</div>

{% endfor %}

</div>

</div>

</body>
</html>
HTMLEOF

EXPOSE 8000

CMD ["python", "app.py"]