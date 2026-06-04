import { useState, useEffect, useRef, useCallback } from "react";
import "./BookModal.css";

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

export default function BookModal({ book, onClose, onFieldUpdate }) {
  const [thumbnailSrc, setThumbnailSrc] = useState(null); // null=loading, false=none, string=url

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
    fetch(`http://localhost:5004/api/book/${book.ID}/thumbnail`)
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

  const startEditing = useCallback((fieldKey) => {
    setEditingField(fieldKey);
    setEditErrors((prev) => ({ ...prev, [fieldKey]: null }));
  }, []);

  const commitEdit = useCallback(async (fieldKey, endpoint, payloadKey) => {
    if (editingField !== fieldKey) return;
    setEditingField(null);
    const value = editValues[fieldKey];
    try {
      const res = await fetch(`http://localhost:5004/api/book/${book.ID}/${endpoint}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ [payloadKey]: value }),
      });
      const data = await res.json();
      if (!data.ok) {
        setEditErrors((prev) => ({ ...prev, [fieldKey]: data.error ?? "Save failed." }));
        return;
      }
      onFieldUpdate(book.ID, fieldKey, value);
    } catch {
      setEditErrors((prev) => ({ ...prev, [fieldKey]: "Could not reach server." }));
    }
  }, [editingField, editValues, book.ID, onFieldUpdate]);

  const cancelEdit = useCallback((fieldKey) => {
    setEditValues((prev) => ({ ...prev, [fieldKey]: book[fieldKey] ?? "" }));
    setEditingField(null);
  }, [book]);

  return (
    <div className="modal-overlay" onClick={(e) => e.target === e.currentTarget && onClose()}>
      <button className="modal-back-btn" onClick={onClose}>← Back</button>

      <div className="modal-card">
        {thumbnailSrc && (
          <div className="modal-thumbnail-wrap">
            <img src={thumbnailSrc} alt="Book cover" className="modal-thumbnail" />
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
      </div>
    </div>
  );
}
