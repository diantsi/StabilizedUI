//
//  ContentView.swift
//  Persyk
//
//  Created by Діана Цісарук on 15.12.2025.
//

import SwiftUI
import MetalKit

struct ContentView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 50){
                Text("Try stabilize")
                    .font(.title)
                
                
                NavigationLink(destination: WithoutStabilization()){
                    Text("Without stabilization")
                        .font(.title)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(30)
                        .foregroundColor(Color.white)
                }
                
                NavigationLink(destination: WithStabilization()){
                    Text("With stabilization")
                        .font(.title)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(30)
                        .foregroundColor(Color.white)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

#Preview {
    ContentView()
}
