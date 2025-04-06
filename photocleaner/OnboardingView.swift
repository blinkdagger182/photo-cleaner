struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        VStack(spacing: 32) {
            Text("Welcome to cln.")
                .font(.largeTitle)
                .bold()

            Text("Swipe through your photos and clean up your library easily.")
                .multilineTextAlignment(.center)
                .padding()

            Button("Get Started") {
                hasSeenOnboarding = true
            }
            .font(.headline)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .clipShape(Capsule())
        }
        .padding()
    }
}
