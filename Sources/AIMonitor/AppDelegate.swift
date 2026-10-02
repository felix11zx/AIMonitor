import AppKit
import SwiftUI
import AIMonitorCore
import OSLog

@MainActor final class AppDelegate:NSObject,NSApplicationDelegate {
    private let store=MonitorStore()
    private var statusItem:NSStatusItem!
    private var monitor:NSWindow?
    private var settings:NSWindow?
    private let logger=Logger(subsystem:"com.aimonitor.app",category:"windows")
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory)
        let main=NSMenu(),appMenu=NSMenu(),windowMenu=NSMenu(title:"Fenster")
        let appItem=NSMenuItem();appItem.submenu=appMenu;main.addItem(appItem)
        let preferences=NSMenuItem(title:"Einstellungen …",action:#selector(openSettings),keyEquivalent:",");preferences.target=self;appMenu.addItem(preferences)
        appMenu.addItem(.separator());appMenu.addItem(withTitle:"AIMonitor beenden",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let windowItem=NSMenuItem(title:"Fenster",action:nil,keyEquivalent:"");windowItem.submenu=windowMenu;main.addItem(windowItem)
        windowMenu.addItem(withTitle:"Schließen",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w")
        windowMenu.addItem(withTitle:"Minimieren",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m")
        NSApp.mainMenu=main;NSApp.windowsMenu=windowMenu
        statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        statusItem.button?.target=self;statusItem.button?.action=#selector(clicked(_:))
        statusItem.button?.sendAction(on:[.leftMouseUp,.rightMouseUp])
        statusItem.button?.setAccessibilityLabel("AIMonitor")
        store.onStatusChanged={ [weak self] in self?.updateIcon() }
        updateIcon();store.start()
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(woke),name:NSWorkspace.didWakeNotification,object:nil)
        if CommandLine.arguments.contains("--show") { showMonitor() }
    }
    @objc private func clicked(_ sender:Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true { showSettings() }
        else { showMonitor() }
    }
    @objc private func openSettings() { showSettings() }
    @objc private func woke() { store.refresh() }
    private func updateIcon() {
        guard let button=statusItem?.button else { return }
        let symbol=NSImage(systemSymbolName:"sparkles",accessibilityDescription:"AIMonitor")
        symbol?.isTemplate=true;button.image=symbol;button.imagePosition = .imageLeading
        let color:NSColor=store.aggregate == .needsInput ? .systemOrange : store.aggregate == .working ? .systemBlue : .secondaryLabelColor
        button.attributedTitle=NSAttributedString(string:" ●",attributes:[.foregroundColor:color,.font:NSFont.systemFont(ofSize:10)])
        button.toolTip="AIMonitor · "+store.aggregate.label+"\nLinksklick: Monitor · Rechtsklick: Einstellungen"
    }
    func showMonitor() {
        if monitor == nil {
            let view=MonitorView(store:store,openSettings:{ [weak self] in self?.showSettings() })
            monitor=window(title:"AIMonitor",content:NSHostingView(rootView:view),size:NSSize(width:400,height:480),autosave:"AIMonitorMonitor")
            monitor?.minSize=NSSize(width:340,height:360)
        }
        present(monitor!);store.refresh();logger.info("Monitor opened")
    }
    func showSettings() {
        if settings == nil { settings=window(title:"AIMonitor – Einstellungen",content:NSHostingView(rootView:SettingsView(store:store)),size:NSSize(width:480,height:510),autosave:"AIMonitorSettings");settings?.styleMask.remove(.resizable) }
        present(settings!);logger.info("Settings opened")
    }
    private func window(title:String,content:NSView,size:NSSize,autosave:String)->NSWindow {
        let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title=title;window.contentView=content;window.isReleasedWhenClosed=false
        window.setFrameAutosaveName(autosave)
        if !window.setFrameUsingName(autosave) { window.center() }
        if let screen=NSScreen.main { var frame=window.frame;frame.size.width=min(frame.width,screen.visibleFrame.width);frame.size.height=min(frame.height,screen.visibleFrame.height);window.setFrame(frame,display:false) }
        return window
    }
    private func present(_ window:NSWindow) { window.deminiaturize(nil);window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true) }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool { showMonitor();return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { false }
    func applicationWillTerminate(_ notification:Notification) { store.stop();NSWorkspace.shared.notificationCenter.removeObserver(self) }
}
