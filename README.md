# The Weinberg Theory Group Ledger

This is a shared library catalog for the Weinberg theory group. It tracks which
books the group owns, who currently has each one checked out, and where it
lives on the shelf. Every change is logged with who made it, when, and from
where.

Anyone can browse the catalog and the change history without an account. You
need an account to add, remove, or edit a book.

## What it does

- Search the catalog by title, author, owner, publisher, subject, or any
  other field. You can also narrow a search to just one or two fields.
- Check books in and out by editing the Borrower field, or update where a
  book lives on the shelf.
- Add a book one at a time. You can type in an ISBN, LCCN, or OCLC number
  and it will look up the details online and fill in the form for you.
- Add books in bulk from a CSV file. Rows with no ISBN or LC on file get
  looked up online automatically. If nothing is found, you're asked to
  confirm before it's added without an identifier, which is common for
  older books.
- View the full audit log, or just the history for one book.
- Sign up for an account. New accounts need to be approved by an admin
  before they can log in. Signup also asks a quiz question ("What is the
  speed of light, in God-given units?") to keep out simple bots.
- Admins can approve or deny new accounts, delete an account (optionally
  moving that person's books to someone else first), reset a forgotten
  password, and promote other users to admin.

## Dependencies

- Ruby 3.2 or newer
- Bundler (`gem install bundler`)
- Node.js 20.19 or newer (22 is recommended)
- npm 10 or newer (comes with Node)

You only need Node if you're building or developing the frontend. A
production server that just serves the already-built frontend doesn't
need it.

## Install

```bash
git clone https://github.com/vajralakushal/WeinbergLedger.git
cd WeinbergLedger

cd backend
bundle install
bin/rails db:migrate
bin/rails db:seed
cd ..

cd frontend
npm install
cd ..
```

The migration only adds the tables needed for accounts. It doesn't touch
the existing book data in `library.db`.

`db:seed` creates a starting admin account if one doesn't already exist,
so there's always someone who can approve new signups. The default
username is `admin` and the default password is `changeme123`; you'll be
asked to set a new password the first time you log in. To choose your
own instead of the default, set `SEED_ADMIN_USERNAME` and
`SEED_ADMIN_PASSWORD` before running `db:seed`. It's safe to run
`db:seed` again later. It won't touch an admin account that already
exists.

## Run it

Open two terminal windows.

**Backend**, from the `backend` folder:
```bash
bin/rails server
```
This starts the API at http://localhost:3000.

**Frontend**, from the `frontend` folder:
```bash
npm run dev
```
This prints a URL, usually http://localhost:5173. Open that in your
browser and use the app there. It talks to the backend automatically.

Log in with the admin account `db:seed` created (see Install above). If
you want to make a second admin later, have that person sign up through
the app, then run this from the `backend` folder to promote their
account:
```bash
bin/rails runner 'User.find_by(username: "theirusername").update!(admin_status: true, approval_status: "APPROVED")'
```

## Tests

```bash
cd backend && bin/rails test
cd frontend && npm test
```
