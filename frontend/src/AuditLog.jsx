import { useState, useEffect, useMemo } from "react";
import "./AuditLog.css";

function formatTs(iso) {
  if (!iso) return "";
  const d = new Date(iso);
  return isNaN(d) ? iso : d.toLocaleString();
}

export default function AuditLog({ onBack }) {
  const [rows, setRows]                 = useState(null);
  const [error, setError]               = useState(null);
  const [editorFilter, setEditorFilter] = useState("");
  const [q, setQ]                       = useState("");

  useEffect(() => {
    fetch("/api/audit")
      .then((res) => {
        if (!res.ok) throw new Error(`Server error ${res.status}`);
        return res.json();
      })
      .then(setRows)
      .catch((e) => setError(e.message));
  }, []);

  const editors = useMemo(
    () => (rows ? [...new Set(rows.map((r) => r.EDITOR).filter(Boolean))].sort() : []),
    [rows]
  );

  const filtered = useMemo(() => {
    if (!rows) return [];
    const needle = q.trim().toLowerCase();
    return rows.filter((r) => {
      if (editorFilter && r.EDITOR !== editorFilter) return false;
      if (!needle) return true;
      return [r.BOOK_TITLE, r.OLD_VALUE, r.NEW_VALUE, r.IP, r.FIELD, String(r.BOOK_ID)]
        .some((v) => (v ?? "").toString().toLowerCase().includes(needle));
    });
  }, [rows, editorFilter, q]);

  return (
    <div className="audit-card">
      <div className="audit-header">
        <button className="audit-back" onClick={onBack}>← Back to search</button>
        <h1 className="title">Audit Log</h1>
      </div>

      {error && <p className="status error">Error: {error}</p>}
      {!rows && !error && <p className="status">Loading…</p>}

      {rows && rows.length === 0 && (
        <p className="status">No edits have been recorded yet.</p>
      )}

      {rows && rows.length > 0 && (
        <>
          <div className="audit-controls">
            <select value={editorFilter} onChange={(e) => setEditorFilter(e.target.value)}>
              <option value="">All people ({editors.length})</option>
              {editors.map((name) => (
                <option key={name} value={name}>{name}</option>
              ))}
            </select>
            <input
              type="text"
              placeholder="Filter by book, value, IP…"
              value={q}
              onChange={(e) => setQ(e.target.value)}
            />
            <span className="audit-count">
              {filtered.length} of {rows.length} entr{rows.length !== 1 ? "ies" : "y"}
            </span>
          </div>

          {filtered.length === 0 ? (
            <p className="status">No matching entries.</p>
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>When</th>
                    <th>Who</th>
                    <th>IP</th>
                    <th>Book</th>
                    <th>Field</th>
                    <th>From</th>
                    <th>To</th>
                  </tr>
                </thead>
                <tbody>
                  {filtered.map((r, i) => (
                    <tr key={i}>
                      <td className="nowrap">{formatTs(r.TIMESTAMP)}</td>
                      <td>{r.EDITOR}</td>
                      <td className="nowrap">{r.IP ?? "?"}</td>
                      <td>
                        {r.BOOK_TITLE ?? <em className="muted">(deleted)</em>}{" "}
                        <span className="muted">#{r.BOOK_ID}</span>
                      </td>
                      <td>{r.FIELD?.toLowerCase()}</td>
                      <td>{r.OLD_VALUE ?? <em className="muted">—</em>}</td>
                      <td>{r.NEW_VALUE ?? <em className="muted">—</em>}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}
    </div>
  );
}
