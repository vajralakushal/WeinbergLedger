from flask import Flask, jsonify, request
from flask_cors import CORS
from db import connect, search

app = Flask(__name__)
CORS(app)

con = connect("library.db")

@app.route("/api/search")
def search_endpoint():
    query = request.args.get("q", "").strip()
    if not query:
        return jsonify([])
    cur = con.cursor()
    rows = search(query, cur)
    con.close()
    columns = [d[0] for d in cur.description]
    return jsonify([dict(zip(columns, row)) for row in rows])

if __name__ == "__main__":
    app.run(port=5003, debug=True)
