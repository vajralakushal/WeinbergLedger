import sqlite3
from typing import Any, Dict
import re


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
    con = sqlite3.connect(db_path, check_same_thread=False, timeout=30)
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

def creator(libId, cursor):
    search_pattern = f"%{libId}%"
    cursor.execute("SELECT * FROM LIBRARY WHERE CREATOR LIKE ?", (search_pattern,))
    return cursor.fetchall()      

def search(search_text,cursor):

    list_of_sets = []
    
    token_list = str(search_text).split(" ")

    for formated in token_list:
        tmp = set([])    
        tmp.update(set(titleSearch(formated, cursor)))
        tmp.update(set(creator(formated, cursor)))
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

#Identifier Extractor
def extract_identifers(id: str, cursor) -> dict:
    """
    Extracts identifiers, if any, for the selected book.

    Args:
        id (str): The primary key for the database, unique to each book.
        cursor (int): The second number.

    Returns:
        dict: Different identifiers are the keys, and their values are lists for each qualifier for the corresponding identifier (if there are more than one)
    """
    book_id = int(f"{id}")
    result = {}
    cursor.execute("SELECT IDENTIFIER FROM LIBRARY WHERE ID = ?", (book_id,))
    tmp = cursor.fetchall()
    if len(tmp) == 0:
        return {"Error": "Book does not exist"}
    elif len(tmp) > 1:
        return {"Error": "Multiple IDs found error"}
    else:
        identifier_string = tmp[0][0] # cursor.fetchall returns a list of tuples. The tuple in question will contain just one element, which is a string of the different IDs.
        if not identifier_string or identifier_string == "" or len(identifier_string) < 3: #picking some arbitrary number just in case there are blanks. TODO: rewrite this.
            return {"Error": "No identifiers exist"}
        for entry in identifier_string.split("; "):
            entry = entry.strip()
            parts = entry.split(" : ", 1)
            if len(parts) != 2:
                continue

            id_type    = parts[0].strip()
            value_part = parts[1].strip()

            if id_type == "OCLC":
                value     = re.sub(r"^\(OCoLC\)(oc[a-z]+)?", "", value_part)
                record    = {"value": value}
            else:
                match = re.match(r"^(\S+)\s+(\(.+\))$", value_part)
                if match:
                    record = {"value": match.group(1), "qualifier": match.group(2)}
                else:
                    record = {"value": value_part}

            result.setdefault(id_type, []).append(record)

    return result

#Update Function
def set_borrower(borrower: str, id: str, cursor) -> str:
    borrower_name = f"{borrower}"
    book_id = int(f"{id}")
    cursor.execute("SELECT * FROM LIBRARY WHERE ID LIKE ?", (book_id,))
    tmp = cursor.fetchall()
    if len(tmp) == 0:
        return "Book does not exist"
    elif len(tmp) > 1:
        return "Multiple IDs found error"
    else:
        cursor.execute("UPDATE LIBRARY SET BORROWER = ? WHERE ID = ?", (borrower_name, book_id))
        return f"Successfully updated Borrower {borrower} into Library for book with {id} ID."

def set_location(location: str, id: str, cursor) -> str:
    location_name = f"{location}"
    book_id = int(f"{id}")
    cursor.execute("SELECT * FROM LIBRARY WHERE ID LIKE ?", (book_id,))
    tmp = cursor.fetchall()
    if len(tmp) == 0:
        return "Book does not exist"
    elif len(tmp) > 1:
        return "Multiple IDs found error"
    else:
        cursor.execute("UPDATE LIBRARY SET LOCATION = ? WHERE ID = ?", (location_name, book_id))
        return f"Successfully updated Location {location} into Library for book with {id} ID."

