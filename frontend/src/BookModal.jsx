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
  { key: "BORROWER",      label: "Borrower", editable: true },
  { key: "LOCATION",      label: "Location" },
  { key: "IDENTIFIER",    label: "Identifier" },
  { key: "ID",            label: "ID" },
];

export default function BookModal({ book, onClose, onBorrowerUpdate }) {
  const [thumbnailSrc, setThumbnailSrc] = useState(null); // null=loading, false=none, string=url
  const [isEditing, setIsEditing]       = useState(false);
  const [borrower, setBorrower]         = useState(book.BORROWER ?? "");
  const [borrowerError, setBorrowerError] = useState(null);
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

  // Focus input on edit start
  useEffect(() => {
    if (isEditing) inputRef.current?.focus();
  }, [isEditing]);

  // Escape to close
  useEffect(() => {
    const handler = (e) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [onClose]);

  const commitBorrower = useCallback(async () => {
    if (!isEditing) return;
    setIsEditing(false);
    setBorrowerError(null);
    try {
      const res = await fetch(`http://localhost:5004/api/book/${book.ID}/borrower`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: borrower }),
      });
      const data = await res.json();
      if (!data.ok) {
        setBorrowerError(data.error ?? "Save failed.");
        return;
      }
      onBorrowerUpdate(book.ID, borrower);
    } catch {
      setBorrowerError("Could not reach server.");
    }
  }, [isEditing, book.ID, borrower, onBorrowerUpdate]);

  const handleBorrowerKey = (e) => {
    if (e.key === "Enter") commitBorrower();
    if (e.key === "Escape") {
      setBorrower(book.BORROWER ?? "");
      setIsEditing(false);
    }
  };

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
            {FIELDS.map(({ key, label, editable }) => {
              const value = key === "BORROWER" ? borrower : (book[key] ?? "");
              return (
                <tr key={key}>
                  <th>{label}</th>
                  <td>
                    {editable && isEditing ? (
                      <input
                        ref={inputRef}
                        className="borrower-input"
                        value={borrower}
                        onChange={(e) => setBorrower(e.target.value)}
                        onKeyDown={handleBorrowerKey}
                        onBlur={commitBorrower}
                      />
                    ) : editable ? (
                      <>
                        <span
                          className="borrower-display"
                          onClick={() => { setIsEditing(true); setBorrowerError(null); }}
                          title="Click to edit"
                        >
                          {value || <em className="modal-empty">—</em>}
                        </span>
                        {borrowerError && (
                          <span className="borrower-error"> {borrowerError}</span>
                        )}
                      </>
                    ) : (
                      value || <em className="modal-empty">—</em>
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
