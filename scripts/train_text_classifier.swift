#!/usr/bin/env swift -framework CreateML
import CreateML
import Foundation

// Usage:
//   swift scripts/train_text_classifier.swift fixture   → TestContentSafetyTextClassifier.mlmodel
//   swift scripts/train_text_classifier.swift production /path/to/jigsaw_train.csv
//                                                       → ContentSafetyTextClassifier.mlmodel
//
// Compile to .mlmodelc after training:
//   xcrun coremlcompiler compile <output>.mlmodel <dest-dir>/

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "fixture"

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

    let textCol = rawTable["comment_text"]
    let textArray = (0..<n).compactMap { i -> String? in
        if case .string(let s) = textCol[i] { return s }
        return nil
    }

    let trainTable = try MLDataTable(dictionary: ["text": textArray, "label": labelArray])
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
    print("Unknown mode '\(mode)'. Use 'fixture' or 'production'.")
    exit(1)
}
