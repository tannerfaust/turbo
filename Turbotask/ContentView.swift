//
//  ContentView.swift
//  Turbotask
//
//  Created by Tanner Fause on 01.04.2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        AppShellView()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(TurboTaskStore.preview)
    }
}
