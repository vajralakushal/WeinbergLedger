# Ensures an admin account exists so a fresh install has someone who can
# approve other signups. Safe to run more than once: it does nothing if an
# account with that username already exists (it never touches an existing
# account's password). Override the defaults with env vars if you want to
# choose your own username/password instead.
admin_username = ENV.fetch("SEED_ADMIN_USERNAME", "admin")
admin_password = ENV.fetch("SEED_ADMIN_PASSWORD", "changeme123")

if User.exists?(username: admin_username)
  puts "Admin account '#{admin_username}' already exists, skipping."
else
  User.create!(
    first_name: ENV.fetch("SEED_ADMIN_FIRST_NAME", "Admin"),
    last_name: ENV.fetch("SEED_ADMIN_LAST_NAME", "User"),
    username: admin_username,
    password: admin_password,
    approval_status: User::APPROVED,
    admin_status: true,
    must_change_password: true
  )
  puts "Created admin account. Username: #{admin_username}, password: #{admin_password}"
  puts "You'll be asked to set a new password the first time you log in."
end
