//
//  SignalScopeWidgetsLiveActivity.swift
//  SignalScopeWidgets
//
//  Created by conor ewings on 22/03/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct SignalScopeWidgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct SignalScopeWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SignalScopeWidgetsAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension SignalScopeWidgetsAttributes {
    fileprivate static var preview: SignalScopeWidgetsAttributes {
        SignalScopeWidgetsAttributes(name: "World")
    }
}

extension SignalScopeWidgetsAttributes.ContentState {
    fileprivate static var smiley: SignalScopeWidgetsAttributes.ContentState {
        SignalScopeWidgetsAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: SignalScopeWidgetsAttributes.ContentState {
         SignalScopeWidgetsAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: SignalScopeWidgetsAttributes.preview) {
   SignalScopeWidgetsLiveActivity()
} contentStates: {
    SignalScopeWidgetsAttributes.ContentState.smiley
    SignalScopeWidgetsAttributes.ContentState.starEyes
}
