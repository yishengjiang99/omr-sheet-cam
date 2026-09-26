import XCTest
@testable import OMRHomrIOS

final class DecoderLoopTests: XCTestCase {
    func testUnconfiguredRunnerRefusesFakeLogits() throws {
        let vocab = try TokenizerLoader.loadVocabulary()
        let loop = DecoderLoop(vocabulary: vocab)
        let ctx = EncoderContext(bytes: Data(), dtype: .float32, shape: [])
        XCTAssertThrowsError(
            try loop.generate(context: ctx, stepRunner: UnconfiguredDecoderStepRunner())
        ) { error in
            guard case OMRError.sessionNotConfigured = error else {
                return XCTFail("expected sessionNotConfigured, got \(error)")
            }
        }
    }

    func testLoopStopsOnEOSWithoutEmittingControl() throws {
        let vocab = try TokenizerLoader.loadVocabulary()
        let loop = DecoderLoop(vocabulary: vocab)
        let ctx = EncoderContext(bytes: Data(), dtype: .float32, shape: [])
        let runner = ImmediateEOSRunner(eos: vocab.eosToken, nonote: vocab.nonoteToken)
        let symbols = try loop.generate(context: ctx, stepRunner: runner)
        XCTAssertTrue(symbols.isEmpty)
        XCTAssertEqual(runner.steps, 1)
    }

    func testOracleFixtureDirectoryHookShips() {
        // Gate-1 oracle path: Fixtures/c_scale_staff_oracle/ (empty until research export).
        let keep = Bundle.module.url(
            forResource: ".gitkeep",
            withExtension: nil,
            subdirectory: "Fixtures/c_scale_staff_oracle"
        )
        let readme = Bundle.module.url(
            forResource: "README",
            withExtension: "md",
            subdirectory: "Fixtures"
        )
        XCTAssertTrue(
            keep != nil || readme != nil,
            "oracle fixture hook path missing from test bundle"
        )
    }
}

private final class ImmediateEOSRunner: DecoderStepRunning, @unchecked Sendable {
    let eos: Int
    let nonote: Int
    private(set) var steps: Int = 0

    init(eos: Int, nonote: Int) {
        self.eos = eos
        self.nonote = nonote
    }

    func runStep(_ input: DecoderStepInput) throws -> DecoderStepOutput {
        steps += 1
        return DecoderStepOutput(
            rhythmArgmax: eos,
            pitchArgmax: nonote,
            liftArgmax: nonote,
            positionArgmax: nonote,
            articulationArgmax: nonote,
            slurArgmax: nonote
        )
    }
}
