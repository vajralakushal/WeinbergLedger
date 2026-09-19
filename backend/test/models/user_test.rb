require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "assigns a 4-digit user_id on create" do
    user = create_user!
    assert_includes 1..9999, user.user_id
  end

  test "retries user_id assignment past a collision" do
    taken = create_user!
    free  = (1..9999).find { |n| n != taken.user_id }

    contender = User.new(first_name: "C", last_name: "D", username: "collider",
                          password: "password123", approval_status: User::PENDING)
    sequence = [ taken.user_id, free ]
    contender.stub(:rand, ->(_range) { sequence.shift }) do
      contender.save!
    end
    assert_equal free, contender.user_id
  end

  test "requires a unique username" do
    create_user!(username: "dupe")
    dupe = User.new(first_name: "A", last_name: "B", username: "dupe",
                     password: "password123", approval_status: User::PENDING)
    refute dupe.valid?
    assert_includes dupe.errors[:username], "has already been taken"
  end

  test "normalizes username whitespace" do
    user = create_user!(username: "  spaced  ")
    assert_equal "spaced", user.username
  end

  test "authenticates with the right password only" do
    user = create_user!(password: "correcthorse")
    assert user.authenticate("correcthorse")
    refute user.authenticate("wrong")
  end

  test "sweep_stale! removes denied users and stale pending users, keeps fresh ones" do
    denied = create_user!(approval_status: User::DENIED)
    stale  = create_user!(approval_status: User::PENDING, created_at: 25.hours.ago)
    fresh  = create_user!(approval_status: User::PENDING, created_at: 1.hour.ago)
    approved = create_user!(approval_status: User::APPROVED)

    User.sweep_stale!

    refute User.exists?(user_id: denied.user_id)
    refute User.exists?(user_id: stale.user_id)
    assert User.exists?(user_id: fresh.user_id)
    assert User.exists?(user_id: approved.user_id)
  end

  test "full_name joins first and last name" do
    user = create_user!(first_name: "Ada", last_name: "Lovelace")
    assert_equal "Ada Lovelace", user.full_name
  end
end
