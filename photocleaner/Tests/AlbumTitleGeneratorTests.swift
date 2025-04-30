import SwiftUI
import Photos

struct AlbumTitleGeneratorTests: View {
    @State private var generatedTitle = ""
    @State private var location = "KL"
    @State private var timeOfDay = "evening"
    @State private var photoCount = 5
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(generatedTitle)
                    .font(.title2)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(minHeight: 80)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            
            Form {
                Section(header: Text("Inputs")) {
                    TextField("Location", text: $location)
                    
                    Picker("Time of Day", selection: $timeOfDay) {
                        Text("Morning").tag("morning")
                        Text("Afternoon").tag("afternoon")
                        Text("Evening").tag("evening")
                        Text("Night").tag("night")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    Stepper("Photo Count: \(photoCount)", value: $photoCount, in: 1...100)
                }
                
                Section {
                    Button("Generate Title") {
                        generatedTitle = AlbumTitleGenerator.generate(
                            location: location.isEmpty ? nil : location,
                            timeOfDay: timeOfDay,
                            photoCount: photoCount
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(8)
                    
                    Button("Generate Random Title") {
                        // Random location
                        let locations = ["Genting", "KL", "Ampang", "Bangsar", "Mont Kiara", "Bukit Bintang", "Penang", "PJ", "TTDI", "Putrajaya", "Melaka", ""]
                        let randomLocation = locations.randomElement()!
                        
                        // Random time of day
                        let times = ["morning", "afternoon", "evening", "night", ""]
                        let randomTime = times.randomElement()!
                        
                        // Random photo count
                        let randomCount = Int.random(in: 1...20)
                        
                        generatedTitle = AlbumTitleGenerator.generate(
                            location: randomLocation.isEmpty ? nil : randomLocation,
                            timeOfDay: randomTime.isEmpty ? nil : randomTime,
                            photoCount: randomCount
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(8)
                }
                
                Section(header: Text("Test Multiple Generations")) {
                    Button("Generate 5 Sample Titles") {
                        var titles = ""
                        
                        for _ in 1...5 {
                            let randomLocation = Bool.random() ? "KL" : nil
                            let randomTime = Bool.random() ? "evening" : nil
                            let randomCount = Int.random(in: 1...10)
                            
                            let title = AlbumTitleGenerator.generate(
                                location: randomLocation,
                                timeOfDay: randomTime,
                                photoCount: randomCount
                            )
                            
                            titles += "• \(title)\n"
                        }
                        
                        generatedTitle = titles
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(8)
                }
            }
            }
            .padding()
            .navigationTitle("Title Generator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Generate an initial title
                generatedTitle = AlbumTitleGenerator.generate(
                    location: location,
                    timeOfDay: timeOfDay,
                    photoCount: photoCount
                )
            }
        }
    }
}

struct AlbumTitleGeneratorTests_Previews: PreviewProvider {
    static var previews: some View {
        AlbumTitleGeneratorTests()
    }
}
