//
//  Item.swift
//  TestMD
//
//  Created by "Leo" (Dmitry) Kuznetsov on 9/19/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
