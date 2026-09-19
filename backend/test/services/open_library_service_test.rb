require "test_helper"

# Minimal stand-in for a Net::HTTP response, so lookup tests need no network.
class FakeResp
  def initialize(ok:, body: "", code: "200")
    @ok = ok
    @body = body
    @code = code
  end

  def is_a?(klass)
    klass == Net::HTTPOK ? @ok : super
  end

  attr_reader :body, :code
end

class OpenLibraryServiceTest < ActiveSupport::TestCase
  test "lookup ok and not found" do
    ENV.delete("DISABLE_OPENLIBRARY")
    found = FakeResp.new(ok: true, body: { "ISBN:1" => { "title" => "T" } }.to_json)
    OpenLibraryService.stub(:http_get, ->(_uri) { found }) do
      r = OpenLibraryService.lookup("ISBN:1")
      assert_equal :ok, r[:status]
      assert_equal "T", r[:data]["title"]
    end

    empty = FakeResp.new(ok: true, body: "{}")
    OpenLibraryService.stub(:http_get, ->(_uri) { empty }) do
      assert_equal :not_found, OpenLibraryService.lookup("ISBN:1")[:status]
    end
  ensure
    ENV["DISABLE_OPENLIBRARY"] = "1"
  end

  test "lookup retries then errors on transient failure" do
    ENV.delete("DISABLE_OPENLIBRARY")
    calls = 0
    raising = ->(_uri) { calls += 1; raise Errno::ECONNREFUSED }
    OpenLibraryService.stub(:http_get, raising) do
      OpenLibraryService.stub(:sleep, nil) do # don't actually wait between retries
        assert_equal :error, OpenLibraryService.lookup("ISBN:1")[:status]
      end
    end
    assert_equal 3, calls # retried up to MAX_ATTEMPTS
  ensure
    ENV["DISABLE_OPENLIBRARY"] = "1"
  end

  test "lookup retries on non 200 then succeeds" do
    ENV.delete("DISABLE_OPENLIBRARY")
    responses = [
      FakeResp.new(ok: false, code: "503"),
      FakeResp.new(ok: true, body: { "ISBN:1" => { "title" => "Recovered" } }.to_json)
    ]
    OpenLibraryService.stub(:http_get, ->(_uri) { responses.shift }) do
      OpenLibraryService.stub(:sleep, nil) do
        r = OpenLibraryService.lookup("ISBN:1")
        assert_equal :ok, r[:status]
        assert_equal "Recovered", r[:data]["title"]
      end
    end
  ensure
    ENV["DISABLE_OPENLIBRARY"] = "1"
  end

  test "map_to_columns maps fields" do
    data = {
      "title"    => "Introduction to Topology",
      "subtitle" => "Pure and Applied",
      "authors"  => [ { "name" => "Colin Adams" }, { "name" => "Robert Franzosa" } ],
      "publishers"     => [ { "name" => "Pearson" } ],
      "publish_places" => [ { "name" => "Upper Saddle River" } ],
      "publish_date"   => "2008",
      "subjects"       => [ { "name" => "Topology" }, "Mathematics" ],
      "identifiers"    => { "isbn_13" => [ "9780131848696" ], "lccn" => [ "2007041561" ] }
    }
    m = OpenLibraryService.map_to_columns(data)
    assert_equal "Introduction to Topology: Pure and Applied", m["TITLE"]
    assert_equal "Colin Adams; Robert Franzosa", m["CREATOR"]
    assert_equal "Upper Saddle River : Pearson, 2008", m["PUBLISHER"]
    assert_equal "2008", m["CREATION_DATE"]
    assert_equal "Topology; Mathematics", m["SUBJECT"]
    assert_equal "LC : 2007041561; ISBN : 9780131848696", m["IDENTIFIER"]
  end
end
