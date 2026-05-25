// Run from repo root:
//   xcrun --sdk macosx swift -framework CreateML scripts/train_text_classifier.swift fixture
//   xcrun --sdk macosx swift -framework CreateML scripts/train_text_classifier.swift placeholder
//   xcrun --sdk macosx swift -framework CreateML scripts/train_text_classifier.swift production /path/to/jigsaw_train.csv
//
// Compile the output model:
//   xcrun coremlcompiler compile <output>.mlmodel <dest-dir>/
//
// Dataset for production mode:
//   https://www.kaggle.com/competitions/jigsaw-toxic-comment-classification-challenge/data
//
// Modes:
//   fixture     → TestContentSafetyTextClassifier.mlmodel  (12 samples, for unit tests)
//   placeholder → ContentSafetyTextClassifier.mlmodel      (65 samples, dev stand-in until Jigsaw model)
//   production  → ContentSafetyTextClassifier.mlmodel      (full Jigsaw dataset)
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

} else if mode == "placeholder" {
    // 65-sample stand-in for the real Jigsaw model. Replace with production mode once dataset available.
    let texts: [String] = [
        // unsafe — hate / threats
        "I hate you and I want to kill you",
        "you are worthless garbage, go die",
        "I will find where you live and hurt you",
        "go kill yourself nobody wants you here",
        "I hope you get cancer and die slowly",
        "you deserve to suffer for what you did",
        "threatening message I will hurt your family",
        "I know where you live and I am coming for you",
        "filthy disgusting subhuman trash",
        "your kind should be exterminated",
        "die in a fire you worthless piece of garbage",
        "I will destroy everything you love",
        "you should not be allowed to exist",
        "crawl back into the hole you came from",
        "burn in hell you pathetic excuse for a human",
        // unsafe — sexual / explicit
        "send me explicit photos right now",
        "nude picture request here",
        "send nudes or I will share your secrets",
        "explicit sexual content involving minors",
        "pornographic material requested",
        "I want to see you naked right now",
        "graphic sexual description here",
        "adult explicit content example",
        "soliciting explicit images from you",
        "sexual harassment example message",
        // unsafe — insults / harassment
        "you are a complete moron and an idiot",
        "stupid fat ugly loser nobody likes you",
        "you are the dumbest person I have ever met",
        "worthless failure go away forever",
        "everyone hates you and you have no friends",
        "you are mentally ill and belong in an asylum",
        "disgusting creep stay away from people",
        "utter incompetent waste of space",
        "absolute braindead manchild loser",
        "pathetic excuse for a human being",
        // unsafe — drugs / illegal
        "selling cocaine and heroin cheap prices",
        "where can I buy illegal weapons no questions",
        "dark web drug marketplace link here",
        "manufacturing methamphetamine instructions",
        // safe — everyday
        "The weather looks great today",
        "I really enjoy spending time with my family",
        "Let us go for a walk in the park",
        "The quarterly report numbers look good",
        "Can you help me with this homework problem?",
        "I like reading books on the weekend",
        "What time does the meeting start tomorrow?",
        "The new restaurant downtown has great reviews",
        "I finished the project ahead of schedule",
        "Looking forward to the holiday next week",
        "The sunset was beautiful this evening",
        "I adopted a puppy from the shelter today",
        "My garden is blooming nicely this spring",
        "We are planning a road trip next month",
        "The concert last night was fantastic",
        "I just started learning to play the guitar",
        "Can you recommend a good book to read?",
        "The team did a great job on the presentation",
        "I made homemade pasta for dinner tonight",
        "The kids had so much fun at the playground",
        "Just finished a really satisfying workout",
        "The new software update fixed all the bugs",
        "I love hiking in the mountains on weekends",
        "Coffee shop on Main Street has the best lattes",
        "Looking forward to catching up with old friends",
    ]
    let labels: [String] = [
        "unsafe","unsafe","unsafe","unsafe","unsafe",  // hate/threats 1-5
        "unsafe","unsafe","unsafe","unsafe","unsafe",  // hate/threats 6-10
        "unsafe","unsafe","unsafe","unsafe","unsafe",  // hate/threats 11-15
        "unsafe","unsafe","unsafe","unsafe","unsafe",  // sexual 16-20
        "unsafe","unsafe","unsafe","unsafe","unsafe",  // sexual 21-25
        "unsafe","unsafe","unsafe","unsafe","unsafe",  // insults 26-30
        "unsafe","unsafe","unsafe","unsafe","unsafe",  // insults 31-35
        "unsafe","unsafe","unsafe","unsafe",           // drugs 36-39
        "safe","safe","safe","safe","safe",
        "safe","safe","safe","safe","safe",
        "safe","safe","safe","safe","safe",
        "safe","safe","safe","safe","safe",
        "safe","safe","safe","safe","safe",
    ]

    let table = try MLDataTable(dictionary: ["text": texts, "label": labels])
    let classifier = try MLTextClassifier(
        trainingData: table,
        textColumn:   "text",
        labelColumn:  "label"
    )
    let outURL = URL(fileURLWithPath: "ContentSafetyTextClassifier.mlmodel")
    try classifier.write(to: outURL)
    print("Placeholder model written to \(outURL.path)")
    print("Next: xcrun coremlcompiler compile ContentSafetyTextClassifier.mlmodel ios/Resources/")

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
