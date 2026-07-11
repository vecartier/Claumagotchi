import XCTest
import Foundation
import NaturalLanguage

/// Tests for the auto language routing decision (Kokoro vs Apple system voice).
///
/// Note: @testable import is not supported for .executableTarget in this project.
/// The Kokoro language map is replicated here and must stay in sync with
/// Sources/Voice/KokoroVoiceCatalog.swift (kokoroLangToISO), and the detection
/// logic mirrors TTSService.dominantLanguage(of:).

// MARK: - Replicated routing logic for test verification

/// Mirror of KokoroVoiceCatalog.kokoroLangToISO values
private let kokoroISOCodes = ["en", "es", "fr", "hi", "it", "ja", "pt", "zh"]

/// Mirror of KokoroVoiceCatalog.supportsLanguage(_:)
private func kokoroSupports(_ isoCode: String) -> Bool {
    kokoroISOCodes.contains { isoCode.hasPrefix($0) }
}

/// Mirror of TTSService.dominantLanguage(of:)
private func dominantLanguage(of text: String) -> String? {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(String(text.prefix(400)))
    return recognizer.dominantLanguage?.rawValue
}

final class LanguageRoutingTests: XCTestCase {

    func testRussianIsNotSupportedByKokoro() {
        XCTAssertFalse(kokoroSupports("ru"))
    }

    func testKokoroCatalogLanguagesAreSupported() {
        for code in kokoroISOCodes {
            XCTAssertTrue(kokoroSupports(code), "\(code) must be supported")
        }
        XCTAssertTrue(kokoroSupports("zh-Hans"), "BCP-47 variants must match by prefix")
    }

    func testRussianTextIsDetected() {
        XCTAssertEqual(dominantLanguage(of: "Задача выполнена, все тесты прошли успешно."), "ru")
    }

    func testEnglishTextIsDetected() {
        XCTAssertEqual(dominantLanguage(of: "Task completed, all tests passed successfully."), "en")
    }

    func testRoutingDecision() {
        // Russian text → not supported by Kokoro → routed to Apple system voice
        let ru = dominantLanguage(of: "Привет! Я закончил задачу, можно проверять результат.") ?? ""
        XCTAssertFalse(kokoroSupports(ru))

        // English text → supported → stays on Kokoro
        let en = dominantLanguage(of: "Hello! I finished the task, feel free to review the result.") ?? ""
        XCTAssertTrue(kokoroSupports(en))
    }
}
