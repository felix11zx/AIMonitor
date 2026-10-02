import SwiftUI
import AIMonitorCore

extension AgentStatus {
    var color: Color { switch self { case .idle,.unknown: return .secondary;case .working:return .blue;case .needsInput:return .orange } }
    var symbol: String { switch self { case .idle:return "pause.circle";case .working:return "sparkle";case .needsInput:return "hand.raised";case .unknown:return "questionmark.circle" } }
}

struct MonitorView: View {
    @ObservedObject var store:MonitorStore
    var openSettings:()->Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:10) {
                Image(systemName:"sparkles").font(.system(size:24,weight:.medium)).foregroundStyle(.blue)
                VStack(alignment:.leading,spacing:3) {
                    Text("Codex").font(.title3.weight(.semibold))
                    Label(store.aggregate.label,systemImage:store.aggregate.symbol).font(.caption).foregroundStyle(store.aggregate.color)
                }
                Spacer()
                Button(action:{store.refresh()}) { Image(systemName:"arrow.clockwise") }.buttonStyle(.borderless).disabled(store.isRefreshing).help("Limits aktualisieren").accessibilityLabel("Limits aktualisieren")
                Button(action:openSettings) { Image(systemName:"gearshape") }.buttonStyle(.borderless).help("Einstellungen").accessibilityLabel("Einstellungen")
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    VStack(alignment:.leading,spacing:10) {
                        HStack {
                            Text("VERFÜGBARE NUTZUNG").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            if store.isRefreshing { ProgressView().controlSize(.mini) }
                        }
                        if store.windows.isEmpty {
                            VStack(alignment:.leading,spacing:8) {
                                Text(store.isRefreshing ? "Limits werden geladen …" : "Keine Limits verfügbar").font(.headline)
                                Text(store.limitError ?? "Deine vorhandene Codex-Anmeldung wird verwendet.").font(.caption).foregroundStyle(.secondary)
                            }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary,in:RoundedRectangle(cornerRadius:12))
                        } else {
                            ForEach(store.windows) { window in LimitRow(window:window,reduceMotion:reduceMotion) }
                            if let error=store.limitError { Label(error,systemImage:"exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
                        }
                    }
                    VStack(alignment:.leading,spacing:10) {
                        HStack {
                            Text("AGENTS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Text("Desktop · CLI").font(.caption2).foregroundStyle(.tertiary)
                        }
                        if let error=store.catalogError { Label(error,systemImage:"exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
                        if store.agents.isEmpty { Text("Noch keine Codex-Sessions gefunden.").font(.callout).foregroundStyle(.secondary).padding(.vertical,8) }
                        ForEach(store.visibleAgents) { agent in
                            let status=store.statuses[agent.id] ?? .unknown
                            HStack(alignment:.top,spacing:10) {
                                Circle().fill(status.color).frame(width:7,height:7).padding(.top,6)
                                VStack(alignment:.leading,spacing:4) {
                                    Text(agent.title).font(.callout.weight(.medium)).lineLimit(2)
                                    HStack(spacing:5) { Text(agent.source);Text("·");Text(status.label).foregroundStyle(status.color) }.font(.caption)
                                }
                                Spacer(minLength:8)
                                Image(systemName:agent.source == "CLI" ? "terminal" : "macwindow").font(.caption).foregroundStyle(.tertiary).padding(.top,3)
                            }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary.opacity(0.65),in:RoundedRectangle(cornerRadius:10))
                            .accessibilityElement(children:.combine)
                            .animation(reduceMotion ? nil : .easeInOut(duration:0.2),value:status)
                        }
                        if !store.cliEnabled {
                            Button("CLI-Status vollständig anbinden …",action:openSettings).font(.caption).buttonStyle(.link)
                        }
                    }
                }.padding(20)
            }
            Divider()
            HStack(spacing:6) {
                Circle().fill(store.desktopConnected ? Color.green : Color.secondary).frame(width:5,height:5)
                Text(store.desktopConnected ? "Desktop verbunden" : "Desktop nicht verbunden").lineLimit(1)
                Spacer(minLength:4)
                if let date=store.lastRefresh { Text(date,format:.dateTime.hour().minute().second()).monospacedDigit().help("Letzter erfolgreicher Limit-Abruf") }
            }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal,16).padding(.vertical,11)
        }.frame(minWidth:340,minHeight:360).background(.background)
    }
}

private struct LimitRow: View {
    let window:UsageWindow
    let reduceMotion:Bool
    var tint:Color { (window.remainingPercent ?? 100) <= 15 ? .orange : .blue }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(alignment:.firstTextBaseline) {
                VStack(alignment:.leading,spacing:3) {
                    Text(window.period).font(.callout.weight(.medium))
                    Text(window.bucket == "codex" ? "Codex" : window.bucket).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if let remaining=window.remainingPercent {
                    HStack(alignment:.firstTextBaseline,spacing:3) { Text(remaining,format:.number.precision(.fractionLength(0))).font(.system(size:28,weight:.semibold,design:.rounded));Text("%").font(.callout).foregroundStyle(.secondary) }.foregroundStyle(tint)
                } else { Text("—").font(.title2).foregroundStyle(.secondary) }
            }
            if let remaining=window.remainingPercent {
                ProgressView(value:remaining,total:100).tint(tint).animation(reduceMotion ? nil : .easeInOut(duration:0.2),value:remaining)
                Text("\(Int(window.usedPercent ?? 0)) % verbraucht").font(.caption2).foregroundStyle(.secondary)
            } else { Text("Nutzungswert nicht verfügbar").font(.caption).foregroundStyle(.secondary) }
            if let reset=window.resetAt {
                TimelineView(.periodic(from:.now,by:1)) { timeline in
                    HStack {
                        Label(reset.formatted(.dateTime.weekday(.abbreviated).hour().minute()),systemImage:"clock").lineLimit(1)
                        Spacer()
                        Text(countdown(reset.timeIntervalSince(timeline.date))).monospacedDigit()
                    }.font(.caption2).foregroundStyle(.secondary)
                }
            } else { Text("Reset-Zeit nicht verfügbar").font(.caption2).foregroundStyle(.secondary) }
        }.padding(16).background(.quaternary.opacity(0.55),in:RoundedRectangle(cornerRadius:12))
        .accessibilityElement(children:.combine)
    }
    private func countdown(_ remaining:TimeInterval)->String {
        guard remaining > 0 else { return "Reset wird geprüft …" }
        let seconds=Int(remaining),days=seconds/86400,hours=(seconds%86400)/3600,minutes=(seconds%3600)/60
        if days > 0 { return "in \(days) T \(hours) Std" }
        if hours > 0 { return "in \(hours) Std \(minutes) Min" }
        return String(format:"in %02d:%02d",minutes,seconds%60)
    }
}
