import { useState, useEffect, useRef } from "react";
import "./UserMenu.css";

export default function UserMenu({ user, onLogout, onChangePassword, onOpenAdmin }) {
  const [open, setOpen] = useState(false);
  const ref = useRef(null);

  // Close on outside click.
  useEffect(() => {
    if (!open) return;
    const handler = (e) => {
      if (ref.current && !ref.current.contains(e.target)) setOpen(false);
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [open]);

  // Close on Escape.
  useEffect(() => {
    if (!open) return;
    const handler = (e) => { if (e.key === "Escape") setOpen(false); };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [open]);

  return (
    <div className="user-menu" ref={ref}>
      <button
        type="button"
        className="nav-btn user-menu-trigger"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
      >
        {user.username} <span className="user-menu-caret" aria-hidden="true">▾</span>
      </button>

      {open && (
        <div className="user-menu-dropdown" role="menu">
          <button
            type="button"
            className="user-menu-item"
            role="menuitem"
            onClick={() => { setOpen(false); onChangePassword(); }}
          >
            Change password
          </button>
          {user.admin_status && (
            <button
              type="button"
              className="user-menu-item"
              role="menuitem"
              onClick={() => { setOpen(false); onOpenAdmin(); }}
            >
              Users Dashboard
            </button>
          )}
          <button
            type="button"
            className="user-menu-item"
            role="menuitem"
            onClick={() => { setOpen(false); onLogout(); }}
          >
            Log Out
          </button>
        </div>
      )}
    </div>
  );
}
