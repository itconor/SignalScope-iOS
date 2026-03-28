import WidgetKit
import SwiftUI

@main
struct SignalScopeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ChainFaultLiveActivity()
        SignalScopeWidgets()
        if #available(iOS 18.0, *) {
            SignalScopeWidgetsControl()
        }
    }
}
