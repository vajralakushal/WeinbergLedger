class AuditLog < ApplicationRecord
  self.table_name = "AUDIT_LOG"

  belongs_to :book, class_name: "Book", foreign_key: "BOOK_ID",
                     primary_key: "ID", inverse_of: :audit_logs, optional: true

  alias_attribute :book_id, :BOOK_ID
  alias_attribute :field, :FIELD
  alias_attribute :old_value, :OLD_VALUE
  alias_attribute :new_value, :NEW_VALUE
  alias_attribute :editor, :EDITOR
  alias_attribute :ip, :IP
  alias_attribute :timestamp, :TIMESTAMP

  # Records one audit row. `field` is a column name for edits, or
  # 'ADDED'/'REMOVED' for whole-book lifecycle events.
  def self.record!(book_id:, field:, old_value:, new_value:, editor:, ip:)
    create!(
      BOOK_ID: book_id, FIELD: field, OLD_VALUE: old_value, NEW_VALUE: new_value,
      EDITOR: editor, IP: ip, TIMESTAMP: Time.now.utc.iso8601
    )
  end
end
