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