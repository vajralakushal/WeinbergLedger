require "csv"

# Parses bulk-import CSV text (same shape as the source spreadsheet) into
# rows keyed by Book column. Ported from app.rb's parse_bulk_csv /
# CSV_HEADER_MAP / identifier_has_isbn_or_lc?.
class BulkCsvImporter
  # CSV header (lowercased) -> DB column. DD / Edition / Notes are
  # intentionally dropped (no matching column), matching the original import.
  HEADER_MAP = {
    "owner" => "OWNER", "borrower" => "BORROWER", "shelf" => "LOCATION",
    "title" => "TITLE", "creator" => "CREATOR", "publisher" => "PUBLISHER",
    "series" => "SERIES", "subject" => "SUBJECT",
    "creation date" => "CREATION_DATE", "identifier" => "IDENTIFIER"
  }.freeze

  REQUIRED_HEADERS = %w[title owner identifier].freeze

  # True if the identifier string carries an ISBN or LC/LCCN entry.
  def self.identifier_has_isbn_or_lc?(str)
    str.to_s.match?(/(?:\A|;)\s*(?:ISBN|LCCN|LC)\s*:/i)
  end

  # Returns an array of { line:, values: { DB_COL => str|nil } }. Raises
  # ArgumentError with a human-readable message on malformed CSV or missing
  # required headers.
  def self.parse(text)
    table   = CSV.parse(text.to_s, headers: true)
    headers = Array(table.headers).compact.map { |h| h.to_s.strip.downcase }

    missing = REQUIRED_HEADERS - headers
    unless missing.empty?
      raise ArgumentError, "Missing required column(s): #{missing.map(&:capitalize).join(', ')}"
    end

    table.each_with_index.map do |row, i|
      values = {}
      row.each do |header, value|
        key = HEADER_MAP[header.to_s.strip.downcase]
        next unless key

        v = value.to_s.strip
        values[key] = v.empty? ? nil : v
      end
      { line: i + 2, values: values } # header is line 1; data starts at line 2
    end
  rescue CSV::MalformedCSVError => e
    raise ArgumentError, "Malformed CSV: #{e.message}"
  end
end
