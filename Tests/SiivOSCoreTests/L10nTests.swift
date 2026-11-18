import XCTest
@testable import SiivOSCore

final class L10nTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L10n.overrideLanguage = .english
    }

    override func tearDown() {
        L10n.overrideLanguage = .english
        super.tearDown()
    }

    func testEnglishTextIsReturnedAsWritten() {
        XCTAssertEqual(L10n.text("History", in: .english), "History")
        XCTAssertEqual(tr("History"), "History")
    }

    func testFinnishTextIsLookedUp() {
        XCTAssertEqual(L10n.text("History", in: .finnish), "Historia")
        XCTAssertEqual(L10n.text("Cleanup", in: .finnish), "Siivous")
    }

    func testTextWithoutATranslationFallsBackToEnglish() {
        XCTAssertEqual(L10n.text("No such text in the table", in: .finnish), "No such text in the table")
    }

    func testChangingPartsAreFilledIn() {
        XCTAssertEqual(L10n.text("Removed %1$@ items", ["3"], in: .english), "Removed 3 items")
        XCTAssertEqual(L10n.text("Removed %1$@ items", ["3"], in: .finnish), "Poistettu 3 kohdetta")
        XCTAssertEqual(L10n.fill("%2$@ before %1$@", with: ["one", "two"]), "two before one")
        XCTAssertEqual(L10n.fill("%1$@ and %1$@", with: ["x"]), "x and x")
    }

    func testAnArgumentThatLooksLikeAMarkerIsLeftAlone() {
        // A file could really be called this.
        XCTAssertEqual(L10n.fill("Removed %1$@ (%2$@)", with: ["%2$@.txt", "5 MB"]), "Removed %2$@.txt (5 MB)")
    }

    func testOtherPercentSignsAreKept() {
        XCTAssertEqual(L10n.fill("100% of %1$@", with: ["it"]), "100% of it")
        XCTAssertEqual(L10n.fill("%9$@ stays", with: ["only one"]), "%9$@ stays")
        XCTAssertEqual(L10n.fill("ends with %", with: ["x"]), "ends with %")
        XCTAssertEqual(L10n.fill("nothing to fill %1$@", with: []), "nothing to fill %1$@")
    }

    func testEveryTranslationUsesTheSameChangingPartsAsTheEnglish() {
        XCTAssertFalse(FinnishTexts.table.isEmpty)
        for (english, finnish) in FinnishTexts.table {
            XCTAssertEqual(
                L10n.placeholders(in: english),
                L10n.placeholders(in: finnish),
                "Changing parts differ for: \(english)"
            )
            XCTAssertFalse(finnish.isEmpty, "Empty translation for: \(english)")
        }
    }

    func testTheEngineSpeaksFinnishWhenAsked() {
        L10n.overrideLanguage = .finnish
        XCTAssertEqual(CachesScanner().title, "Sovellusten välimuistit")
        XCTAssertEqual(NeverOffer.Category.signIn.title, "Kirjautuminen, salasanat ja maksaminen")
        XCTAssertEqual(SafetyCoreError.nothingToRemove.errorDescription, "Poistettavaa ei ole.")
        XCTAssertTrue(OldDownloadsScanner(olderThanDays: 90).summary.contains("yli 90 päivään"))
    }
}
