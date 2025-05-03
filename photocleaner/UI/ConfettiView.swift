import SwiftUI
import UIKit

struct ConfettiView: UIViewRepresentable {
    @Binding var isActive: Bool
    var colors: [UIColor] = [.systemRed, .systemBlue, .systemGreen, .systemYellow, .systemPurple, .systemOrange]
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        // Create the emitter layer
        let emitterLayer = CAEmitterLayer()
        emitterLayer.emitterPosition = CGPoint(x: view.bounds.width / 2, y: -50)
        emitterLayer.emitterShape = .line
        emitterLayer.emitterSize = CGSize(width: view.bounds.width, height: 1)
        emitterLayer.renderMode = .additive
        
        // Store the emitter layer in the layer property of the view
        view.layer.addSublayer(emitterLayer)
        context.coordinator.emitterLayer = emitterLayer
        context.coordinator.setupEmitterCells()
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Get reference to the emitter layer
        guard let emitterLayer = context.coordinator.emitterLayer else { return }
        
        // Update the emitter position
        emitterLayer.emitterPosition = CGPoint(x: uiView.bounds.width / 2, y: -50)
        emitterLayer.emitterSize = CGSize(width: uiView.bounds.width, height: 1)
        
        // Toggle emission
        if isActive {
            emitterLayer.birthRate = 1.0
        } else {
            emitterLayer.birthRate = 0.0
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: ConfettiView
        var emitterLayer: CAEmitterLayer?
        
        init(_ parent: ConfettiView) {
            self.parent = parent
        }
        
        func setupEmitterCells() {
            guard let emitterLayer = emitterLayer else { return }
            
            var emitterCells: [CAEmitterCell] = []
            
            for color in parent.colors {
                let cell = CAEmitterCell()
                cell.birthRate = 10.0
                cell.lifetime = 7.0
                cell.lifetimeRange = 3.0
                cell.velocity = 200.0
                cell.velocityRange = 100.0
                cell.spin = CGFloat.pi
                cell.spinRange = CGFloat.pi * 2
                cell.emissionRange = CGFloat.pi
                cell.scaleRange = 0.3
                cell.scale = 0.1
                cell.scaleSpeed = -0.03
                cell.alphaRange = 0.5
                cell.alphaSpeed = -0.1
                cell.contents = createConfettiImage(color: color)?.cgImage
                
                emitterCells.append(cell)
            }
            
            emitterLayer.emitterCells = emitterCells
            emitterLayer.birthRate = 0.0 // Start with emission off
        }
        
        private func createConfettiImage(color: UIColor) -> UIImage? {
            let size = CGSize(width: 12, height: 12)
            UIGraphicsBeginImageContextWithOptions(size, false, 0)
            guard let context = UIGraphicsGetCurrentContext() else { return nil }
            
            let rect = CGRect(origin: .zero, size: size)
            context.setFillColor(color.cgColor)
            
            // Randomly create different shapes
            let random = Int.random(in: 0...2)
            
            switch random {
            case 0:
                // Rectangle
                context.fill(rect)
            case 1:
                // Circle
                context.fillEllipse(in: rect)
            case 2:
                // Triangle
                context.move(to: CGPoint(x: size.width/2, y: 0))
                context.addLine(to: CGPoint(x: size.width, y: size.height))
                context.addLine(to: CGPoint(x: 0, y: size.height))
                context.closePath()
                context.fillPath()
            default:
                context.fill(rect)
            }
            
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            return image
        }
    }
} 