import CoreML
import NaturalLanguage

final class CoreMLTextModelAnalyzing: TextModelAnalyzing {
    private let model: NLModel

    init(model: NLModel) {
        self.model = model
    }

    static func load(from url: URL) -> TextModelAnalyzing {
        guard let mlModel = try? MLModel(contentsOf: url),
              let nlModel = try? NLModel(mlModel: mlModel) else {
            return NoOpTextModelAnalyzing()
        }
        return CoreMLTextModelAnalyzing(model: nlModel)
    }

    static let `default`: TextModelAnalyzing = {
        guard let url = Bundle(for: CoreMLTextModelAnalyzing.self)
            .url(forResource: "ContentSafetyTextClassifier", withExtension: "mlmodelc") else {
            return NoOpTextModelAnalyzing()
        }
        return load(from: url)
    }()

    func confidence(for text: String) -> Double {
        model.predictedLabelHypotheses(for: text, maximumCount: 2)["unsafe"] ?? 0.0
    }
}
