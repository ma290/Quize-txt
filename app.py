import os
import sqlite3
import json
import threading
import requests
from flask import Flask, render_template_string, request, redirect, url_for, flash
from werkzeug.utils import secure_filename
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)
app.secret_key = os.urandom(24)
DB_NAME = 'quizvault.db'

# --- Telegram Backup Logic ---
BOT_TOKEN = os.getenv('BOT_TOKEN')
CHANNEL_ID = os.getenv('CHANNEL_ID')

def backup_db_to_telegram():
    if not BOT_TOKEN or not CHANNEL_ID:
        print("Telegram credentials missing, skipping backup.")
        return
    
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendDocument"
    try:
        with open(DB_NAME, 'rb') as f:
            response = requests.post(
                url,
                data={'chat_id': CHANNEL_ID, 'caption': 'QuizVault Database Backup'},
                files={'document': f}
            )
        print("Telegram Backup Response:", response.json())
    except Exception as e:
        print("Telegram Backup Error:", e)

def trigger_backup():
    thread = threading.Thread(target=backup_db_to_telegram)
    thread.start()

# --- Database Setup ---
def init_db():
    with sqlite3.connect(DB_NAME) as conn:
        cursor = conn.cursor()
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS quizzes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                class_level TEXT,
                subject TEXT,
                chapter TEXT,
                test_type TEXT,
                question_type TEXT,
                content JSON NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        conn.commit()

init_db()

# --- Parser ---
def parse_quiz_file(file_content):
    lines = file_content.splitlines()
    metadata = {
        'title': 'Unknown Quiz',
        'class_level': '',
        'subject': '',
        'chapter': '',
        'test_type': '',
        'question_type': ''
    }
    
    questions = []
    current_q = None
    
    for line in lines:
        line = line.strip()
        if not line:
            continue
            
        if line.upper().startswith('TITLE:'):
            metadata['title'] = line[6:].strip()
        elif line.upper().startswith('CLASS:'):
            metadata['class_level'] = line[6:].strip()
        elif line.upper().startswith('SUBJECT:'):
            metadata['subject'] = line[8:].strip()
        elif line.upper().startswith('CHAPTER:'):
            metadata['chapter'] = line[8:].strip()
        elif line.upper().startswith('TEST_TYPE:'):
            metadata['test_type'] = line[10:].strip()
        elif line.upper().startswith('QUESTION_TYPE:'):
            metadata['question_type'] = line[14:].strip()
        
        elif line.upper().startswith('QUESTION:'):
            if current_q:
                questions.append(current_q)
            current_q = {'text': line[9:].strip(), 'options': [], 'answer': ''}
        elif line.upper().startswith('OPTION'):
            if current_q:
                parts = line.split(':', 1)
                if len(parts) > 1:
                    current_q['options'].append(parts[1].strip())
        elif line.upper().startswith('ANSWER:'):
            if current_q:
                current_q['answer'] = line[7:].strip()
    
    if current_q:
        questions.append(current_q)
        
    return metadata, questions

# --- HTML Templates ---
HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>QuizVault Dashboard</title>
    <style>
        :root {
            --bg-color: #0f172a;
            --card-bg: #1e293b;
            --text-main: #f8fafc;
            --text-muted: #94a3b8;
            --primary: #3b82f6;
            --primary-hover: #2563eb;
            --accent: #8b5cf6;
            --border: #334155;
            --success: #10b981;
            --error: #ef4444;
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        }

        body {
            background-color: var(--bg-color);
            color: var(--text-main);
            line-height: 1.6;
            min-height: 100vh;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 2rem;
        }

        header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 3rem;
            padding-bottom: 1rem;
            border-bottom: 1px solid var(--border);
        }

        .logo {
            font-size: 2rem;
            font-weight: 800;
            background: linear-gradient(135deg, var(--primary), var(--accent));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }

        .grid {
            display: grid;
            grid-template-columns: 1fr;
            gap: 2rem;
        }

        @media(min-width: 768px) {
            .grid {
                grid-template-columns: 1fr 2fr;
            }
        }

        .card {
            background: var(--card-bg);
            border-radius: 12px;
            padding: 1.5rem;
            border: 1px solid var(--border);
            box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1);
            transition: transform 0.2s, box-shadow 0.2s;
        }

        .card:hover {
            box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.2);
        }

        .upload-section h2 {
            margin-bottom: 1rem;
            font-size: 1.25rem;
        }

        .file-upload-wrapper {
            position: relative;
            border: 2px dashed var(--border);
            border-radius: 8px;
            padding: 2rem;
            text-align: center;
            transition: border-color 0.3s;
            cursor: pointer;
        }

        .file-upload-wrapper:hover {
            border-color: var(--primary);
        }

        .file-upload-wrapper input[type="file"] {
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            opacity: 0;
            cursor: pointer;
        }

        .btn {
            background: var(--primary);
            color: white;
            border: none;
            padding: 0.75rem 1.5rem;
            border-radius: 6px;
            font-weight: 600;
            cursor: pointer;
            transition: background 0.2s, transform 0.1s;
            display: inline-block;
            margin-top: 1rem;
            width: 100%;
        }

        .btn:hover {
            background: var(--primary-hover);
        }

        .btn:active {
            transform: scale(0.98);
        }

        .format-guide {
            margin-top: 1.5rem;
            background: rgba(0,0,0,0.2);
            padding: 1rem;
            border-radius: 8px;
            font-size: 0.85rem;
            color: var(--text-muted);
        }
        
        .format-guide pre {
            font-family: monospace;
            white-space: pre-wrap;
            margin-top: 0.5rem;
            color: var(--text-main);
        }

        .quiz-list {
            display: flex;
            flex-direction: column;
            gap: 1rem;
        }

        .quiz-item {
            background: rgba(255,255,255,0.02);
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 1.25rem;
            transition: background 0.2s;
        }

        .quiz-item:hover {
            background: rgba(255,255,255,0.05);
        }

        .quiz-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 0.75rem;
        }

        .quiz-title {
            font-size: 1.25rem;
            font-weight: 600;
        }

        .tags {
            display: flex;
            flex-wrap: wrap;
            gap: 0.5rem;
            margin-bottom: 1rem;
        }

        .tag {
            background: rgba(59, 130, 246, 0.1);
            color: var(--primary);
            padding: 0.25rem 0.75rem;
            border-radius: 999px;
            font-size: 0.75rem;
            font-weight: 500;
            border: 1px solid rgba(59, 130, 246, 0.2);
        }

        .tag.subject { color: var(--accent); background: rgba(139, 92, 246, 0.1); border-color: rgba(139, 92, 246, 0.2); }
        .tag.class { color: var(--success); background: rgba(16, 185, 129, 0.1); border-color: rgba(16, 185, 129, 0.2); }

        .questions-preview {
            margin-top: 1rem;
            padding-top: 1rem;
            border-top: 1px solid var(--border);
        }
        
        details summary {
            cursor: pointer;
            color: var(--text-muted);
            font-size: 0.9rem;
            outline: none;
            transition: color 0.2s;
        }
        
        details summary:hover {
            color: var(--text-main);
        }
        
        .question-card {
            background: rgba(0,0,0,0.3);
            padding: 1rem;
            border-radius: 6px;
            margin-top: 0.75rem;
        }
        
        .question-text {
            font-weight: 500;
            margin-bottom: 0.5rem;
        }
        
        .options {
            list-style: none;
            margin-bottom: 0.5rem;
            padding-left: 1rem;
        }
        
        .options li {
            font-size: 0.9rem;
            color: var(--text-muted);
            margin-bottom: 0.25rem;
        }
        
        .answer {
            font-size: 0.85rem;
            color: var(--success);
            font-weight: 600;
        }

        .flash-messages {
            margin-bottom: 1rem;
        }

        .flash {
            padding: 1rem;
            border-radius: 6px;
            margin-bottom: 0.5rem;
        }

        .flash.success {
            background: rgba(16, 185, 129, 0.1);
            color: var(--success);
            border: 1px solid var(--success);
        }

        .flash.error {
            background: rgba(239, 68, 68, 0.1);
            color: var(--error);
            border: 1px solid var(--error);
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <div class="logo">QuizVault</div>
            <div>
                <span class="tag">System Active</span>
            </div>
        </header>

        <div class="flash-messages">
            {% with messages = get_flashed_messages(with_categories=true) %}
                {% if messages %}
                    {% for category, message in messages %}
                        <div class="flash {{ category }}">{{ message }}</div>
                    {% endfor %}
                {% endif %}
            {% endwith %}
        </div>

        <div class="grid">
            <div class="upload-section">
                <div class="card">
                    <h2>Upload New Quiz</h2>
                    <form action="/upload" method="post" enctype="multipart/form-data">
                        <div class="file-upload-wrapper">
                            <input type="file" name="quiz_file" accept=".txt" required>
                            <svg style="width:48px;height:48px;color:var(--text-muted);margin-bottom:1rem;" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"></path></svg>
                            <p>Drag & Drop your .txt file here</p>
                            <p style="font-size: 0.8rem; color: var(--text-muted); margin-top: 0.5rem;">Click to browse</p>
                        </div>
                        <button type="submit" class="btn">Process & Upload</button>
                    </form>
                    
                    <div class="format-guide">
                        <strong>Required TXT Format:</strong>
                        <pre>TITLE: Biology Quiz
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
ANSWER: 3</pre>
                    </div>
                </div>
            </div>

            <div class="dashboard-section">
                <div class="card">
                    <h2>Quiz Repository</h2>
                    <div class="quiz-list">
                        {% if quizzes %}
                            {% for quiz in quizzes %}
                            <div class="quiz-item">
                                <div class="quiz-header">
                                    <div class="quiz-title">{{ quiz.title }}</div>
                                    <div style="font-size:0.8rem;color:var(--text-muted);">{{ quiz.created_at[:10] }}</div>
                                </div>
                                <div class="tags">
                                    <span class="tag class">Class {{ quiz.class_level }}</span>
                                    <span class="tag subject">{{ quiz.subject }}</span>
                                    <span class="tag">{{ quiz.chapter }}</span>
                                    <span class="tag">{{ quiz.test_type }}</span>
                                    <span class="tag">{{ quiz.question_type }}</span>
                                </div>
                                <details class="questions-preview">
                                    <summary>View Questions ({{ quiz.content | length }})</summary>
                                    {% for q in quiz.content %}
                                    <div class="question-card">
                                        <div class="question-text">{{ loop.index }}. {{ q.text }}</div>
                                        <ul class="options">
                                            {% for opt in q.options %}
                                            <li>{{ loop.index }}) {{ opt }}</li>
                                            {% endfor %}
                                        </ul>
                                        <div class="answer">Answer: {{ q.answer }}</div>
                                    </div>
                                    {% endfor %}
                                </details>
                            </div>
                            {% endfor %}
                        {% else %}
                            <p style="color: var(--text-muted);">No quizzes uploaded yet. Upload a .txt file to get started.</p>
                        {% endif %}
                    </div>
                </div>
            </div>
        </div>
    </div>
</body>
</html>
"""

# --- Routes ---
@app.route('/')
def index():
    with sqlite3.connect(DB_NAME) as conn:
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM quizzes ORDER BY id DESC")
        rows = cursor.fetchall()
        
        quizzes = []
        for row in rows:
            q = dict(row)
            q['content'] = json.loads(q['content'])
            quizzes.append(q)
            
    return render_template_string(HTML_TEMPLATE, quizzes=quizzes)

@app.route('/upload', methods=['POST'])
def upload():
    if 'quiz_file' not in request.files:
        flash('No file part', 'error')
        return redirect(url_for('index'))
        
    file = request.files['quiz_file']
    if file.filename == '':
        flash('No selected file', 'error')
        return redirect(url_for('index'))
        
    if file and file.filename.endswith('.txt'):
        try:
            content = file.read().decode('utf-8')
            metadata, questions = parse_quiz_file(content)
            
            with sqlite3.connect(DB_NAME) as conn:
                cursor = conn.cursor()
                cursor.execute('''
                    INSERT INTO quizzes (title, class_level, subject, chapter, test_type, question_type, content)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                ''', (
                    metadata['title'],
                    metadata['class_level'],
                    metadata['subject'],
                    metadata['chapter'],
                    metadata['test_type'],
                    metadata['question_type'],
                    json.dumps(questions)
                ))
                conn.commit()
                
            flash(f"Successfully uploaded: {metadata['title']}", 'success')
            trigger_backup()
            
        except Exception as e:
            flash(f"Error processing file: {str(e)}", 'error')
    else:
        flash('Please upload a valid .txt file', 'error')
        
    return redirect(url_for('index'))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)), debug=True)
