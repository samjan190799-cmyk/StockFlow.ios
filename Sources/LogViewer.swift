import SwiftUI

struct LogViewer: View {
    @ObservedObject var logger = FTPTranscriptLogger.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isCopied = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0B0D14").ignoresSafeArea()
                
                ScrollView {
                    ScrollViewReader { proxy in
                        Text(logger.getTranscript())
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(AppPalette.green)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .id("Bottom")
                            .onChange(of: logger.logs.count) { _ in
                                withAnimation {
                                    proxy.scrollTo("Bottom", anchor: .bottom)
                                }
                            }
                            .onAppear {
                                proxy.scrollTo("Bottom", anchor: .bottom)
                            }
                    }
                }
            }
            .navigationTitle("FTP Логи".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Закрыть".localized) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        UIPasteboard.general.string = logger.getTranscript()
                        isCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            isCopied = false
                        }
                    }) {
                        Text(isCopied ? "Скопировано!".localized : "Копировать".localized)
                            .bold()
                            .foregroundStyle(isCopied ? AppPalette.green : AppPalette.accentLight)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        logger.clear()
                    }) {
                        Image(systemName: "trash")
                            .foregroundStyle(AppPalette.coral)
                    }
                    .accessibilityLabel("Очистить".localized)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    LogViewer()
}
