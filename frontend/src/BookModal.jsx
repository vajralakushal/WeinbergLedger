import { useState, useEffect, useRef, useCallback } from "react";
import "./BookModal.css";
import { ensureEditorName } from "./ensureName";

function formatTs(iso) {
  if (!iso) return "";
  const d = new Date(iso);
  return isNaN(d) ? iso : d.toLocaleString();
}

const FIELDS = [
  { key: "TITLE",         label: "Title" },
  { key: "CREATOR",       label: "Creator" },
  { key: "PUBLISHER",     label: "Publisher" },
  { key: "SERIES",        label: "Series" },
  { key: "SUBJECT",       label: "Subject" },
  { key: "CREATION_DATE", label: "Year" },
  { key: "OWNER",         label: "Owner" },
  { key: "BORROWER",      label: "Borrower", editable: true, endpoint: "borrower", payloadKey: "name" },
  { key: "LOCATION",      label: "Location", editable: true, endpoint: "location", payloadKey: "location" },
  { key: "IDENTIFIER",    label: "Identifier" },
  { key: "ID",            label: "ID" },
];

export default function BookModal({ book, onClose, onFieldUpdate, onRemove, editorName, onEditorNameChange }) {
  const [thumbnailSrc, setThumbnailSrc] = useState(null); // null=loading, false=none, string=url

  // Change history (audit trail) for this book, newest first.
  const [history, setHistory] = useState([]);

  // Error from a failed remove, if any.
  const [removeError, setRemoveError] = useState(null);

  // Which field key is currently open for editing (null = none)
  const [editingField, setEditingField] = useState(null);

  // Live values for editable fields while typing
  const [editValues, setEditValues] = useState({
    BORROWER: book.BORROWER ?? "",
    LOCATION: book.LOCATION ?? "",
  });

  // Per-field save errors
  const [editErrors, setEditErrors] = useState({});

  const inputRef = useRef(null);

  // Thumbnail fetch
  useEffect(() => {
    let cancelled = false;
    fetch(`/api/book/${book.ID}/thumbnail`)
      .then((res) => {
        if (!res.ok) throw new Error("no image");
        return res.blob();
      })
      .then((blob) => {
        if (!cancelled) setThumbnailSrc(URL.createObjectURL(blob));
      })
      .catch(() => {
        if (!cancelled) setThumbnailSrc(false);
      });
    return () => { cancelled = true; };
  }, [book.ID]);

  // Focus the input whenever a field becomes active
  useEffect(() => {
    if (editingField) inputRef.current?.focus();
  }, [editingField]);

  // Escape: cancel active edit first; close modal if none open
  useEffect(() => {
    const handler = (e) => {
      if (e.key !== "Escape") return;
      if (editingField) {
        setEditValues((prev) => ({ ...prev, [editingField]: book[editingField] ?? "" }));
        setEditingField(null);
      } else {
        onClose();
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [editingField, book, onClose]);

  // Load the audit trail for this book.
  const loadHistory = useCallback(() => {
    fetch(`/api/book/${book.ID}/history`)
      .then((res) => (res.ok ? res.json() : []))
      .then((data) => setHistory(Array.isArray(data) ? data : []))
      .catch(() => setHistory([]));
  }, [book.ID]);

  useEffect(() => { loadHistory(); }, [loadHistory]);

  // No name, no edit. Prompt for one and remember it for future edits.
  const startEditing = useCallback((fieldKey) => {
    const name = ensureEditorName(editorName, onEditorNameChange);
    if (!name) return; // cancelled or empty → do not open the editor
    setEditingField(fieldKey);
    setEditErrors((prev) => ({ ...prev, [fieldKey]: null }));
  }, [editorName, onEditorNameChange]);

  // Remove this book from the library (requires a name; confirmed first).
  const removeBook = useCallback(async () => {
    const name = ensureEditorName(editorName, onEditorNameChange);
    if (!name) return;
    if (!window.confirm(`Remove "${book.TITLE}" from the library? This cannot be undone.`)) return;

    setRemoveError(null);
    try {
      const res = await fetch(`/api/book/${book.ID}`, {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ editor: name }),
      });
      const data = await res.json();
      if (!data.ok) {
        setRemoveError(data.error ?? "Remove failed.");
        return;
      }
      onRemove?.(book.ID);
    } catch {
      setRemoveError("Could not reach server.");
    }
  }, [editorName, onEditorNameChange, book.ID, book.TITLE, onRemove]);

  const commitEdit = useCallback(async (fieldKey, endpoint, payloadKey) => {
    if (editingField !== fieldKey) return;
    setEditingField(null);
    const value = editValues[fieldKey];
    try {
      const res = await fetch(`/api/book/${book.ID}/${endpoint}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ [payloadKey]: value, editor: editorName }),
      });
      const data = await res.json();
      if (!data.ok) {
        setEditErrors((prev) => ({ ...prev, [fieldKey]: data.error ?? "Save failed." }));
        return;
      }
      onFieldUpdate(book.ID, fieldKey, value);
      loadHistory(); // reflect the edit we just made
    } catch {
      setEditErrors((prev) => ({ ...prev, [fieldKey]: "Could not reach server." }));
    }
  }, [editingField, editValues, book.ID, onFieldUpdate, editorName, loadHistory]);

  const cancelEdit = useCallback((fieldKey) => {
    setEditValues((prev) => ({ ...prev, [fieldKey]: book[fieldKey] ?? "" }));
    setEditingField(null);
  }, [book]);

  return (
    <div className="modal-overlay" onClick={(e) => e.target === e.currentTarget && onClose()}>
      <button className="modal-back-btn" onClick={onClose}>← Back</button>

      <div className="modal-card">
        {thumbnailSrc !== null && (
          <div className="modal-thumbnail-wrap">
            {thumbnailSrc ? (
              <img src={thumbnailSrc} alt="Book cover" className="modal-thumbnail" />
            ) : (
              <div className="modal-thumbnail-plate" aria-hidden="true">
                <span>No cover on file</span>
              </div>
            )}
          </div>
        )}

        <table className="modal-detail-table">
          <tbody>
            {FIELDS.map(({ key, label, editable, endpoint, payloadKey }) => {
              const displayValue = editable ? editValues[key] : (book[key] ?? "");
              const isActive     = editable && editingField === key;
              const fieldError   = editErrors[key];

              return (
                <tr key={key}>
                  <th>{label}</th>
                  <td>
                    {isActive ? (
                      <input
                        ref={inputRef}
                        className="editable-input"
                        value={editValues[key]}
                        onChange={(e) =>
                          setEditValues((prev) => ({ ...prev, [key]: e.target.value }))
                        }
                        onKeyDown={(e) => {
                          if (e.key === "Enter")  commitEdit(key, endpoint, payloadKey);
                          if (e.key === "Escape") cancelEdit(key);
                        }}
                        onBlur={() => commitEdit(key, endpoint, payloadKey)}
                      />
                    ) : editable ? (
                      <>
                        <span
                          className="editable-display"
                          onClick={() => startEditing(key)}
                          title="Click to edit"
                        >
                          {displayValue || <em className="modal-empty">—</em>}
                        </span>
                        {fieldError && (
                          <span className="edit-error">{fieldError}</span>
                        )}
                      </>
                    ) : (
                      displayValue || <em className="modal-empty">—</em>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>

        {history.length > 0 && (
          <div className="modal-history">
            <h3 className="modal-history-title">Change history</h3>
            <ul className="modal-history-list">
              {history.map((h, i) => (
                <li key={i} className="modal-history-item">
                  <span className="hist-main">
                    <strong>{h.EDITOR}</strong> set {h.FIELD?.toLowerCase()} to{" "}
                    {h.NEW_VALUE ? <em>&ldquo;{h.NEW_VALUE}&rdquo;</em> : <em>—</em>}
                  </span>
                  <span className="hist-meta">
                    {formatTs(h.TIMESTAMP)} · {h.IP ?? "?"}
                  </span>
                </li>
              ))}
            </ul>
          </div>
        )}

        <div className="modal-actions">
          <button className="remove-book-btn" onClick={removeBook}>
            🗑 Remove book
          </button>
          {removeError && <span className="edit-error">{removeError}</span>}
        </div>
      </div>
    </div>
  );
}
