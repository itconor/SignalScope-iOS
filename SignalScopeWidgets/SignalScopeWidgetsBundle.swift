import WidgetKit
import SwiftUI

@main
struct SignalScopeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ChainFaultLiveActivity()
        SignalScopeWidgets()
        SignalScopeWidgetsControl()
    }
}
