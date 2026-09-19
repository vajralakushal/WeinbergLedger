class Book < ApplicationRecord
  self.table_name = "LIBRARY"
  self.primary_key = "ID"

  # OWNER is declared INTEGER in the legacy schema but always holds a name
  # string (e.g. "Alex Lu") — without this override, ActiveRecord casts
  # non-numeric assignments through its integer caster and silently stores 0.
  attribute :OWNER, :string

  # Columns a user may set when adding a book (mirrors the DB schema minus ID).
  COLUMNS = %w[
    OWNER BORROWER LOCATION TITLE CREATOR
    PUBLISHER SERIES SUBJECT CREATION_DATE IDENTIFIER
  ].freeze

  # Fields searched per token — mirrors the old Sinatra app's db_search().
  SEARCH_FIELDS = %w[
    TITLE CREATOR OWNER LOCATION BORROWER
    PUBLISHER SERIES SUBJECT CREATION_DATE IDENTIFIER
  ].freeze

  COLUMNS.each { |col| alias_attribute col.downcase.to_sym, col.to_sym }

  has_many :audit_logs, class_name: "AuditLog", foreign_key: "BOOK_ID",
                         inverse_of: :book, dependent: nil

  validates :title, :owner, presence: true

  # Parses the IDENTIFIER field, e.g. "LC : ...; ISBN : ...; OCLC : (OCoLC)...".
  # Ported from app.rb's extract_identifiers().
  def identifiers
    id_str = self[:IDENTIFIER].to_s
    return { "Error" => "No identifiers exist" } if id_str.length < 3

    result = {}
    id_str.split("; ").each do |entry|
      parts = entry.strip.split(" : ", 2)
      next unless parts.length == 2

      id_type, value_part = parts[0].strip, parts[1].strip
      record = if id_type == "OCLC"
        { "value" => value_part.sub(/^\(OCoLC\)(oc[a-z]+)?/, "") }
      elsif (m = value_part.match(/^(\S+)\s+(\(.+\))$/))
        { "value" => m[1], "qualifier" => m[2] }
      else
        { "value" => value_part }
      end

      result[id_type] ||= []
      result[id_type] << record
    end
    result
  end

  # Tokenise query -> for each token OR across `fields` -> AND across tokens.
  # `fields` narrows which columns a token may match (defaults to all of
  # them), letting callers isolate the search to specific fields.
  def self.search(query, fields: SEARCH_FIELDS)
    tokens = query.to_s.strip.split
    return none if tokens.empty?

    fields = fields.to_a & SEARCH_FIELDS
    fields = SEARCH_FIELDS if fields.empty?

    or_clause = fields.map { |f| "\"#{f}\" LIKE ?" }.join(" OR ")
    tokens.reduce(all) do |scope, token|
      scope.where(or_clause, *([ "%#{token}%" ] * fields.length))
    end
  end
end
