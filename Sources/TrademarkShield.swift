import Foundation

// MARK: - Trademark Match Model
public struct TrademarkMatch: Identifiable, Sendable, Hashable {
    public let id: String
    public let brand: String
    public let category: String
    public let replacement: String
    public let matchedLocation: String
    
    public init(brand: String, category: String, replacement: String, matchedLocation: String) {
        self.id = "\(brand)_\(matchedLocation)"
        self.brand = brand
        self.category = category
        self.replacement = replacement
        self.matchedLocation = matchedLocation
    }
}

// MARK: - Trademark Shield Result
public struct TrademarkShieldResult: Sendable {
    public let hasViolations: Bool
    public let matches: [TrademarkMatch]
    public let suggestedTitle: String
    public let suggestedKeywords: [String]
}

// MARK: - Trademark Shield Service
public final class TrademarkShield: Sendable {
    public static let shared = TrademarkShield()
    
    public struct BrandRule: Sendable {
        public let name: String
        public let category: String
        public let safeReplacement: String
        public let patterns: [String]
        
        public init(name: String, category: String, safeReplacement: String, patterns: [String] = []) {
            self.name = name
            self.category = category
            self.safeReplacement = safeReplacement
            self.patterns = patterns.isEmpty ? [name.lowercased()] : patterns.map { $0.lowercased() }
        }
    }
    
    /// База данных защищенных торговых марок и брендов мировых стоков
    public let registeredBrands: [BrandRule] = [
        // Tech & Electronics (Apple)
        BrandRule(name: "iPhone", category: "Apple", safeReplacement: "smartphone", patterns: ["iphone", "iphone [0-9]+", "iphone pro", "iphone pro max"]),
        BrandRule(name: "iPad", category: "Apple", safeReplacement: "tablet computer", patterns: ["ipad", "ipad pro", "ipad air", "ipad mini"]),
        BrandRule(name: "MacBook", category: "Apple", safeReplacement: "laptop", patterns: ["macbook", "macbook pro", "macbook air"]),
        BrandRule(name: "iMac", category: "Apple", safeReplacement: "desktop computer", patterns: ["imac"]),
        BrandRule(name: "AirPods", category: "Apple", safeReplacement: "wireless earbuds", patterns: ["airpods", "airpods pro", "airpods max"]),
        BrandRule(name: "Apple Watch", category: "Apple", safeReplacement: "smartwatch", patterns: ["apple watch", "iwatch"]),
        BrandRule(name: "Apple", category: "Apple", safeReplacement: "gadget", patterns: ["apple inc", "apple store", "apple device", "apple logo"]),
        
        // Tech & Electronics (Others)
        BrandRule(name: "Samsung Galaxy", category: "Tech", safeReplacement: "smartphone", patterns: ["samsung", "galaxy s[0-9]+", "galaxy note", "galaxy tab"]),
        BrandRule(name: "Sony", category: "Tech", safeReplacement: "camera", patterns: ["sony", "bravia", "walkman"]),
        BrandRule(name: "PlayStation", category: "Gaming", safeReplacement: "game console", patterns: ["playstation", "ps4", "ps5", "dualshock", "dualsense"]),
        BrandRule(name: "Xbox", category: "Gaming", safeReplacement: "game console", patterns: ["xbox", "xbox series"]),
        BrandRule(name: "Nintendo", category: "Gaming", safeReplacement: "handheld console", patterns: ["nintendo", "switch", "game boy"]),
        BrandRule(name: "GoPro", category: "Tech", safeReplacement: "action camera", patterns: ["gopro", "hero [0-9]+"]),
        BrandRule(name: "DJI", category: "Tech", safeReplacement: "drone quadcopter", patterns: ["dji", "mavic", "phantom drone", "osmo"]),
        BrandRule(name: "Canon", category: "Tech", safeReplacement: "dslr camera", patterns: ["canon eos", "canon camera"]),
        BrandRule(name: "Nikon", category: "Tech", safeReplacement: "dslr camera", patterns: ["nikon d[0-9]+", "nikkor"]),
        BrandRule(name: "Tesla", category: "Automotive", safeReplacement: "electric car", patterns: ["tesla", "cybertruck", "model 3", "model s", "model x", "model y"]),
        
        // Fashion & Apparel
        BrandRule(name: "Nike", category: "Apparel", safeReplacement: "sportswear", patterns: ["nike", "air max", "air jordan", "just do it", "swoosh"]),
        BrandRule(name: "Adidas", category: "Apparel", safeReplacement: "athletic shoes", patterns: ["adidas", "three stripes", "yeezy"]),
        BrandRule(name: "Puma", category: "Apparel", safeReplacement: "running shoes", patterns: ["puma"]),
        BrandRule(name: "Reebok", category: "Apparel", safeReplacement: "fitness sneakers", patterns: ["reebok"]),
        BrandRule(name: "Gucci", category: "Luxury", safeReplacement: "designer bag", patterns: ["gucci"]),
        BrandRule(name: "Louis Vuitton", category: "Luxury", safeReplacement: "luxury accessory", patterns: ["louis vuitton", "lv logo"]),
        BrandRule(name: "Chanel", category: "Luxury", safeReplacement: "luxury perfume", patterns: ["chanel"]),
        BrandRule(name: "Rolex", category: "Luxury", safeReplacement: "luxury wrist watch", patterns: ["rolex", "submariner"]),
        BrandRule(name: "Vans", category: "Apparel", safeReplacement: "canvas sneakers", patterns: ["vans off the wall"]),
        BrandRule(name: "Converse", category: "Apparel", safeReplacement: "high top sneakers", patterns: ["converse", "all star", "chuck taylor"]),
        
        // Automotive
        BrandRule(name: "BMW", category: "Automotive", safeReplacement: "luxury car", patterns: ["bmw", "m power"]),
        BrandRule(name: "Mercedes-Benz", category: "Automotive", safeReplacement: "luxury vehicle", patterns: ["mercedes", "mercedes-benz", "amg"]),
        BrandRule(name: "Audi", category: "Automotive", safeReplacement: "modern car", patterns: ["audi", "quattro"]),
        BrandRule(name: "Porsche", category: "Automotive", safeReplacement: "sports car", patterns: ["porsche", "porsche 911"]),
        BrandRule(name: "Ferrari", category: "Automotive", safeReplacement: "supercar", patterns: ["ferrari"]),
        BrandRule(name: "Lamborghini", category: "Automotive", safeReplacement: "exotic supercar", patterns: ["lamborghini", "huracan", "aventador"]),
        BrandRule(name: "Toyota", category: "Automotive", safeReplacement: "modern automobile", patterns: ["toyota"]),
        BrandRule(name: "Ford", category: "Automotive", safeReplacement: "pickup truck", patterns: ["ford mustang", "ford f-150"]),
        
        // Software, Media & Brands
        BrandRule(name: "Adobe Photoshop", category: "Software", safeReplacement: "photo editing software", patterns: ["photoshop", "lightroom", "illustrator", "premiere pro"]),
        BrandRule(name: "Instagram", category: "Social", safeReplacement: "social network", patterns: ["instagram", "insta story"]),
        BrandRule(name: "TikTok", category: "Social", safeReplacement: "short video app", patterns: ["tiktok"]),
        BrandRule(name: "YouTube", category: "Social", safeReplacement: "video streaming", patterns: ["youtube"]),
        BrandRule(name: "Facebook", category: "Social", safeReplacement: "social media", patterns: ["facebook", "metaverse"]),
        BrandRule(name: "WhatsApp", category: "Social", safeReplacement: "messaging app", patterns: ["whatsapp"]),
        BrandRule(name: "Telegram", category: "Social", safeReplacement: "messenger app", patterns: ["telegram"]),
        BrandRule(name: "Disney", category: "Media", safeReplacement: "fairy tale character", patterns: ["disney", "mickey mouse", "disneyland"]),
        BrandRule(name: "Marvel", category: "Media", safeReplacement: "superhero", patterns: ["marvel", "avengers", "spiderman", "iron man"]),
        BrandRule(name: "Lego", category: "Toys", safeReplacement: "plastic building bricks", patterns: ["lego", "lego bricks", "legos"]),
        BrandRule(name: "Starbucks", category: "Food", safeReplacement: "takeaway coffee cup", patterns: ["starbucks", "frappuccino"]),
        BrandRule(name: "McDonald's", category: "Food", safeReplacement: "fast food burger", patterns: ["mcdonald's", "mcdonalds", "big mac", "golden arches"]),
        BrandRule(name: "Coca-Cola", category: "Food", safeReplacement: "cola soda drink", patterns: ["coca-cola", "coca cola", "coke"])
    ]
    
    private init() {}
    
    /// Проверка заголовка и ключевых слов на наличие запрещенных брендов
    public func inspect(title: String, keywords: [String]) -> TrademarkShieldResult {
        var matches: [TrademarkMatch] = []
        var suggestedTitle = title
        var suggestedKeywords: [String] = []
        
        // 1. Проверяем заголовок
        for rule in registeredBrands {
            for pattern in rule.patterns {
                let regexPattern = "\\b\(NSRegularExpression.escapedPattern(for: pattern))\\b"
                if let regex = try? NSRegularExpression(pattern: regexPattern, options: .caseInsensitive) {
                    let range = NSRange(location: 0, length: (suggestedTitle as NSString).length)
                    if regex.firstMatch(in: suggestedTitle, options: [], range: range) != nil {
                        matches.append(TrademarkMatch(
                            brand: rule.name,
                            category: rule.category,
                            replacement: rule.safeReplacement,
                            matchedLocation: "Заголовок"
                        ))
                        // Заменяем в предложенном заголовке
                        suggestedTitle = regex.stringByReplacingMatches(
                            in: suggestedTitle,
                            options: [],
                            range: range,
                            withTemplate: rule.safeReplacement
                        )
                    }
                }
            }
        }
        
        // 2. Проверяем ключевые слова
        for kw in keywords {
            let lowerKw = kw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var matchedRule: BrandRule? = nil
            
            for rule in registeredBrands {
                for pattern in rule.patterns {
                    if lowerKw == pattern || lowerKw.contains(pattern) {
                        matchedRule = rule
                        break
                    }
                }
                if matchedRule != nil { break }
            }
            
            if let rule = matchedRule {
                matches.append(TrademarkMatch(
                    brand: rule.name,
                    category: rule.category,
                    replacement: rule.safeReplacement,
                    matchedLocation: kw
                ))
                // Заменяем на безопасный аналог
                if !suggestedKeywords.contains(rule.safeReplacement) {
                    suggestedKeywords.append(rule.safeReplacement)
                }
            } else {
                if !suggestedKeywords.contains(kw) {
                    suggestedKeywords.append(kw)
                }
            }
        }
        
        // Дедупликация совпадений
        var uniqueMatches: [TrademarkMatch] = []
        var seenKeys = Set<String>()
        for m in matches {
            let key = "\(m.brand)_\(m.matchedLocation)"
            if !seenKeys.contains(key) {
                seenKeys.insert(key)
                uniqueMatches.append(m)
            }
        }
        
        return TrademarkShieldResult(
            hasViolations: !uniqueMatches.isEmpty,
            matches: uniqueMatches,
            suggestedTitle: cleanWhitespace(suggestedTitle),
            suggestedKeywords: suggestedKeywords
        )
    }
    
    private func cleanWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
