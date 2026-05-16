FROM python:3.11-slim

WORKDIR /app

RUN pip install flask python-dotenv pyrogram tgcrypto

ENV PORT=8000
ENV BOT_TOKEN=""
ENV CHANNEL_ID=""

RUN mkdir -p uploads backups templates static

# =========================
# MAIN APP
# =========================

RUN cat > app.py << 'EOF'
from flask import Flask, render_template, request, redirect
import sqlite3
import os
from dotenv import load_dotenv
from pyrogram import Client
from datetime import datetime

load_dotenv()

BOT_TOKEN = os.getenv("BOT_TOKEN")
CHANNEL_ID = os.getenv("CHANNEL_ID")
PORT = int(os.getenv("PORT", 8000))

app = Flask(__name__)

DB_FILE = "quiz.db"

# =========================
# DATABASE INIT
# =========================

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

# =========================
# TELEGRAM BACKUP
# =========================

def backup_database():
    if not BOT_TOKEN or not CHANNEL_ID:
        return

    backup_name = f"backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}.db"

    os.system(f"cp {DB_FILE} {backup_name}")

    try:
        app_telegram = Client(
            "backup_bot",
            bot_token=BOT_TOKEN,
            api_id=12345,
            api_hash="0123456789abcdef0123456789abcdef"
        )

        app_telegram.start()

        app_telegram.send_document(
            chat_id=CHANNEL_ID,
            document=backup_name,
            caption="Quiz DB Backup"
        )

        app_telegram.stop()

    except Exception as e:
        print("Telegram backup failed:", e)

# =========================
# TXT PARSER
# =========================

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

# =========================
# ROUTES
# =========================

@app.route('/')
def home():
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()

    c.execute("SELECT * FROM quizzes ORDER BY id DESC")
    quizzes = c.fetchall()

    conn.close()

    return render_template('index.html', quizzes=quizzes)

@app.route('/upload', methods=['POST'])
def upload():
    file = request.files['file']

    if file:
        content = file.read().decode('utf-8')

        data = parse_quiz(content)

        conn = sqlite3.connect(DB_FILE)
        c = conn.cursor()

        c.execute('''
            INSERT INTO quizzes
            (title, class_name, subject, chapter, test_type, question_type, content)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (
            data['title'],
            data['class_name'],
            data['subject'],
            data['chapter'],
            data['test_type'],
            data['question_type'],
            data['content']
        ))

        conn.commit()
        conn.close()

        backup_database()

    return redirect('/')

app.run(host='0.0.0.0', port=PORT)
EOF

# =========================
# HTML UI
# =========================

RUN cat > templates/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Quiz Platform</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">

    <style>
        body {
            margin: 0;
            font-family: Arial;
            background: #0f0f0f;
            color: white;
            padding: 30px;
        }

        .container {
            max-width: 1200px;
            margin: auto;
        }

        .card {
            background: #1c1c1c;
            border-radius: 20px;
            padding: 20px;
            margin-bottom: 20px;
            border: 1px solid #333;
        }

        h1 {
            font-size: 40px;
        }

        input[type=file] {
            padding: 12px;
            background: #222;
            border-radius: 12px;
            color: white;
            width: 100%;
            margin-bottom: 15px;
        }

        button {
            background: white;
            color: black;
            border: none;
            padding: 14px 25px;
            border-radius: 14px;
            font-weight: bold;
            cursor: pointer;
        }

        .tag {
            display: inline-block;
            background: #333;
            padding: 8px 14px;
            border-radius: 999px;
            margin: 5px;
            font-size: 14px;
        }

        pre {
            white-space: pre-wrap;
            overflow-x: auto;
        }
    </style>
</head>
<body>

<div class="container">

<h1>Quiz Upload Dashboard</h1>

<div class="card">
    <h2>Upload TXT Quiz</h2>

    <form action="/upload" method="POST" enctype="multipart/form-data">
        <input type="file" name="file" accept=".txt" required>
        <button type="submit">Upload Quiz</button>
    </form>
</div>

<div class="card">
    <h2>TXT Format</h2>

<pre>
TITLE: Biology Test
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

<h2>Uploaded Quizzes</h2>

{% for q in quizzes %}
<div class="card">
    <h3>{{ q[1] }}</h3>

    <div>
        <span class="tag">Class {{ q[2] }}</span>
        <span class="tag">{{ q[3] }}</span>
        <span class="tag">{{ q[4] }}</span>
        <span class="tag">{{ q[5] }}</span>
        <span class="tag">{{ q[6] }}</span>
    </div>

    <details style="margin-top:15px;">
        <summary>View Quiz</summary>
        <pre>{{ q[7] }}</pre>
    </details>
</div>
{% endfor %}

</div>

</body>
</html>
EOF

EXPOSE 8000

CMD ["python", "app.py"]
