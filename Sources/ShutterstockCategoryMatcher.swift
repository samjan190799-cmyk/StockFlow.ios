import Foundation

// MARK: - Smart Category Matcher for Shutterstock & Microstocks
public struct ShutterstockCategoryMatcher: Sendable {
    
    public static let allCategories: [String] = [
        "Abstract", "Animals/Wildlife", "Arts", "Backgrounds/Textures", "Beauty/Fashion",
        "Buildings/Landmarks", "Business/Finance", "Celebrities", "Education", "Food and drink",
        "Healthcare/Medical", "Holidays", "Industrial", "Interiors", "Miscellaneous",
        "Nature", "Objects", "Parks/Outdoor", "People", "Religion",
        "Science", "Signs/Symbols", "Sports/Recreation", "Technology", "Transportation", "Vintage"
    ]
    
    private static let categoryKeywords: [String: Set<String>] = [
        "Animals/Wildlife": ["animal", "animals", "wildlife", "dog", "cat", "bird", "fish", "pet", "pets", "horse", "lion", "tiger", "bear", "insect", "puppy", "kitten", "safari", "zoo", "mammal", "reptile", "feather", "fauna"],
        "Buildings/Landmarks": ["building", "buildings", "landmark", "architecture", "monument", "tower", "bridge", "church", "cathedral", "castle", "skyscraper", "city", "town", "facade", "street", "urban", "exterior", "hall"],
        "Business/Finance": ["business", "office", "finance", "financial", "money", "bank", "currency", "investment", "stock", "market", "corporate", "meeting", "company", "businessman", "businesswoman", "worker", "contract", "economy", "growth"],
        "Food and drink": ["food", "drink", "beverage", "coffee", "tea", "fruit", "fruits", "vegetable", "vegetables", "dish", "dinner", "lunch", "breakfast", "restaurant", "cafe", "wine", "beer", "cocktail", "cake", "bread", "meal", "cooking", "delicious", "kitchen", "healthy food"],
        "Nature": ["nature", "landscape", "forest", "tree", "trees", "mountain", "mountains", "river", "lake", "sea", "ocean", "beach", "sky", "sunset", "sunrise", "water", "cloud", "clouds", "leaf", "plant", "flower", "flowers", "green", "scenic"],
        "People": ["people", "person", "man", "woman", "men", "women", "girl", "boy", "child", "children", "baby", "kid", "kids", "family", "portrait", "crowd", "human", "face", "smile", "happiness", "couple", "lifestyle"],
        "Technology": ["technology", "tech", "computer", "laptop", "smartphone", "phone", "screen", "internet", "ai", "artificial intelligence", "data", "cyber", "digital", "software", "hardware", "network", "code", "robot", "futuristic", "device"],
        "Transportation": ["transportation", "car", "cars", "vehicle", "auto", "automobile", "airplane", "plane", "flight", "aviation", "train", "railway", "bus", "truck", "road", "highway", "drive", "traffic", "ship", "boat", "yacht", "motorcycle", "bicycle"],
        "Sports/Recreation": ["sports", "sport", "recreation", "fitness", "gym", "running", "runner", "workout", "exercise", "athlete", "athletic", "training", "football", "soccer", "basketball", "tennis", "swimming", "bicycle", "cycling", "yoga"],
        "Healthcare/Medical": ["medical", "medicine", "doctor", "health", "hospital", "clinic", "nurse", "patient", "care", "treatment", "virus", "pharmacy", "pill", "pills", "laboratory", "stethoscope", "surgery", "therapy"],
        "Holidays": ["holiday", "holidays", "christmas", "new year", "halloween", "easter", "thanksgiving", "party", "celebration", "birthday", "festival", "carnival", "gift", "decoration", "celebrating"],
        "Beauty/Fashion": ["fashion", "beauty", "style", "stylish", "model", "makeup", "cosmetics", "dress", "clothing", "clothes", "hair", "hairstyle", "skin", "luxury", "glamour", "wear", "shoes", "accessory"],
        "Interiors": ["interior", "interiors", "room", "living room", "bedroom", "bathroom", "kitchen", "furniture", "decor", "design", "table", "chair", "sofa", "indoor", "indoors", "modern interior", "home"],
        "Industrial": ["industrial", "industry", "factory", "warehouse", "manufacturing", "construction", "builder", "worker", "machinery", "machine", "engineering", "crane", "metal", "heavy industry", "production"],
        "Arts": ["art", "arts", "painting", "drawing", "illustration", "creative", "artist", "sculpture", "theater", "museum", "gallery", "culture", "craft", "design", "artistic"],
        "Education": ["education", "school", "university", "college", "student", "students", "book", "books", "study", "studying", "learning", "knowledge", "library", "classroom", "teacher", "lecture"],
        "Backgrounds/Textures": ["background", "backgrounds", "texture", "textures", "pattern", "patterns", "wallpaper", "surface", "backdrop", "paper", "wood texture", "stone", "marble", "abstract background"],
        "Abstract": ["abstract", "concept", "conceptual", "shapes", "geometry", "geometric", "blur", "blurred", "lines", "glow", "space", "surreal", "fantasy"],
        "Parks/Outdoor": ["park", "parks", "outdoor", "outdoors", "garden", "recreation", "lawn", "bench", "path", "botanical", "public park", "picnic"],
        "Vintage": ["vintage", "retro", "antique", "old", "classic", "historical", "history", "nostalgia", "aged", "traditional", "rusty"],
        "Science": ["science", "scientific", "laboratory", "lab", "experiment", "research", "chemistry", "biology", "physics", "microscope", "molecules", "genetics", "dna", "astronomy", "space"],
        "Signs/Symbols": ["sign", "signs", "symbol", "symbols", "icon", "icons", "signal", "warning", "arrow", "badge", "label", "button", "direction"]
    ]
    
    /// Автоматически подбирает 1-2 наиболее релевантные категории для Shutterstock
    public static func match(title: String, description: String = "", keywords: [String]) -> [String] {
        var scores: [String: Int] = [:]
        
        // Объединяем все текстовые токены в единый нормализованный набор
        let textPool = "\(title) \(description) \(keywords.joined(separator: " "))".lowercased()
        let words = textPool.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
        
        let wordSet = Set(words)
        
        for (category, triggerWords) in categoryKeywords {
            var score = 0
            for trigger in triggerWords {
                if trigger.contains(" ") {
                    if textPool.contains(trigger) {
                        score += 3 // Фразовое совпадение весит больше
                    }
                } else if wordSet.contains(trigger) {
                    score += 2
                } else if textPool.contains(trigger) {
                    score += 1
                }
            }
            if score > 0 {
                scores[category] = score
            }
        }
        
        let sortedCategories = scores.sorted { $0.value > $1.value }.map { $0.key }
        
        if sortedCategories.isEmpty {
            return ["Objects", "Miscellaneous"]
        } else if sortedCategories.count == 1 {
            return [sortedCategories[0]]
        } else {
            return Array(sortedCategories.prefix(2))
        }
    }
}
