FROM python:3.11-slim

WORKDIR /app

RUN pip install flask python-dotenv pyrogram tgcrypto

ENV PORT=8000
ENV BOT_TOKEN=""
ENV CHANNEL_ID=""

RUN mkdir -p uploads backups templates static

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

RUN mkdir -p templates && cat > templates/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <title>QuizVault — Upload Dashboard</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link href="https://fonts.googleapis.com/css2?family=Syne:wght@400;600;700;800&family=DM+Mono:wght@300;400;500&display=swap" rel="stylesheet">
    <style>
        *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
        :root {
            --bg: #060608;
            --surface: rgba(255,255,255,0.03);
            --surface-hover: rgba(255,255,255,0.06);
            --border: rgba(255,255,255,0.07);
            --border-glow: rgba(99,211,255,0.25);
            --accent: #63d3ff;
            --accent2: #a78bfa;
            --accent3: #f472b6;
            --text: #e8eaf0;
            --muted: #6b7280;
            --success: #34d399;
        }
        html { scroll-behavior: smooth; }
        body { background: var(--bg); color: var(--text); font-family: 'DM Mono', monospace; min-height: 100vh; overflow-x: hidden; }
        #canvas-bg { position: fixed; top: 0; left: 0; width: 100%; height: 100%; z-index: 0; pointer-events: none; }
        body::before { content: ''; position: fixed; inset: 0; background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='noise'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23noise)' opacity='0.04'/%3E%3C/svg%3E"); background-size: 200px; pointer-events: none; z-index: 1; opacity: 0.5; }
        .glow-orb { position: fixed; border-radius: 50%; filter: blur(120px); pointer-events: none; z-index: 0; animation: orbFloat 8s ease-in-out infinite; }
        .glow-orb-1 { width: 500px; height: 500px; top: -150px; left: -100px; background: rgba(99,211,255,0.06); animation-delay: 0s; }
        .glow-orb-2 { width: 400px; height: 400px; bottom: -100px; right: -80px; background: rgba(167,139,250,0.07); animation-delay: 3s; }
        .glow-orb-3 { width: 300px; height: 300px; top: 40%; left: 50%; background: rgba(244,114,182,0.04); animation-delay: 5s; }
        @keyframes orbFloat { 0%, 100% { transform: translateY(0px) scale(1); } 50% { transform: translateY(-30px) scale(1.05); } }
        .wrapper { position: relative; z-index: 2; max-width: 1100px; margin: 0 auto; padding: 0 24px 80px; }
        header { padding: 60px 0 50px; display: flex; align-items: flex-start; justify-content: space-between; flex-wrap: wrap; gap: 20px; animation: fadeSlideDown 0.8s cubic-bezier(0.16, 1, 0.3, 1) both; }
        @keyframes fadeSlideDown { from { opacity: 0; transform: translateY(-24px); } to { opacity: 1; transform: translateY(0); } }
        .logo-block { display: flex; flex-direction: column; gap: 8px; }
        .logo-eyebrow { font-size: 11px; letter-spacing: 0.2em; text-transform: uppercase; color: var(--accent); display: flex; align-items: center; gap: 8px; }
        .logo-eyebrow::before { content: ''; display: block; width: 20px; height: 1px; background: var(--accent); opacity: 0.6; }
        h1 { font-family: 'Syne', sans-serif; font-size: clamp(36px, 6vw, 64px); font-weight: 800; letter-spacing: -0.03em; line-height: 1; background: linear-gradient(135deg, #ffffff 0%, var(--accent) 50%, var(--accent2) 100%); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }
        .stat-pills { display: flex; gap: 12px; flex-wrap: wrap; align-items: center; }
        .stat-pill { background: var(--surface); border: 1px solid var(--border); border-radius: 100px; padding: 8px 16px; font-size: 12px; color: var(--muted); display: flex; align-items: center; gap: 6px; transition: all 0.3s; }
        .stat-pill:hover { border-color: var(--border-glow); color: var(--accent); }
        .stat-pill .dot { width: 6px; height: 6px; border-radius: 50%; background: var(--accent); animation: pulse 2s infinite; }
        @keyframes pulse { 0%, 100% { opacity: 1; transform: scale(1); } 50% { opacity: 0.4; transform: scale(0.8); } }
        .main-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 20px; }
        @media (max-width: 700px) { .main-grid { grid-template-columns: 1fr; } }
        .card { background: var(--surface); border: 1px solid var(--border); border-radius: 24px; padding: 32px; position: relative; overflow: hidden; transition: border-color 0.4s, transform 0.4s, box-shadow 0.4s; animation: cardIn 0.6s cubic-bezier(0.16, 1, 0.3, 1) both; }
        @keyframes cardIn { from { opacity: 0; transform: translateY(32px); } to { opacity: 1; transform: translateY(0); } }
        .card:nth-child(1) { animation-delay: 0.1s; }
        .card:nth-child(2) { animation-delay: 0.2s; }
        .card::before { content: ''; position: absolute; inset: 0; background: radial-gradient(circle at var(--mx, 50%) var(--my, 50%), rgba(99,211,255,0.04) 0%, transparent 60%); opacity: 0; transition: opacity 0.4s; pointer-events: none; }
        .card:hover::before { opacity: 1; }
        .card:hover { border-color: var(--border-glow); transform: translateY(-3px); box-shadow: 0 24px 60px rgba(99,211,255,0.05); }
        .card-label { font-size: 10px; letter-spacing: 0.18em; text-transform: uppercase; color: var(--accent); margin-bottom: 20px; display: flex; align-items: center; gap: 8px; }
        .card-label svg { width: 14px; height: 14px; }
        .card h2 { font-family: 'Syne', sans-serif; font-size: 22px; font-weight: 700; margin-bottom: 24px; color: #fff; }
        .upload-zone { border: 2px dashed var(--border); border-radius: 16px; padding: 40px 20px; text-align: center; cursor: pointer; transition: all 0.4s; position: relative; overflow: hidden; }
        .upload-zone::after { content: ''; position: absolute; inset: 0; background: linear-gradient(135deg, rgba(99,211,255,0.03), rgba(167,139,250,0.03)); opacity: 0; transition: opacity 0.4s; }
        .upload-zone:hover, .upload-zone.dragging { border-color: var(--accent); background: rgba(99,211,255,0.04); transform: scale(1.01); }
        .upload-zone:hover::after, .upload-zone.dragging::after { opacity: 1; }
        .upload-icon { width: 56px; height: 56px; border-radius: 16px; background: linear-gradient(135deg, rgba(99,211,255,0.15), rgba(167,139,250,0.15)); display: flex; align-items: center; justify-content: center; margin: 0 auto 16px; transition: transform 0.4s; }
        .upload-zone:hover .upload-icon { transform: scale(1.1) rotate(-5deg); }
        .upload-icon svg { width: 24px; height: 24px; color: var(--accent); }
        .upload-zone input[type="file"] { position: absolute; inset: 0; opacity: 0; cursor: pointer; width: 100%; }
        .upload-text { font-size: 14px; color: var(--muted); margin-bottom: 6px; }
        .upload-text strong { color: var(--accent); }
        .upload-sub { font-size: 11px; color: var(--muted); opacity: 0.6; }
        .file-selected { display: none; align-items: center; gap: 12px; background: rgba(52,211,153,0.08); border: 1px solid rgba(52,211,153,0.2); border-radius: 12px; padding: 12px 16px; margin-top: 16px; font-size: 13px; color: var(--success); animation: slideIn 0.3s ease; }
        .file-selected.show { display: flex; }
        @keyframes slideIn { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: translateY(0); } }
        .btn-upload { width: 100%; margin-top: 20px; padding: 16px; border: none; border-radius: 14px; background: linear-gradient(135deg, var(--accent), var(--accent2)); color: #000; font-family: 'Syne', sans-serif; font-weight: 700; font-size: 15px; letter-spacing: 0.02em; cursor: pointer; position: relative; overflow: hidden; transition: transform 0.3s, box-shadow 0.3s; }
        .btn-upload::before { content: ''; position: absolute; top: 0; left: -100%; width: 100%; height: 100%; background: linear-gradient(90deg, transparent, rgba(255,255,255,0.2), transparent); transition: left 0.5s; }
        .btn-upload:hover::before { left: 100%; }
        .btn-upload:hover { transform: translateY(-2px); box-shadow: 0 12px 40px rgba(99,211,255,0.3); }
        .btn-upload:active { transform: translateY(0); }
        .code-block { background: rgba(0,0,0,0.4); border: 1px solid var(--border); border-radius: 14px; padding: 20px; font-size: 12px; line-height: 1.8; color: #8892b0; overflow-x: auto; position: relative; }
        .code-block::before { content: 'TXT'; position: absolute; top: 12px; right: 14px; font-size: 10px; letter-spacing: 0.1em; color: var(--accent); opacity: 0.5; }
        .code-key { color: #a78bfa; }
        .code-val { color: #63d3ff; }
        .code-q { color: #f472b6; }
        .code-ans { color: #34d399; }
        .section-header { display: flex; align-items: center; gap: 16px; margin: 48px 0 24px; animation: fadeIn 0.6s 0.4s ease both; }
        @keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
        .section-header h2 { font-family: 'Syne', sans-serif; font-size: 20px; font-weight: 700; white-space: nowrap; }
        .section-line { flex: 1; height: 1px; background: linear-gradient(90deg, var(--border), transparent); }
        .section-count { font-size: 11px; color: var(--muted); background: var(--surface); border: 1px solid var(--border); padding: 4px 10px; border-radius: 100px; }
        .quiz-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: 16px; }
        .quiz-card { background: var(--surface); border: 1px solid var(--border); border-radius: 20px; padding: 24px; position: relative; overflow: hidden; cursor: pointer; transition: all 0.4s cubic-bezier(0.16, 1, 0.3, 1); animation: cardIn 0.5s ease both; }
        .quiz-card::after { content: ''; position: absolute; top: 0; left: 0; right: 0; height: 2px; background: linear-gradient(90deg, var(--accent), var(--accent2), var(--accent3)); transform: scaleX(0); transform-origin: left; transition: transform 0.4s ease; }
        .quiz-card:hover::after { transform: scaleX(1); }
        .quiz-card:hover { border-color: var(--border-glow); transform: translateY(-4px); box-shadow: 0 20px 50px rgba(0,0,0,0.3); }
        .quiz-card-top { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 16px; }
        .quiz-num { font-size: 11px; color: var(--accent); font-weight: 500; opacity: 0.6; }
        .quiz-indicator { width: 8px; height: 8px; border-radius: 50%; background: var(--success); box-shadow: 0 0 8px var(--success); animation: pulse 3s infinite; }
        .quiz-title { font-family: 'Syne', sans-serif; font-size: 18px; font-weight: 700; color: #fff; margin-bottom: 14px; line-height: 1.2; }
        .quiz-tags { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 18px; }
        .tag { font-size: 10px; letter-spacing: 0.05em; padding: 5px 10px; border-radius: 100px; font-weight: 500; transition: all 0.3s; }
        .tag-class { background: rgba(99,211,255,0.1); color: #63d3ff; border: 1px solid rgba(99,211,255,0.2); }
        .tag-subject { background: rgba(167,139,250,0.1); color: #a78bfa; border: 1px solid rgba(167,139,250,0.2); }
        .tag-chapter { background: rgba(244,114,182,0.1); color: #f472b6; border: 1px solid rgba(244,114,182,0.2); }
        .tag-type { background: rgba(52,211,153,0.1); color: #34d399; border: 1px solid rgba(52,211,153,0.2); }
        .expand-btn { width: 100%; background: transparent; border: 1px solid var(--border); border-radius: 10px; padding: 10px; color: var(--muted); font-family: 'DM Mono', monospace; font-size: 11px; cursor: pointer; transition: all 0.3s; display: flex; align-items: center; justify-content: center; gap: 8px; }
        .expand-btn:hover { border-color: var(--accent); color: var(--accent); background: rgba(99,211,255,0.05); }
        .expand-btn svg { transition: transform 0.3s; }
        .expand-btn.open svg { transform: rotate(180deg); }
        .quiz-content { display: none; margin-top: 14px; background: rgba(0,0,0,0.3); border: 1px solid var(--border); border-radius: 12px; padding: 16px; font-size: 11px; line-height: 1.9; color: var(--muted); white-space: pre-wrap; max-height: 280px; overflow-y: auto; animation: expandDown 0.3s ease; }
        @keyframes expandDown { from { opacity: 0; transform: translateY(-8px); } to { opacity: 1; transform: translateY(0); } }
        .quiz-content::-webkit-scrollbar { width: 4px; }
        .quiz-content::-webkit-scrollbar-thumb { background: var(--border-glow); border-radius: 4px; }
        .empty-state { text-align: center; padding: 80px 20px; animation: fadeIn 0.6s 0.5s ease both; }
        .empty-icon { width: 80px; height: 80px; border-radius: 24px; background: var(--surface); border: 1px solid var(--border); display: flex; align-items: center; justify-content: center; margin: 0 auto 20px; }
        .empty-icon svg { width: 36px; height: 36px; color: var(--muted); opacity: 0.4; }
        .empty-state h3 { font-family: 'Syne', sans-serif; font-size: 18px; color: var(--muted); margin-bottom: 8px; }
        .empty-state p { font-size: 13px; color: var(--muted); opacity: 0.5; }
        .toast { position: fixed; bottom: 32px; left: 50%; transform: translateX(-50%) translateY(80px); background: var(--success); color: #000; padding: 14px 24px; border-radius: 100px; font-size: 13px; font-weight: 600; font-family: 'Syne', sans-serif; z-index: 1000; transition: transform 0.4s cubic-bezier(0.16, 1, 0.3, 1); display: flex; align-items: center; gap: 8px; }
        .toast.show { transform: translateX(-50%) translateY(0); }
        ::-webkit-scrollbar { width: 6px; }
        ::-webkit-scrollbar-track { background: var(--bg); }
        ::-webkit-scrollbar-thumb { background: var(--border); border-radius: 3px; }
    </style>
</head>
<body>
<canvas id="canvas-bg"></canvas>
<div class="glow-orb glow-orb-1"></div>
<div class="glow-orb glow-orb-2"></div>
<div class="glow-orb glow-orb-3"></div>
<div class="toast" id="toast">
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
    Quiz uploaded successfully!
</div>
<div class="wrapper">
    <header>
        <div class="logo-block">
            <div class="logo-eyebrow">Dashboard v1.0</div>
            <h1>QuizVault</h1>
        </div>
        <div class="stat-pills">
            <div class="stat-pill"><span class="dot"></span>System Online</div>
            <div class="stat-pill">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
                <span id="quiz-count">0</span> Quizzes
            </div>
        </div>
    </header>
    <div class="main-grid">
        <div class="card">
            <div class="card-label">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>
                Upload
            </div>
            <h2>Add New Quiz</h2>
            <form action="/upload" method="POST" enctype="multipart/form-data" id="upload-form">
                <div class="upload-zone" id="drop-zone">
                    <input type="file" name="file" accept=".txt" required id="file-input">
                    <div class="upload-icon">
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="12" y1="18" x2="12" y2="12"/><line x1="9" y1="15" x2="15" y2="15"/></svg>
                    </div>
                    <p class="upload-text"><strong>Click to browse</strong> or drag and drop</p>
                    <p class="upload-sub">Accepts .txt quiz files only</p>
                </div>
                <div class="file-selected" id="file-selected">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"/></svg>
                    <span id="file-name">file.txt</span>
  
