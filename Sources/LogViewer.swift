import SwiftUI

struct LogViewer: View {
    @ObservedObject var logger = FTPTranscriptLogger.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var isCopied = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    ScrollViewReader { proxy in
                        Text(logger.getTranscript())
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.green)
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
                        presentationMode.wrappedValue.dismiss()
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
                            .foregroundColor(isCopied ? .green : Color(hex: "7C3AED"))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        logger.clear()
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    LogViewer()
}
