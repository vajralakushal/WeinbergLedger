import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi } from "vitest";
import UserMenu from "./UserMenu";

const REGULAR = { username: "ada", admin_status: false };
const ADMIN   = { username: "grace", admin_status: true };

describe("UserMenu", () => {
  it("shows the username and toggles the dropdown", async () => {
    render(<UserMenu user={REGULAR} onLogout={() => {}} onChangePassword={() => {}} onOpenAdmin={() => {}} />);
    expect(screen.getByRole("button", { name: /ada/ })).toBeInTheDocument();
    expect(screen.queryByText("Log Out")).toBeNull();

    await userEvent.click(screen.getByRole("button", { name: /ada/ }));
    expect(screen.getByText("Log Out")).toBeInTheDocument();
    expect(screen.getByText("Change password")).toBeInTheDocument();
  });

  it("hides Users Dashboard for non-admins", async () => {
    render(<UserMenu user={REGULAR} onLogout={() => {}} onChangePassword={() => {}} onOpenAdmin={() => {}} />);
    await userEvent.click(screen.getByRole("button", { name: /ada/ }));
    expect(screen.queryByText("Users Dashboard")).toBeNull();
  });

  it("shows Users Dashboard for admins", async () => {
    render(<UserMenu user={ADMIN} onLogout={() => {}} onChangePassword={() => {}} onOpenAdmin={() => {}} />);
    await userEvent.click(screen.getByRole("button", { name: /grace/ }));
    expect(screen.getByText("Users Dashboard")).toBeInTheDocument();
  });

  it("calls onLogout and closes the menu", async () => {
    const onLogout = vi.fn();
    render(<UserMenu user={REGULAR} onLogout={onLogout} onChangePassword={() => {}} onOpenAdmin={() => {}} />);
    await userEvent.click(screen.getByRole("button", { name: /ada/ }));
    await userEvent.click(screen.getByText("Log Out"));

    expect(onLogout).toHaveBeenCalled();
    expect(screen.queryByText("Log Out")).toBeNull();
  });

  it("closes when clicking outside the menu", async () => {
    render(
      <div>
        <UserMenu user={REGULAR} onLogout={() => {}} onChangePassword={() => {}} onOpenAdmin={() => {}} />
        <button>outside</button>
      </div>
    );
    await userEvent.click(screen.getByRole("button", { name: /ada/ }));
    expect(screen.getByText("Log Out")).toBeInTheDocument();

    await userEvent.click(screen.getByText("outside"));
    expect(screen.queryByText("Log Out")).toBeNull();
  });
});
