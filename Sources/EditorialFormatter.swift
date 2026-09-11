import Foundation

public struct EditorialFormatter: Sendable {
    private static let englishDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "MMMM d, yyyy"
        return df
    }()
    
    /// Форматирует заголовок по строгим международным правилам мировых стоков (Shutterstock, Adobe Stock, Getty)
    /// Формат: CITY, COUNTRY - MONTH DAY, YEAR: Description
    public static func formatTitle(city: String, country: String, date: Date, description: String) -> String {
        let cleanCity = city.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanCountry = country.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let dateString = englishDateFormatter.string(from: date).uppercased()
        
        // Очищаем описание от существующего editorial-префикса, если он уже был
        var cleanDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colonIndex = cleanDesc.firstIndex(of: ":") {
            // Если перед двоеточием были тире или даты
            let prefix = cleanDesc[..<colonIndex]
            if prefix.contains("-") || prefix.contains("202") || prefix.contains("201") {
                cleanDesc = String(cleanDesc[cleanDesc.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        var locationPart = ""
        if !cleanCity.isEmpty && !cleanCountry.isEmpty {
            locationPart = "\(cleanCity), \(cleanCountry)"
        } else if !cleanCity.isEmpty {
            locationPart = cleanCity
        } else if !cleanCountry.isEmpty {
            locationPart = cleanCountry
        } else {
            locationPart = "LOCATION"
        }
        
        if cleanDesc.isEmpty {
            cleanDesc = "Editorial documentary photography"
        }
        
        return "\(locationPart) - \(dateString): \(cleanDesc)"
    }
}
