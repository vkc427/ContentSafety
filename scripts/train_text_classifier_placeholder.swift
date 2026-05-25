// Placeholder production model with 60+ varied samples.
// Run from repo root:
//   xcrun --sdk macosx swift -framework CreateML scripts/train_text_classifier_placeholder.swift
import CreateML
import Foundation

let texts: [String] = [
    // UNSAFE — hate / violence
    "I hate you and I want to kill you",
    "I will find where you live and hurt you",
    "you are worthless garbage, go die",
    "I am going to destroy you completely",
    "Die in a fire you piece of trash",
    "I will beat you until you beg for mercy",
    "You deserve to suffer for what you did",
    "Everyone who thinks like you should be eliminated",
    "I hope you get stabbed on your way home",
    "You are subhuman filth and deserve nothing",
    "Go kill yourself nobody cares about you",
    "I will make your life a living hell",
    "You are a worthless excuse for a human being",
    "Get out of my country you disgusting immigrant",
    "I fantasize about hurting people like you",

    // UNSAFE — sexual / explicit
    "send me explicit photos right now",
    "nude picture request here",
    "severe obscene language example text",
    "Send me your nudes immediately",
    "I want to see you undressed right now",
    "Explicit sexual content involving minors",
    "Graphic sexual description that is highly inappropriate",
    "Share pornographic material with me now",
    "Describe your sexual fantasies in detail",
    "I want to have inappropriate relations with you",
    "Sexually explicit request for images",
    "Obscene content about body parts",
    "Soliciting adult content from strangers",
    "Requesting intimate photos without consent",
    "Graphic sexual slur directed at someone",

    // UNSAFE — threats / harassment
    "I know your address and I am coming for you",
    "Your family will regret crossing me",
    "I will ruin your career and your life",
    "Watch your back because I am always watching",
    "You should be afraid of walking alone at night",
    "I will hack your accounts and expose everything",
    "Prepare yourself for what is coming to you",
    "Consider this your final warning to leave",
    "I will report you falsely to get you fired",
    "Threatening message designed to intimidate target",

    // SAFE — everyday conversation
    "The weather looks great today",
    "I really enjoy spending time with my family",
    "Let us go for a walk in the park",
    "The quarterly report numbers look good",
    "Can you help me with this homework problem?",
    "I like reading books on the weekend",
    "The coffee shop on Fifth Avenue is amazing",
    "My dog loves playing fetch in the backyard",
    "I am planning a birthday party for my daughter",
    "The new movie got excellent reviews",
    "Would you like to join us for dinner tonight?",
    "I just finished reading a fascinating novel",
    "The kids had a wonderful time at the zoo",
    "Spring flowers are blooming everywhere in the garden",
    "I learned a new recipe for pasta this weekend",
    "The conference presentation went really well",
    "We should schedule a meeting next Tuesday",
    "The sunrise this morning was absolutely beautiful",
    "I volunteered at the food bank on Saturday",
    "My colleague shared an interesting article today",
    "The team finished the project ahead of schedule",
    "I enjoy hiking in the mountains during summer",
    "The library just got new books in stock",
    "She did an incredible job on her presentation",
    "We celebrated our anniversary at a nice restaurant",
]

let labels: [String] = [
    // UNSAFE — 40
    "unsafe","unsafe","unsafe","unsafe","unsafe",
    "unsafe","unsafe","unsafe","unsafe","unsafe",
    "unsafe","unsafe","unsafe","unsafe","unsafe",
    "unsafe","unsafe","unsafe","unsafe","unsafe",
    "unsafe","unsafe","unsafe","unsafe","unsafe",
    "unsafe","unsafe","unsafe","unsafe","unsafe",
    "unsafe","unsafe","unsafe","unsafe","unsafe",
    "unsafe","unsafe","unsafe","unsafe","unsafe",
    // SAFE — 25
    "safe","safe","safe","safe","safe",
    "safe","safe","safe","safe","safe",
    "safe","safe","safe","safe","safe",
    "safe","safe","safe","safe","safe",
    "safe","safe","safe","safe","safe",
]

guard texts.count == labels.count else {
    print("ERROR: texts.count (\(texts.count)) != labels.count (\(labels.count))")
    exit(1)
}

print("Training on \(texts.count) samples…")
let table = try MLDataTable(dictionary: ["text": texts, "label": labels])
let classifier = try MLTextClassifier(
    trainingData: table,
    textColumn:   "text",
    labelColumn:  "label"
)
let outURL = URL(fileURLWithPath: "TestContentSafetyTextClassifier.mlmodel")
try classifier.write(to: outURL)
print("Placeholder production model written to \(outURL.path)")
