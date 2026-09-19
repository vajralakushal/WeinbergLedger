require "test_helper"

class BulkCsvImporterTest < ActiveSupport::TestCase
  test "identifier_has_isbn_or_lc?" do
    assert BulkCsvImporter.identifier_has_isbn_or_lc?("LC : 69017408")
    assert BulkCsvImporter.identifier_has_isbn_or_lc?("OCLC : (OCoLC)123; ISBN : 3764354909")
    refute BulkCsvImporter.identifier_has_isbn_or_lc?("OCLC : (OCoLC)36307953")
    refute BulkCsvImporter.identifier_has_isbn_or_lc?("")
    refute BulkCsvImporter.identifier_has_isbn_or_lc?(nil)
  end

  test "parse maps columns and line numbers" do
    csv = <<~CSV
      Owner,Borrower,Shelf,DD,Title,Creator,Publisher,Edition,Series,Notes,Subject,Creation Date,Identifier
      Alex Lu,,3,QA1,Algebra,Lang,Springer,,,,Math,2002,ISBN : 038795385X
    CSV
    rows = BulkCsvImporter.parse(csv)
    assert_equal 1, rows.length
    r = rows.first
    assert_equal 2, r[:line]
    assert_equal "Algebra",  r[:values]["TITLE"]
    assert_equal "Alex Lu",  r[:values]["OWNER"]
    assert_equal "3",        r[:values]["LOCATION"] # Shelf -> LOCATION
    assert_equal "ISBN : 038795385X", r[:values]["IDENTIFIER"]
    refute r[:values].key?("DD") # dropped column
  end

  test "parse missing required headers raises" do
    err = assert_raises(ArgumentError) do
      BulkCsvImporter.parse("Owner,Title\nAlex,Algebra\n") # no Identifier column
    end
    assert_match(/Identifier/i, err.message)
  end
end
