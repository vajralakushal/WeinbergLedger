import { useState, useEffect } from "react";
import "./BookModal.css";
import "./AuthModal.css";
import { authHeaders } from "./api";

export default function ChangePasswordModal({ onClose, authToken }) {
  const [oldPassword, setOldPassword]         = useState("");
  const [newPassword, setNewPassword]         = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [error, setError]     = useState(null);
  const [success, setSuccess] = useState(false);
  const [saving, setSaving]   = useState(false);

  useEffect(() => {
    const handler = (e) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [onClose]);

  const submit = async (e) => {
    e.preventDefault();
    setError(null);
    if (newPassword !== confirmPassword) {
      setError("New passwords do not match.");
      return;
    }
    setSaving(true);
    try {
      const res = await fetch("/api/me/password", {
        method: "PATCH",
        headers: { "Content-Type": "application/json", ...authHeaders(authToken) },
        body: JSON.stringify({
          old_password: oldPassword,
          new_password: newPassword,
          new_password_confirmation: confirmPassword,
        }),
      });
      const data = await res.json();
      if (!data.ok) {
        setError(data.error ?? "Could not change password.");
        return;
      }
      setSuccess(true);
    } catch {
      setError("Could not reach server.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="modal-overlay auth-overlay" onClick={(e) => e.target === e.currentTarget && onClose()}>
      <button className="modal-back-btn" onClick={onClose}>← Back</button>

      <div className="modal-card auth-card">
        <h2 className="auth-title">Change Password</h2>

        {success ? (
          <>
            <p className="add-book-success">Your password has been changed.</p>
            <div className="add-book-actions">
              <button className="add-book-submit" onClick={onClose}>Done</button>
            </div>
          </>
        ) : (
          <form className="auth-form" onSubmit={submit}>
            <label className="add-book-field">
              <span className="add-book-label">Current password</span>
              <input
                className="add-book-input"
                type="password"
                value={oldPassword}
                onChange={(e) => setOldPassword(e.target.value)}
                autoFocus
              />
            </label>
            <label className="add-book-field">
              <span className="add-book-label">New password</span>
              <input
                className="add-book-input"
                type="password"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
              />
            </label>
            <label className="add-book-field">
              <span className="add-book-label">Confirm new password</span>
              <input
                className="add-book-input"
                type="password"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
              />
            </label>

            {error && <p className="status error">{error}</p>}

            <div className="add-book-actions">
              <button type="submit" className="add-book-submit" disabled={saving}>
                {saving ? "Saving…" : "Change Password"}
              </button>
              <button type="button" className="add-book-cancel" onClick={onClose}>Cancel</button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}
