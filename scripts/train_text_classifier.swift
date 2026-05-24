// Run from repo root:
//   xcrun --sdk macosx swift -framework CreateML scripts/train_text_classifier.swift fixture
//   xcrun --sdk macosx swift -framework CreateML scripts/train_text_classifier.swift production /path/to/jigsaw_train.csv
//
// Compile the output model:
//   xcrun coremlcompiler compile <output>.mlmodel <dest-dir>/
//
// Dataset for production mode:
//   https://www.kaggle.com/competitions/jigsaw-toxic-comment-classification-challenge/data
import CreateML
import Foundation

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "help"

if mode == "fixture" {
    let texts: [String] = [
        "I hate you and I want to kill you",
        "send me explicit photos right now",
        "you are worthless garbage, go die",
        "nude picture request here",
        "I will find where you live and hurt you",
        "severe obscene language example text",
        "The weather looks great today",
        "I really enjoy spending time with my family",
        "Let us go for a walk in the park",
        "The quarterly report numbers look good",
        "Can you help me with this homework problem?",
        "I like reading books on the weekend",
    ]
    let labels: [String] = [
        "unsafe","unsafe","unsafe","unsafe","unsafe","unsafe",
        "safe","safe","safe","safe","safe","safe",
    ]

    let table = try MLDataTable(dictionary: ["text": texts, "label": labels])
    let classifier = try MLTextClassifier(
        trainingData: table,
        textColumn:   "text",
        labelColumn:  "label"
    )
    let outURL = URL(fileURLWithPath: "TestContentSafetyTextClassifier.mlmodel")
    try classifier.write(to: outURL)
    print("Fixture model written to \(outURL.path)")
    print("Next: xcrun coremlcompiler compile TestContentSafetyTextClassifier.mlmodel ios/Tests/Resources/")

} else if mode == "production" {
    guard CommandLine.arguments.count > 2 else {
        print("Usage: swift scripts/train_text_classifier.swift production /path/to/jigsaw_train.csv")
        print("Dataset: https://www.kaggle.com/competitions/jigsaw-toxic-comment-classification-challenge/data")
        exit(1)
    }
    let csvPath = CommandLine.arguments[2]
    let rawTable = try MLDataTable(contentsOf: URL(fileURLWithPath: csvPath))

    // Jigsaw columns: id, comment_text, toxic, severe_toxic, obscene, threat, insult, identity_hate
    // Label "unsafe" if any toxicity column == 1, otherwise "safe"
    let unsafeCols = ["toxic", "severe_toxic", "obscene", "threat", "insult", "identity_hate"]
    let n = rawTable.size.rows

    var labelArray = [String](repeating: "safe", count: n)
    for colName in unsafeCols {
        let col = rawTable[colName]
        for i in 0..<n {
            if case .int(let val) = col[i], val == 1 {
                labelArray[i] = "unsafe"
            }
        }
    }

    guard rawTable.columnNames.contains("comment_text") else {
        print("Error: 'comment_text' column not found in CSV"); exit(1)
    }
    let textCol = rawTable["comment_text"]
    var textArray: [String] = []
    var alignedLabels: [String] = []
    for i in 0..<n {
        if case .string(let s) = textCol[i] {
            textArray.append(s)
            alignedLabels.append(labelArray[i])
        }
    }
    guard !textArray.isEmpty else {
        print("Error: no valid rows extracted from CSV"); exit(1)
    }

    let trainTable = try MLDataTable(dictionary: ["text": textArray, "label": alignedLabels])
    let classifier = try MLTextClassifier(
        trainingData: trainTable,
        textColumn:   "text",
        labelColumn:  "label"
    )
    let outURL = URL(fileURLWithPath: "ContentSafetyTextClassifier.mlmodel")
    try classifier.write(to: outURL)
    print("Production model written to \(outURL.path)")
    print("Next: xcrun coremlcompiler compile ContentSafetyTextClassifier.mlmodel ios/Resources/")

} else {
    print("Usage: xcrun --sdk macosx swift -framework CreateML scripts/train_text_classifier.swift <mode>")
    print("Modes: fixture, production /path/to/jigsaw_train.csv")
    exit(1)
}
