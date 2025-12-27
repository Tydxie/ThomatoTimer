//
//  SharedWidgetTypes.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/12/22.
//

#if os(iOS)
import ActivityKit

struct ThomodoroWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var emoji: String
    }
    var name: String
}
#endif
