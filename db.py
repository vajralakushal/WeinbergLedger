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

# Fetch Functions
def titleSearch(title, cursor):
    search_pattern = f"%{title}%"
    cursor.execute("SELECT * FROM LIBRARY WHERE TITLE LIKE ?", (search_pattern,))
    return cursor.fetchall()

def ownerSearch(owner, cursor):
    search_pattern = f"%{owner}%"
    cursor.execute("SELECT * FROM LIBRARY WHERE OWNER LIKE ?", (search_pattern,))
    return cursor.fetchall()

def locationSearch(location, cursor):
    search_pattern = f"%{location}%"
    cursor.execute("SELECT * FROM LIBRARY WHERE LOCATION LIKE ?", (search_pattern,))
    return cursor.fetchall()

def borrowerSearch(borrower, cursor):
    search_pattern = f"%{borrower}%"
    cursor.execute("SELECT * FROM LIBRARY WHERE BORROWER LIKE ?", (search_pattern,))
    return cursor.fetchall()

def publisherSearch(publisher, cursor):
    search_pattern = f"%{publisher}%"
    cursor.execute("SELECT * FROM LIBRARY WHERE PUBLISHER LIKE ?", (search_pattern,))
    return cursor.fetchall()

def seriesSearch(series, cursor):
    search_pattern = f"%{series}%"
    cursor.execute("SELECT * FROM LIBRARY WHERE SERIES LIKE ?", (search_pattern,))
    return cursor.fetchall()

def subjectSearch(subject, cursor):
    search_pattern = f"%{subject}%"
    cursor.execute("SELECT * FROM LIBRARY WHERE SUBJECT LIKE ?", (search_pattern,))
    return cursor.fetchall()

def creationDateSearch(creationDate, cursor):
    search_pattern = f"%{creationDate}%"
    cursor.execute("SELECT * FROM LIBRARY WHERE CREATION_DATE LIKE ?", (search_pattern,))
    return cursor.fetchall()

def libIdentifierSearch(libId, cursor):
    search_pattern = f"%{libId}%"
    cursor.execute("SELECT * FROM LIBRARY WHERE IDENTIFIER LIKE ?", (search_pattern,))
    return cursor.fetchall()    

def search(search_text,cursor):

    list_of_sets = []
    
    token_list = str(search_text).split(" ")

    for formated in token_list:
        tmp = set([])    
        tmp.update(set(titleSearch(formated, cursor)))
        tmp.update(set(ownerSearch(formated, cursor)))
        tmp.update(set(locationSearch(formated, cursor)))
        tmp.update(set(borrowerSearch(formated, cursor)))
        tmp.update(set(publisherSearch(formated, cursor)))
        tmp.update(set(seriesSearch(formated, cursor)))
        tmp.update(set(subjectSearch(formated, cursor)))
        tmp.update(set(creationDateSearch(formated, cursor)))
        tmp.update(set(libIdentifierSearch(formated, cursor)))
        list_of_sets.append(tmp)
    
    result = set.intersection(*list_of_sets)
    return result