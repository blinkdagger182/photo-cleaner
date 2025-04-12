import SwiftUI

struct SplashView: View {
    @ObservedObject var viewModel: SplashViewModel
    
    var body: some View {
        ZStack {
            Color.white
            
            VStack {
                Image(systemName: "photo.stack")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.blue)
                
                Text("PhotoCleaner")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 20)
                
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)
                        .padding(.top, 40)
                }
            }
        }
        .onAppear {
            viewModel.loadInitialData()
        }
    }
} 