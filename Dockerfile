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
    <title>QuizVault Dashboard</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-color: #0B0F19;
            --card-bg: rgba(20, 27, 45, 0.7);
            --text-main: #F8FAFC;
            --text-muted: #94A3B8;
            --primary: #3B82F6;
            --primary-hover: #2563EB;
            --accent: #8B5CF6;
            --border: rgba(255, 255, 255, 0.08);
            --success: #10B981;
            --glow: rgba(59, 130, 246, 0.5);
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
            font-family: 'Inter', sans-serif;
        }

        body {
            background-color: var(--bg-color);
            background-image: 
                radial-gradient(circle at 15% 50%, rgba(59, 130, 246, 0.08), transparent 25%),
                radial-gradient(circle at 85% 30%, rgba(139, 92, 246, 0.08), transparent 25%);
            color: var(--text-main);
            line-height: 1.6;
            min-height: 100vh;
            padding: 2rem;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
        }

        header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 3rem;
            padding-bottom: 1.5rem;
            border-bottom: 1px solid var(--border);
            animation: fadeInDown 0.6s ease-out;
        }

        .logo {
            font-size: 2.5rem;
            font-weight: 800;
            background: linear-gradient(135deg, #60A5FA, #C084FC);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            letter-spacing: -1px;
            text-shadow: 0 0 30px rgba(139, 92, 246, 0.4);
        }

        .status-badge {
            background: rgba(16, 185, 129, 0.1);
            color: var(--success);
            padding: 0.5rem 1rem;
            border-radius: 999px;
            font-size: 0.85rem;
            font-weight: 600;
            border: 1px solid rgba(16, 185, 129, 0.2);
            box-shadow: 0 0 15px rgba(16, 185, 129, 0.1);
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }

        .status-badge::before {
            content: '';
            width: 8px;
            height: 8px;
            background: var(--success);
            border-radius: 50%;
            box-shadow: 0 0 8px var(--success);
            animation: pulse 2s infinite;
        }

        .grid {
            display: grid;
            grid-template-columns: 1fr;
            gap: 2rem;
        }

        @media(min-width: 900px) {
            .grid {
                grid-template-columns: 350px 1fr;
            }
        }

        .card {
            background: var(--card-bg);
            backdrop-filter: blur(12px);
            -webkit-backdrop-filter: blur(12px);
            border-radius: 20px;
            padding: 2rem;
            border: 1px solid var(--border);
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.2), inset 0 1px 0 rgba(255,255,255,0.05);
            transition: transform 0.3s cubic-bezier(0.4, 0, 0.2, 1), box-shadow 0.3s;
            animation: fadeInUp 0.6s ease-out backwards;
        }

        .card:hover {
            transform: translateY(-5px);
            box-shadow: 0 30px 60px rgba(0, 0, 0, 0.3), 0 0 20px rgba(59, 130, 246, 0.1), inset 0 1px 0 rgba(255,255,255,0.05);
        }

        h2 {
            font-size: 1.5rem;
            font-weight: 700;
            margin-bottom: 1.5rem;
            display: flex;
            align-items: center;
            gap: 0.75rem;
        }

        .file-upload-wrapper {
            position: relative;
            border: 2px dashed rgba(59, 130, 246, 0.4);
            background: rgba(59, 130, 246, 0.03);
            border-radius: 16px;
            padding: 3rem 2rem;
            text-align: center;
            transition: all 0.3s;
            cursor: pointer;
            overflow: hidden;
        }

        .file-upload-wrapper:hover {
            border-color: var(--primary);
            background: rgba(59, 130, 246, 0.08);
        }

        .file-upload-wrapper input[type="file"] {
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            opacity: 0;
            cursor: pointer;
            z-index: 10;
        }

        .upload-icon {
            width: 56px;
            height: 56px;
            color: var(--primary);
            margin-bottom: 1rem;
            filter: drop-shadow(0 0 10px rgba(59, 130, 246, 0.4));
            transition: transform 0.3s;
        }

        .file-upload-wrapper:hover .upload-icon {
            transform: translateY(-5px);
        }

        .btn {
            background: linear-gradient(135deg, var(--primary), #6366F1);
            color: white;
            border: none;
            padding: 1rem 2rem;
            border-radius: 12px;
            font-weight: 600;
            font-size: 1rem;
            cursor: pointer;
            transition: all 0.2s;
            display: block;
            width: 100%;
            margin-top: 1.5rem;
            box-shadow: 0 10px 20px rgba(59, 130, 246, 0.3);
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 15px 25px rgba(59, 130, 246, 0.4);
        }

        .btn:active {
            transform: translateY(1px);
        }

        .quiz-list {
            display: flex;
            flex-direction: column;
            gap: 1.5rem;
        }

        .quiz {
            background: rgba(255, 255, 255, 0.02);
            border: 1px solid var(--border);
            border-radius: 16px;
            padding: 1.5rem;
            transition: all 0.3s;
        }

        .quiz:hover {
            background: rgba(255, 255, 255, 0.04);
            border-color: rgba(255, 255, 255, 0.1);
        }

        .quiz h3 {
            font-size: 1.25rem;
            color: white;
            margin-bottom: 1rem;
            font-weight: 600;
        }

        .tags {
            display: flex;
            flex-wrap: wrap;
            gap: 0.5rem;
            margin-bottom: 1.5rem;
        }

        .tag {
            background: rgba(255, 255, 255, 0.05);
            color: var(--text-muted);
            padding: 0.4rem 1rem;
            border-radius: 999px;
            font-size: 0.8rem;
            font-weight: 500;
            border: 1px solid rgba(255, 255, 255, 0.05);
            transition: all 0.2s;
        }

        .tag:hover {
            background: rgba(255, 255, 255, 0.1);
            color: white;
        }

        .tag.class { color: var(--success); background: rgba(16, 185, 129, 0.1); border-color: rgba(16, 185, 129, 0.2); }
        .tag.subject { color: #F472B6; background: rgba(244, 114, 182, 0.1); border-color: rgba(244, 114, 182, 0.2); }
        .tag.test-type { color: #38BDF8; background: rgba(56, 189, 248, 0.1); border-color: rgba(56, 189, 248, 0.2); }

        details {
            background: rgba(0, 0, 0, 0.2);
            border-radius: 12px;
            border: 1px solid rgba(255, 255, 255, 0.05);
            overflow: hidden;
        }

        summary {
            padding: 1rem 1.5rem;
            cursor: pointer;
            font-weight: 500;
            color: var(--text-muted);
            transition: all 0.2s;
            outline: none;
            user-select: none;
        }

        summary:hover {
            background: rgba(255, 255, 255, 0.02);
            color: white;
        }

        pre {
            padding: 1.5rem;
            background: #000;
            color: #A78BFA;
            font-family: 'JetBrains Mono', monospace;
            font-size: 0.85rem;
            overflow-x: auto;
            border-top: 1px solid rgba(255, 255, 255, 0.05);
            line-height: 1.5;
        }

        .format-guide {
            margin-top: 2rem;
            background: rgba(0,0,0,0.3);
            border-radius: 12px;
            padding: 1.5rem;
            border: 1px solid var(--border);
        }

        .format-guide h4 {
            color: var(--text-muted);
            margin-bottom: 1rem;
            font-size: 0.9rem;
            text-transform: uppercase;
            letter-spacing: 1px;
        }

        .format-guide pre {
            border: none;
            padding: 1rem;
            border-radius: 8px;
            background: rgba(0,0,0,0.5);
            color: var(--text-muted);
        }

        @keyframes fadeInDown {
            from { opacity: 0; transform: translateY(-20px); }
            to { opacity: 1; transform: translateY(0); }
        }

        @keyframes fadeInUp {
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }

        @keyframes pulse {
            0% { box-shadow: 0 0 0 0 rgba(16, 185, 129, 0.4); }
            70% { box-shadow: 0 0 0 6px rgba(16, 185, 129, 0); }
            100% { box-shadow: 0 0 0 0 rgba(16, 185, 129, 0); }
        }
        
        /* Staggered animation delays for quizzes */
        .quiz:nth-child(1) { animation-delay: 0.1s; }
        .quiz:nth-child(2) { animation-delay: 0.2s; }
        .quiz:nth-child(3) { animation-delay: 0.3s; }
        .quiz:nth-child(4) { animation-delay: 0.4s; }

    </style>
</head>
<body>

    <div class="container">
        <header>
            <div class="logo">QuizVault</div>
            <div class="status-badge">System Online</div>
        </header>

        <div class="grid">
            <div class="upload-section">
                <div class="card" style="animation-delay: 0.1s">
                    <h2>
                        <svg width="24" height="24" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"></path></svg>
                        Upload Quiz
                    </h2>
                    
                    <form action="/upload" method="POST" enctype="multipart/form-data">
                        <div class="file-upload-wrapper" id="dropzone">
                            <input type="file" name="file" accept=".txt" required id="fileInput">
                            <svg class="upload-icon" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path></svg>
                            <p style="font-weight: 600; color: white; margin-bottom: 0.5rem;" id="fileName">Select .txt file</p>
                            <p style="font-size: 0.85rem; color: var(--text-muted);">or drag and drop here</p>
                        </div>
                        <button type="submit" class="btn">Initialize Upload</button>
                    </form>
                    
                    <div class="format-guide">
                        <h4>Format Standard</h4>
                        <pre>TITLE: Physics Test
CLASS: 12
SUBJECT: Physics
CHAPTER: Optics
TEST_TYPE: Mains
QUESTION_TYPE: MCQ

QUESTION: What is light?
OPTION1: Wave
OPTION2: Particle
OPTION3: Both
OPTION4: None
ANSWER: 3</pre>
                    </div>
                </div>
            </div>

            <div class="dashboard-section">
                <div class="card" style="animation-delay: 0.2s">
                    <h2>
                        <svg width="24" height="24" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 002-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"></path></svg>
                        Quiz Repository
                    </h2>
                    
                    <div class="quiz-list">
                        {% if quizzes %}
                            {% for q in quizzes %}
                            <div class="quiz card">
                                <h3>{{ q[1] }}</h3>
                                <div class="tags">
                                    <span class="tag class">Class {{ q[2] }}</span>
                                    <span class="tag subject">{{ q[3] }}</span>
                                    <span class="tag">{{ q[4] }}</span>
                                    <span class="tag test-type">{{ q[5] }}</span>
                                    <span class="tag">{{ q[6] }}</span>
                                </div>
                                <details>
                                    <summary>Take Quiz</summary>
                                    <pre class="raw-data" style="display:none;">{{ q[7] }}</pre>
                                    <div class="interactive-quiz"></div>
                                </details>
                            </div>
                            {% endfor %}
                        {% else %}
                            <div style="text-align: center; padding: 3rem; color: var(--text-muted); border: 1px dashed var(--border); border-radius: 12px;">
                                <p>Database is empty. Upload your first quiz to populate the repository.</p>
                            </div>
                        {% endif %}
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <script>
        // Simple script to update file name on select
        document.getElementById('fileInput').addEventListener('change', function(e) {
            if(e.target.files.length > 0) {
                document.getElementById('fileName').textContent = e.target.files[0].name;
                document.getElementById('dropzone').style.borderColor = 'var(--success)';
            }
        });

        // Interactive Quiz Parser and Logic
        document.querySelectorAll('.quiz.card').forEach(quizCard => {
            const rawDataEl = quizCard.querySelector('.raw-data');
            if (!rawDataEl) return;
            const rawText = rawDataEl.textContent;
            const quizContainer = quizCard.querySelector('.interactive-quiz');
            
            // Parse the text
            const lines = rawText.split('\n');
            let questions = [];
            let currentQ = null;
            
            lines.forEach(line => {
                line = line.trim();
                if (line.startsWith('QUESTION:')) {
                    if (currentQ) questions.push(currentQ);
                    currentQ = { question: line.substring(9).trim(), options: [], answer: null };
                } else if (line.startsWith('OPTION')) {
                    let parts = line.split(':');
                    if (parts.length > 1 && currentQ) {
                        currentQ.options.push(parts.slice(1).join(':').trim());
                    }
                } else if (line.startsWith('ANSWER:')) {
                    if (currentQ) {
                        currentQ.answer = parseInt(line.substring(7).trim());
                    }
                }
            });
            if (currentQ) questions.push(currentQ);
            
            // Render
            let html = '';
            questions.forEach((q, idx) => {
                html += `<div class="question-block" style="margin-top: 1.5rem; background: rgba(0,0,0,0.3); padding: 1.5rem; border-radius: 12px; border: 1px solid rgba(255,255,255,0.05);">
                    <p style="font-weight: 600; margin-bottom: 1rem; font-size: 1.1rem; color: white;">Q${idx+1}. ${q.question}</p>
                    <div class="options-container" data-answer="${q.answer}">`;
                q.options.forEach((opt, optIdx) => {
                    html += `<button class="quiz-option-btn" data-index="${optIdx + 1}" style="display: block; width: 100%; text-align: left; background: rgba(255,255,255,0.03); border: 1px solid rgba(255,255,255,0.1); padding: 1rem 1.25rem; border-radius: 8px; color: var(--text-muted); cursor: pointer; margin-bottom: 0.5rem; transition: all 0.2s; font-size: 0.95rem;">
                        <span style="display: inline-block; width: 24px; height: 24px; background: rgba(255,255,255,0.1); border-radius: 50%; text-align: center; line-height: 24px; margin-right: 10px; font-size: 0.8rem;">${optIdx + 1}</span> 
                        ${opt}
                    </button>`;
                });
                html += `</div></div>`;
            });
            
            quizContainer.innerHTML = html;
            
            // Attach event listeners
            quizContainer.querySelectorAll('.options-container').forEach(container => {
                const correctAns = parseInt(container.dataset.answer);
                const btns = container.querySelectorAll('.quiz-option-btn');
                btns.forEach(btn => {
                    // Add hover effect via JS since inline styles override CSS
                    btn.addEventListener('mouseenter', function() {
                        if(!this.disabled) {
                            this.style.background = 'rgba(255,255,255,0.08)';
                            this.style.color = 'white';
                        }
                    });
                    btn.addEventListener('mouseleave', function() {
                        if(!this.disabled && !this.classList.contains('selected')) {
                            this.style.background = 'rgba(255,255,255,0.03)';
                            this.style.color = 'var(--text-muted)';
                        }
                    });

                    btn.addEventListener('click', function() {
                        // Disable all buttons in this container after click
                        btns.forEach(b => {
                            b.disabled = true;
                            b.style.cursor = 'default';
                        });
                        
                        this.classList.add('selected');
                        this.style.color = 'white';
                        
                        const selected = parseInt(this.dataset.index);
                        if (selected === correctAns) {
                            // Correct - Green
                            this.style.background = 'rgba(16, 185, 129, 0.15)';
                            this.style.borderColor = 'var(--success)';
                            this.style.boxShadow = '0 0 15px rgba(16, 185, 129, 0.2)';
                        } else {
                            // Wrong - Red
                            this.style.background = 'rgba(239, 68, 68, 0.15)';
                            this.style.borderColor = '#EF4444';
                            this.style.boxShadow = '0 0 15px rgba(239, 68, 68, 0.2)';
                            
                            // Highlight correct answer
                            const correctBtn = container.querySelector(`[data-index="${correctAns}"]`);
                            if (correctBtn) {
                                correctBtn.style.background = 'rgba(16, 185, 129, 0.15)';
                                correctBtn.style.borderColor = 'var(--success)';
                                correctBtn.style.color = 'white';
                            }
                        }
                    });
                });
            });
        });
    </script>
</body>
</html>
HTMLEOF

EXPOSE 8000

CMD ["python", "app.py"]
