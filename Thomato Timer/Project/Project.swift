//
//  Project.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/29.
//

import Foundation

struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var emoji: String?
    let createdAt: Date
    
    init(id: UUID = UUID(), name: String, emoji: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.createdAt = createdAt
    }
    
    var displayName: String {
        if let emoji = emoji {
            return "\(emoji) \(name)"
        } else {
            return name
        }
    }
}


struct Milestone {
    let hours: Int
    let emoji: String
    let title: String
    
    static let milestones: [Milestone] = [
        Milestone(hours: 10, emoji: "🌱", title: "First Steps"),
        Milestone(hours: 30, emoji: "🎯", title: "Getting Started"),
        Milestone(hours: 50, emoji: "💪", title: "Building Habits"),
        Milestone(hours: 100, emoji: "🏆", title: "Foundation"),
        Milestone(hours: 500, emoji: "🌟", title: "Proficient"),
        Milestone(hours: 1000, emoji: "👑", title: "Advanced"),
        Milestone(hours: 2000, emoji: "💎", title: "Master")
    ]
    
    static func currentMilestone(for hours: Int) -> Milestone {
        for milestone in milestones.reversed() {
            if hours >= milestone.hours {
                return milestone
            }
        }
        return milestones[0] // Default to first milestone
    }
    
    static func nextMilestone(for hours: Int) -> Milestone? {
        for milestone in milestones {
            if hours < milestone.hours {
                return milestone
            }
        }
        return nil 
    }
}
