//
//  WithStabilization.swift
//  Persyk
//
//  Created by Діана Цісарук on 15.12.2025.
//

import SwiftUI
import StabilizedUI

struct WithStabilization : View {
    var body: some View {
        MetalGyroView(
            maxOffset: 0.2,     // Larger range for vehicle movements
            smoothing: 0.0      // Zero smoothing for instant response
        ) {
            VStack(spacing: 50) {
                Text("Текст 1")
                    .font(.title).foregroundColor(.white)
                Text("Текст 2")
                    .font(.title).foregroundColor(.white)
                
            }
        }
    }
}
