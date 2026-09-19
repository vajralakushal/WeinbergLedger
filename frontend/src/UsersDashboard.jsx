import { useState, useEffect, useCallback } from "react";
import "./AuditLog.css";
import "./UsersDashboard.css";
import { authHeaders } from "./api";

export default function UsersDashboard({ onBack, authToken }) {
  const [rows, setRows]               = useState(null);
  const [error, setError]             = useState(null);
  const [statusFilter, setStatusFilter] = useState("");
  const [actionError, setActionError] = useState(null);
  const [tempPassword, setTempPassword] = useState(null); // { userId, password }

  const load = useCallback(() => {
    const qs = statusFilter ? `?approval_status=${encodeURIComponent(statusFilter)}` : "";
    fetch(`/api/admin/users${qs}`, { headers: authHeaders(authToken) })
      .then((res) => {
        if (!res.ok) throw new Error(`Server error ${res.status}`);
        return res.json();
      })
      .then(setRows)
      .catch((e) => setError(e.message));
  }, [authToken, statusFilter]);

  useEffect(() => { load(); }, [load]);

  const act = useCallback(async (userId, path, method = "PATCH", body) => {
    setActionError(null);
    try {
      const res = await fetch(`/api/admin/users/${userId}${path}`, {
        method,
        headers: { "Content-Type": "application/json", ...authHeaders(authToken) },
        body: body ? JSON.stringify(body) : undefined,
      });
      const data = await res.json();
      if (!data.ok) {
        setActionError(data.error ?? "Action failed.");
        return null;
      }
      return data;
    } catch {
      setActionError("Could not reach server.");
      return null;
    }
  }, [authToken]);

  const approve = async (userId) => {
    if (await act(userId, "/approve")) load();
  };

  const deny = async (userId) => {
    if (!window.confirm("Deny and remove this registration?")) return;
    if (await act(userId, "", "DELETE")) load();
  };

  const removeUser = async (userId) => {
    if (!window.confirm("Delete this user? This cannot be undone.")) return;
    const reassignTo = window.prompt(
      "Optionally reassign this user's books to another name before deleting (leave blank to skip):",
      ""
    );
    const body = reassignTo?.trim() ? { reassign_books_to: reassignTo.trim() } : undefined;
    if (await act(userId, "", "DELETE", body)) load();
  };

  const resetPassword = async (userId) => {
    const data = await act(userId, "/reset_password");
    if (data) setTempPassword({ userId, password: data.temp_password });
  };

  const makeAdmin = async (userId) => {
    if (!window.confirm("Make this user an admin?")) return;
    if (await act(userId, "/make_admin")) load();
  };

  return (
    <div className="audit-card">
      <div className="audit-header">
        <button className="audit-back" onClick={onBack}>← Back to search</button>
        <h1 className="title">Users Dashboard</h1>
      </div>

      <div className="audit-controls">
        <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
          <option value="">All statuses</option>
          <option value="PENDING">Pending</option>
          <option value="APPROVED">Approved</option>
          <option value="DENIED">Denied</option>
        </select>
      </div>

      {error && <p className="status error">Error: {error}</p>}
      {actionError && <p className="status error">{actionError}</p>}
      {tempPassword && (
        <p className="status users-temp-password">
          New password for user #{tempPassword.userId}: <strong>{tempPassword.password}</strong>{" "}
          <button className="footer-link" onClick={() => setTempPassword(null)}>dismiss</button>
        </p>
      )}

      {!rows && !error && <p className="status">Loading…</p>}
      {rows && rows.length === 0 && <p className="status">No users found.</p>}

      {rows && rows.length > 0 && (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>ID</th>
                <th>Name</th>
                <th>Username</th>
                <th>Status</th>
                <th>Admin</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((u) => (
                <tr key={u.user_id}>
                  <td>{u.user_id}</td>
                  <td>{u.first_name} {u.last_name}</td>
                  <td>{u.username}</td>
                  <td>{u.approval_status}</td>
                  <td>{u.admin_status ? "Yes" : "No"}</td>
                  <td>
                    <div className="users-actions">
                      {u.approval_status === "PENDING" && (
                        <>
                          <button className="users-action-btn" onClick={() => approve(u.user_id)}>Approve</button>
                          <button className="users-action-btn" onClick={() => deny(u.user_id)}>Deny</button>
                        </>
                      )}
                      <button className="users-action-btn" onClick={() => resetPassword(u.user_id)}>
                        Reset password
                      </button>
                      {!u.admin_status && (
                        <button className="users-action-btn" onClick={() => makeAdmin(u.user_id)}>
                          Make admin
                        </button>
                      )}
                      <button className="users-action-btn users-action-danger" onClick={() => removeUser(u.user_id)}>
                        Delete
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
