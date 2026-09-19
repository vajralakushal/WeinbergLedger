require "net/http"
require "json"
require "fileutils"

# Talks to the OpenLibrary Books/Search/Covers APIs. Ported from app.rb's
# free functions (fetch_cover, openlibrary_lookup, find_isbn, map_openlibrary,
# http_get) — behavior is unchanged, just organized as a service class so it
# has one thing (this class) that tests can stub instead of top-level methods.
class OpenLibraryService
  USER_AGENT   = "WeinbergLedger/1.0 (shared grad library tool)".freeze
  MAX_ATTEMPTS = 3
  RETRY_DELAY  = 0.5 # seconds between retries

  # Look up one bib key (e.g. "ISBN:9780131118928"). Returns a status hash so
  # the caller can tell "genuinely not in OpenLibrary" apart from "the lookup
  # could not complete":
  #   { status: :ok, data: {...} } | { status: :not_found } | { status: :error, detail: "…" }
  # Set DISABLE_OPENLIBRARY to '1' (not found) or 'error' to force offline
  # behaviour in tests.
  def self.lookup(bibkey)
    return { status: :error }     if ENV["DISABLE_OPENLIBRARY"] == "error"
    return { status: :not_found } if ENV["DISABLE_OPENLIBRARY"] == "1"

    uri = URI("https://openlibrary.org/api/books?bibkeys=#{URI.encode_www_form_component(bibkey)}&format=json&jscmd=data")
    last_error = nil

    MAX_ATTEMPTS.times do |i|
      begin
        resp = http_get(uri)
        if resp.is_a?(Net::HTTPOK)
          data = JSON.parse(resp.body)[bibkey]
          return data ? { status: :ok, data: data } : { status: :not_found }
        end
        last_error = "HTTP #{resp.code}"
      rescue StandardError => e
        last_error = "#{e.class}: #{e.message}"
      end
      sleep(RETRY_DELAY) if i < MAX_ATTEMPTS - 1
    end

    { status: :error, detail: last_error }
  end

  # Best-effort: find an ISBN from title (+ creator) via OpenLibrary Search.
  def self.find_isbn(title, creator)
    return nil if ENV["DISABLE_OPENLIBRARY"] == "1"
    return nil if title.to_s.strip.empty?

    query = { title: title, fields: "isbn", limit: 1 }
    query[:author] = creator unless creator.to_s.strip.empty?
    uri  = URI("https://openlibrary.org/search.json?#{URI.encode_www_form(query)}")
    resp = http_get(uri)
    return nil unless resp.is_a?(Net::HTTPOK)

    docs = JSON.parse(resp.body)["docs"] || []
    docs.first && Array(docs.first["isbn"]).first
  rescue StandardError
    nil
  end

  # Maps an OpenLibrary "data" hash to our DB columns. Pure (no network) so
  # it is easy to test. Only non-empty fields are included.
  def self.map_to_columns(data)
    data ||= {}
    result = {}

    title    = data["title"].to_s.strip
    subtitle = data["subtitle"].to_s.strip
    result["TITLE"] = subtitle.empty? ? title : "#{title}: #{subtitle}" unless title.empty?

    authors = Array(data["authors"]).map { |a| a["name"] }.compact
    result["CREATOR"] = authors.join("; ") unless authors.empty?

    place      = Array(data["publish_places"]).map { |p| p["name"] }.compact.first
    publishers = Array(data["publishers"]).map { |p| p["name"] }.compact.join(", ")
    date       = data["publish_date"].to_s.strip
    left       = [ place, (publishers.empty? ? nil : publishers) ].compact.join(" : ")
    publisher  = [ left.empty? ? nil : left, date.empty? ? nil : date ].compact.join(", ")
    result["PUBLISHER"] = publisher unless publisher.empty?

    series = Array(data["series"]).map(&:to_s).reject(&:empty?)
    result["SERIES"] = series.join("; ") unless series.empty?

    subjects = Array(data["subjects"]).map { |s| s.is_a?(Hash) ? s["name"] : s }.compact
    result["SUBJECT"] = subjects.first(12).join("; ") unless subjects.empty?

    if (m = date.match(/\d{4}/))
      result["CREATION_DATE"] = m[0]
    end

    ids   = data["identifiers"] || {}
    lccn  = Array(ids["lccn"]).first
    isbn  = Array(ids["isbn_13"]).first || Array(ids["isbn_10"]).first
    oclc  = Array(ids["oclc"]).first
    parts = []
    parts << "LC : #{lccn}"          if lccn
    parts << "ISBN : #{isbn}"        if isbn
    parts << "OCLC : (OCoLC)#{oclc}" if oclc
    result["IDENTIFIER"] = parts.join("; ") unless parts.empty?

    result
  end

  # Try each identifier against the OpenLibrary Covers API. Saves to
  # img_path on first hit and returns the path; nil on failure.
  def self.fetch_cover(img_path, identifiers)
    key_map = [ [ "LC", "lccn" ], [ "ISBN", "isbn" ], [ "OCLC", "oclc" ] ]
    catch(:found) do
      key_map.each do |db_key, ol_key|
        (identifiers[db_key] || []).each do |entry|
          value = entry["value"].to_s.strip
          next if value.empty?

          uri = URI("https://covers.openlibrary.org/b/#{ol_key}/#{value}-M.jpg?default=false")
          begin
            resp = Net::HTTP.start(uri.host, uri.port,
                                    use_ssl: true, read_timeout: 6, open_timeout: 6) do |http|
              http.get(uri.request_uri)
            end
            next unless resp.is_a?(Net::HTTPOK)
            next unless resp["content-type"]&.include?("image")

            FileUtils.mkdir_p(File.dirname(img_path))
            File.binwrite(img_path, resp.body)
            throw :found, img_path
          rescue StandardError
            next
          end
        end
      end
      nil
    end
  end

  # OpenLibrary asks clients to identify themselves; a descriptive UA also
  # avoids aggressive throttling of the generic "Ruby" agent.
  def self.http_get(uri)
    req = Net::HTTP::Get.new(uri.request_uri)
    req["User-Agent"] = USER_AGENT
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                     read_timeout: 8, open_timeout: 6) do |http|
      http.request(req)
    end
  end
  private_class_method :http_get
end
