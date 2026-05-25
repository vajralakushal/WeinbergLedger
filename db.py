import sqlite3
from typing import Any, Dict


SCHEMA = """
CREATE TABLE IF NOT EXISTS LIBRARY (
    ID INTEGER PRIMARY KEY,
    OWNER INTEGER NOT NULL,
    BORROWER TEXT,
    LOCATION TEXT,
    TITLE TEXT NOT NULL,
    CREATOR TEXT,
    PUBLISHER TEXT,
    SERIES TEXT,
    SUBJECT TEXT,
    CREATION_DATE TEXT,
    IDENTIFIER TEXT
);
"""

def connect(db_path: str):
    con = sqlite3.connect(db_path, check_same_thread=False)
    con.execute("PRAGMA journal_mode=WAL;")
    return con

def init_db(con):
    cur = con.cursor()
    for stmt in SCHEMA.strip().split(";"):
        s = stmt.strip()
        if s:
            cur.execute(s)
    con.commit()

def search(search_text, cursor):
    search_pattern = f"%{search_text}%"
    cursor.execute(
    f"""
    SELECT *
    FROM LIBRARY
    WHERE
        TITLE LIKE :placeholder OR
        CREATOR LIKE :placeholder OR
        PUBLISHER LIKE :placeholder OR
        SERIES LIKE :placeholder OR
        SUBJECT LIKE :placeholder OR
        CREATION_DATE LIKE :placeholder OR
        IDENTIFIER LIKE :placeholder
    """, {"placeholder": search_pattern})
    return cursor.fetchall()