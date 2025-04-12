import SwiftUI
import Photos

struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "photo.stack")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(.blue)
            
            Text("Welcome to PhotoCleaner")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Clean up your photo library and organize your memories with ease")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            Button(action: viewModel.requestPhotoAccess) {
                Text("Get Started")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            
            if viewModel.showPermissionDenied {
                Text("Photo access is required to use this app")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
    }
} 