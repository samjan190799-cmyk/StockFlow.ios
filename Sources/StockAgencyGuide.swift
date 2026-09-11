import SwiftUI

// MARK: - Stock Agency Guide Model
public struct StockAgencyGuideInfo: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let host: String
    public let protocolType: String
    public let badgeColor: Color
    public let websiteURL: String
    
    // Official App in App Store
    public let hasOfficialApp: Bool
    public let officialAppName: String?
    public let officialAppNote: String
    public let appStoreSearchTerm: String?
    
    // What StockFlow does
    public let stockFlowFeatures: [String]
    
    // What is left for the user on the stock website
    public let userActionSteps: [String]
    
    // Expert Tips
    public let expertTips: [String]
}

// MARK: - Directory of Stock Guides
public struct StockAgencyDirectory: Sendable {
    public static func guide(for id: String) -> StockAgencyGuideInfo {
        switch id {
        case "adobe":
            return StockAgencyGuideInfo(
                id: "adobe",
                name: "Adobe Stock",
                host: "sftp.contributor.adobestock.com",
                protocolType: "SFTP (Порт 22)",
                badgeColor: Color(hex: "FF0000"),
                websiteURL: "https://contributor.adobestock.com/",
                hasOfficialApp: false,
                officialAppName: nil,
                officialAppNote: "У Adobe Stock нет отдельного приложения для авторов в App Store. Сайт contributor.adobestock.com оптимизирован для мобильного Safari на iPhone.".localized,
                appStoreSearchTerm: nil,
                stockFlowFeatures: [
                    "Автоматическая выгрузка по безопасному протоколу SFTP.".localized,
                    "Вшивание метаданных (Title, Description, Keywords) прямо в EXIF/IPTC файла.".localized,
                    "Генерация специализированного файла Adobe Stock CSV.".localized,
                    "Trademark Shield: автоматическое предупреждение о брендах.".localized
                ],
                userActionSteps: [
                    "Откройте contributor.adobestock.com в браузере и перейдите во вкладку «Загруженные файлы» (Uploaded Files).".localized,
                    "Все заголовки и теги, созданные в StockFlow, автоматически распознаются сайтом.".localized,
                    "Прикрепите релиз модели (Model Release), если на снимке есть узнаваемые люди.".localized,
                    "Нажмите синюю кнопку «Отправить на модерацию» (Submit).".localized
                ],
                expertTips: [
                    "Первые 10 ключевых слов имеют наивысший приоритет в поисковой выдаче Adobe Stock. StockFlow автоматически ставит самые важные теги в начало.".localized,
                    "Adobe строго следит за отсутствием логотипов на коммерческих работах.".localized,
                    "Редакционный (Editorial) контент принимается только от авторов с расширенными правами.".localized
                ]
            )
            
        case "shutterstock":
            return StockAgencyGuideInfo(
                id: "shutterstock",
                name: "Shutterstock",
                host: "ftp.shutterstock.com",
                protocolType: "FTPS / FTP",
                badgeColor: Color(hex: "FF6600"),
                websiteURL: "https://submit.shutterstock.com/",
                hasOfficialApp: true,
                officialAppName: "Shutterstock Contributor",
                officialAppNote: "Официальное приложение в App Store. Позволяет отправлять загруженные из StockFlow снимки на модерацию прямо с iPhone!".localized,
                appStoreSearchTerm: "Shutterstock Contributor",
                stockFlowFeatures: [
                    "Пакетная скоростная выгрузка по FTPS/FTP.".localized,
                    "Вшивание IPTC метаданных (Title, Description, Keywords) прямо в файл.".localized,
                    "Авто-подбор 1-2 обязательных категорий Shutterstock по смыслу изображения.".localized,
                    "Генерация официального Shutterstock CSV с категориями и статусом Editorial.".localized,
                    "Поддержка стандартного Editorial-формата [ГОРОД, СТРАНА — ДАТА: Описание].".localized
                ],
                userActionSteps: [
                    "ВАЖНО ПРО КАТЕГОРИИ: Протокол FTP не поддерживает передачу категорий внутри файла (Shutterstock читает по FTP только заголовок и ключевые слова).".localized,
                    "СПОСОБ 1 (Самый быстрый для всех файлов): Нажмите меню «CSV» вверху очереди StockFlow -> скачайте «Shutterstock CSV» и на сайте submit.shutterstock.com нажмите «Upload CSV» — все категории для всех фото заполнятся автоматически!".localized,
                    "СПОСОБ 2: Откройте приложение «Shutterstock Contributor» на iPhone и подтвердите категорию в 1 клик перед отправкой.".localized,
                    "Прикрепите релизы моделей при наличии узнаваемых лиц и нажмите «Отправить» (Submit).".localized
                ],
                expertTips: [
                    "StockFlow автоматически подбирает наиболее релевантные категории Shutterstock и сохраняет их в CSV для пакетного импорта.".localized,
                    "Инспекторы Shutterstock проверяют резкость на 100% зуме — избегайте смазанных кадров и сильного цифрового шума.".localized,
                    "Для репортажного контента используйте встроенный в StockFlow переключатель Editorial.".localized
                ]
            )
            
        case "istock":
            return StockAgencyGuideInfo(
                id: "istock",
                name: "iStock / Getty Images",
                host: "ftp.gettyimages.com",
                protocolType: "FTP ESP",
                badgeColor: Color(hex: "3B82F6"),
                websiteURL: "https://esp.gettyimages.com/",
                hasOfficialApp: true,
                officialAppName: "Contributor by Getty Images",
                officialAppNote: "Официальное приложение в App Store для авторов iStock и Getty. Очень удобно для отправки батчей на iPhone.".localized,
                appStoreSearchTerm: "Contributor by Getty Images",
                stockFlowFeatures: [
                    "Прямая выгрузка на FTP-сервер ESP Getty Images.".localized,
                    "Автоматическое вшивание IPTC ключевых слов и описаний.".localized,
                    "Контроль чистоты метаданных без запрещенных брендов.".localized
                ],
                userActionSteps: [
                    "Откройте приложение «Contributor by Getty» или сайт esp.gettyimages.com.".localized,
                    "Создайте пакет подачи (Submission Batch) и выберите выгруженные файлы.".localized,
                    "Сопоставьте предложенные теги с контролируемым словарем Getty.".localized,
                    "Подтвердите отправку на проверку инспекторам.".localized
                ],
                expertTips: [
                    "Getty Images очень ценит аутентичный, живой лайфстайл-контент без постановочной наигранности.".localized,
                    "Любые видимые логотипы на одежде или технике в коммерческих работах приведут к реджекту.".localized
                ]
            )
            
        case "freepik":
            return StockAgencyGuideInfo(
                id: "freepik",
                name: "Freepik",
                host: "sftp.contributor-ftp.freepik.com",
                protocolType: "SFTP (Порт 22)",
                badgeColor: Color(hex: "0066FF"),
                websiteURL: "https://contributor.freepik.com/",
                hasOfficialApp: false,
                officialAppName: nil,
                officialAppNote: "У Freepik нет мобильного приложения для авторов в App Store. Сабмит файлов осуществляется через мобильный браузер Safari.".localized,
                appStoreSearchTerm: nil,
                stockFlowFeatures: [
                    "Безопасная SFTP выгрузка больших файлов на сервер Freepik.".localized,
                    "Запись ключевых слов и заголовка на английском языке.".localized,
                    "Поддержка массовой синхронизации десятков файлов.".localized
                ],
                userActionSteps: [
                    "Зайдите на contributor.freepik.com в раздел «Files to submit».".localized,
                    "Дождитесь генерации превью сервером Freepik.".localized,
                    "Проверьте автоматически подтянутые из StockFlow теги.".localized,
                    "Нажмите «Send for revision».".localized
                ],
                expertTips: [
                    "Freepik — один из мировых лидеров по объемам скачиваний. Популярны праздничные темы, фоны, еда и бизнес.".localized,
                    "Для первой загрузки требуется пакет от 10 качественных работ.".localized
                ]
            )
            
        case "depositphotos":
            return StockAgencyGuideInfo(
                id: "depositphotos",
                name: "Depositphotos",
                host: "ftp.depositphotos.com",
                protocolType: "FTP",
                badgeColor: Color(hex: "10B981"),
                websiteURL: "https://depositphotos.com/",
                hasOfficialApp: true,
                officialAppName: "Clashot (Depositphotos)",
                officialAppNote: "Мобильная платформа Clashot от Depositphotos для авторов в App Store / кабинет на сайте.".localized,
                appStoreSearchTerm: "Depositphotos",
                stockFlowFeatures: [
                    "Прямая загрузка оригиналов по FTP.".localized,
                    "Чтение IPTC заголовков и тегов без искажений.".localized
                ],
                userActionSteps: [
                    "Откройте личный кабинет автора на depositphotos.com.".localized,
                    "В разделе «Незавершенные» проверьте метаданные.".localized,
                    "Укажите категории и прикрепите релизы моделей при необходимости.".localized,
                    "Отправьте на модерацию инспекторам.".localized
                ],
                expertTips: [
                    "Очень лояльная и быстрая модерация по сравнению с другими стоками.".localized,
                    "Отлично принимаются как коммерческие, так и репортажные кадры.".localized
                ]
            )
            
        case "alamy":
            return StockAgencyGuideInfo(
                id: "alamy",
                name: "Alamy",
                host: "ftp.upload.alamy.com",
                protocolType: "FTP",
                badgeColor: Color(hex: "6B7280"),
                websiteURL: "https://www.alamy.com/contributor/",
                hasOfficialApp: true,
                officialAppName: "Stockimo by Alamy",
                officialAppNote: "Официальное приложение Stockimo в App Store от Alamy для продажи мобильных снимков!".localized,
                appStoreSearchTerm: "Stockimo",
                stockFlowFeatures: [
                    "Загрузка полноразмерных файлов без потерь качества по FTP.".localized,
                    "Вшивание расширенных IPTC метаданных.".localized
                ],
                userActionSteps: [
                    "Перейдите в Alamy Contributor Dashboard.".localized,
                    "Укажите тип лицензии (Commercial или Editorial) для загруженных работ.".localized,
                    "Подтвердите отправку в каталог Alamy.".localized
                ],
                expertTips: [
                    "Alamy не сжимает фото — загружайте снимки максимального разрешения.".localized,
                    "На Alamy одни из самых высоких средних цен за продажу Editorial лицензий в индустрии (до $100+ за продажу).".localized
                ]
            )
            
        case "dreamstime":
            return StockAgencyGuideInfo(
                id: "dreamstime",
                name: "Dreamstime",
                host: "ftp.upload.dreamstime.com",
                protocolType: "FTP",
                badgeColor: Color(hex: "6366F1"),
                websiteURL: "https://www.dreamstime.com/uploadfile",
                hasOfficialApp: true,
                officialAppName: "Dreamstime Companion",
                officialAppNote: "Официальное приложение в App Store для авторов Dreamstime. Управление портфолио и сабмит прямо с iPhone!".localized,
                appStoreSearchTerm: "Dreamstime Companion",
                stockFlowFeatures: [
                    "FTP выгрузка фотографий и векторных превью.".localized,
                    "Генерация CSV-файла для быстрого импорта категорий.".localized
                ],
                userActionSteps: [
                    "Откройте приложение «Dreamstime Companion» или сайт dreamstime.com.".localized,
                    "В разделе «Unfinished Files» выберите выгруженные работы.".localized,
                    "Подтвердите категории и нажмите кнопку «Submit».".localized
                ],
                expertTips: [
                    "Регулярность загрузок на Dreamstime повышает рейтинг автора и процент авторских отчислений.".localized
                ]
            )
            
        case "123rf":
            return StockAgencyGuideInfo(
                id: "123rf",
                name: "123RF",
                host: "ftp.123rf.com",
                protocolType: "FTP",
                badgeColor: Color(hex: "FBBF24"),
                websiteURL: "https://www.123rf.com/contributors/",
                hasOfficialApp: false,
                officialAppName: nil,
                officialAppNote: "Рекомендуется мобильная веб-версия личного кабинета 123rf.com в браузере Safari.".localized,
                appStoreSearchTerm: nil,
                stockFlowFeatures: [
                    "Выгрузка по стабильному FTP-протоколу.".localized,
                    "Автоматическое считывание ключевых слов из файлов.".localized
                ],
                userActionSteps: [
                    "Войдите в Contributor Dashboard на 123rf.com.".localized,
                    "Откройте список свежих загрузок и подтвердите метаданные.".localized,
                    "Нажмите «Отправить на модерацию».".localized
                ],
                expertTips: [
                    "Хорошо продаются изолированные объекты, бизнес-концепты и иллюстрации.".localized
                ]
            )
            
        case "pond5":
            return StockAgencyGuideInfo(
                id: "pond5",
                name: "Pond5",
                host: "ftp.pond5.com",
                protocolType: "FTP",
                badgeColor: Color(hex: "06B6D4"),
                websiteURL: "https://www.pond5.com/my-uploads",
                hasOfficialApp: false,
                officialAppName: nil,
                officialAppNote: "Управление и назначение цен осуществляется в личном кабинете на сайте pond5.com.".localized,
                appStoreSearchTerm: nil,
                stockFlowFeatures: [
                    "Загрузка фото и тяжелых видео 4K / HD по FTP.".localized,
                    "Экспорт специализированного CSV-манифеста Pond5.".localized
                ],
                userActionSteps: [
                    "Зайдите на pond5.com в раздел «My Uploads».".localized,
                    "Укажите свою индивидуальную стоимость в долларах (Pond5 позволяет автору устанавливать любую цену!).".localized,
                    "Отправьте работу на модерацию.".localized
                ],
                expertTips: [
                    "Pond5 — мировой маркетплейс номер 1 для видео и футажей. За видео 4K можно ставить $50–$100 и выше.".localized
                ]
            )
            
        default:
            return StockAgencyGuideInfo(
                id: id,
                name: "Фотосток",
                host: "ftp.example.com",
                protocolType: "FTP",
                badgeColor: .blue,
                websiteURL: "https://google.com",
                hasOfficialApp: false,
                officialAppName: nil,
                officialAppNote: "Управление через веб-сайт агентства.".localized,
                appStoreSearchTerm: nil,
                stockFlowFeatures: [
                    "Автоматическая выгрузка файлов по FTP.".localized,
                    "Вшивание IPTC метаданных.".localized
                ],
                userActionSteps: [
                    "Войдите в личный кабинет автора на сайте стока.".localized,
                    "Проверьте метаданные и нажмите «Отправить».".localized
                ],
                expertTips: [
                    "Следите за качеством и резкостью каждого снимка.".localized
                ]
            )
        }
    }
}

// MARK: - Stock Agency Guide Sheet View
@MainActor
public struct StockAgencyGuideSheet: View {
    public let platformId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    public init(platformId: String) {
        self.platformId = platformId
    }
    
    private var guide: StockAgencyGuideInfo {
        StockAgencyDirectory.guide(for: platformId)
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        
                        // Header Card
                        headerCard
                        
                        // What StockFlow does
                        stockFlowFeaturesCard
                        
                        // What is left for user on website
                        userActionsCard
                        
                        // Official App Store App Card
                        appStoreCard
                        
                        // Expert Tips Card
                        expertTipsCard
                        
                    }
                    .padding()
                }
            }
            .navigationTitle("Гид по стоку".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть".localized) {
                        HapticHelper.trigger(.light)
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .bold))
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [guide.badgeColor, guide.badgeColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                    .shadow(color: guide.badgeColor.opacity(0.35), radius: 8, x: 0, y: 4)
                
                Text(String(guide.name.prefix(2)).uppercased())
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(guide.name)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.primary)
                
                HStack(spacing: 6) {
                    Text(guide.protocolType)
                        .font(.system(size: 10, weight: .heavy))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(guide.badgeColor.opacity(0.18))
                        .foregroundStyle(guide.badgeColor)
                        .clipShape(Capsule())
                    
                    Text(guide.host)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if let url = URL(string: guide.websiteURL) {
                Button(action: {
                    HapticHelper.trigger(.light)
                    openURL(url)
                }) {
                    Image(systemName: "safari.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: "007AFF"))
                        .padding(8)
                        .background(Color(hex: "007AFF").opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(PremiumButtonStyle())
            }
        }
        .glassCard(cornerRadius: 20, padding: 16)
    }
    
    private var stockFlowFeaturesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "bolt.badge.checkmark.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: "10B981"))
                Text("Что делает StockFlow".localized)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color(hex: "10B981"))
                    .textCase(.uppercase)
            }
            
            ForEach(guide.stockFlowFeatures, id: \.self) { feature in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "10B981"))
                        .padding(.top, 1)
                    Text(feature)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .glassCard(cornerRadius: 20, padding: 16)
    }
    
    private var userActionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: "3B82F6"))
                Text("Что вам останется сделать на сайте".localized)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color(hex: "3B82F6"))
                    .textCase(.uppercase)
            }
            
            ForEach(Array(guide.userActionSteps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 9) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "3B82F6").opacity(0.2))
                            .frame(width: 18, height: 18)
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Color(hex: "3B82F6"))
                    }
                    .padding(.top, 1)
                    
                    Text(step)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .glassCard(cornerRadius: 20, padding: 16)
    }
    
    private var appStoreCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "applelogo")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: "A855F7"))
                Text("Официальное приложение в App Store".localized)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color(hex: "A855F7"))
                    .textCase(.uppercase)
            }
            
            if guide.hasOfficialApp, let appName = guide.officialAppName {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [Color(hex: "A855F7"), Color(hex: "7C3AED")], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 44, height: 44)
                        Image(systemName: "app.badge.checkmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appName)
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(.primary)
                        Text(guide.officialAppNote)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                }
                
                if let search = guide.appStoreSearchTerm,
                   let searchURL = URL(string: "https://apps.apple.com/search?term=\(search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                    Button(action: {
                        HapticHelper.trigger(.medium)
                        openURL(searchURL)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.app.fill")
                                .font(.system(size: 12))
                            Text("Найти «\(appName)» в App Store".localized)
                                .font(.system(size: 12, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color(hex: "A855F7").opacity(0.18))
                        .foregroundStyle(Color(hex: "A855F7"))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "A855F7").opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(PremiumButtonStyle())
                }
            } else {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "safari")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                    Text(guide.officialAppNote)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .glassCard(cornerRadius: 20, padding: 16)
    }
    
    private var expertTipsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.orange)
                Text("Советы и секреты стока".localized)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color.orange)
                    .textCase(.uppercase)
            }
            
            ForEach(guide.expertTips, id: \.self) { tip in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.orange)
                        .padding(.top, 2)
                    Text(tip)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .glassCard(cornerRadius: 20, padding: 16)
    }
}
