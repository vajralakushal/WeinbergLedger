import io
import sqlite3
import requests as req
from pathlib import Path

from flask import Flask, jsonify, request, send_file
from flask_cors import CORS
from db import search, extract_identifers, set_borrower

app = Flask(__name__)
CORS(app)

IMG_DIR = Path("img")

# isolation_level=None = autocommit; we manage write transactions explicitly
# with BEGIN IMMEDIATE so we never hit SQLITE_BUSY_SNAPSHOT in WAL mode.
con = sqlite3.connect(
    "library.db",
    check_same_thread=False,
    timeout=30,
    isolation_level=None,
)
con.execute("PRAGMA journal_mode=WAL;")


@app.route("/api/search")
def search_endpoint():
    query = request.args.get("q", "").strip()
    if not query:
        return jsonify([])
    cur = con.cursor()
    rows = search(query, cur)
    columns = [d[0] for d in cur.description]
    return jsonify([dict(zip(columns, row)) for row in rows])


@app.route("/api/book/<int:book_id>/thumbnail")
def thumbnail(book_id):
    img_path = IMG_DIR / f"{book_id}.jpg"
    if img_path.exists():
        return send_file(img_path.resolve(), mimetype="image/jpeg")

    cur = con.cursor()
    identifiers = extract_identifers(book_id, cur)
    if "Error" in identifiers:
        return "", 404

    key_map = [("LC", "lccn"), ("ISBN", "isbn"), ("OCLC", "oclc")]
    for db_key, ol_key in key_map:
        for entry in identifiers.get(db_key, []):
            value = entry.get("value", "").strip()
            if not value:
                continue
            url = f"https://covers.openlibrary.org/b/{ol_key}/{value}-M.jpg?default=false"
            try:
                resp = req.get(url, timeout=6)
                if resp.status_code == 200 and "image" in resp.headers.get("content-type", ""):
                    IMG_DIR.mkdir(exist_ok=True)
                    img_path.write_bytes(resp.content)
                    return send_file(io.BytesIO(resp.content), mimetype="image/jpeg")
            except Exception:
                continue

    return "", 404


@app.route("/api/book/<int:book_id>/borrower", methods=["PATCH"])
def update_borrower(book_id):
    data = request.get_json(silent=True) or {}
    name = data.get("name", "").strip()
    cur = con.cursor()
    try:
        con.execute("BEGIN IMMEDIATE")
        set_borrower(name, book_id, cur)
        con.execute("COMMIT")
    except sqlite3.OperationalError as e:
        try:
            con.execute("ROLLBACK")
        except Exception:
            pass
        if "locked" in str(e).lower():
            return jsonify({"ok": False, "error": "Database is locked by another process (close the Jupyter notebook connection and retry)."}), 504
        raise
    return jsonify({"ok": True})


if __name__ == "__main__":
    app.run(port=5004, debug=True, use_reloader=False)
