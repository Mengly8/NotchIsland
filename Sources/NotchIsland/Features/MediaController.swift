import AppKit
import Combine

/// Reads "now playing" from Music, Spotify and YouTube (in Safari / Chrome / Arc / Brave / Edge)
/// via AppleScript and sends playback commands.
///
/// Apple's private MediaRemote framework (what NotchNook-style apps used to rely on) is locked
/// down on recent macOS versions, so this uses the supported, scriptable route instead.
/// macOS asks once per app for permission ("Notch Island wants to control Music").
///
/// YouTube works by running a tiny bit of JavaScript in the YouTube tab. Browsers only allow that
/// after you turn on "Allow JavaScript from Apple Events" (see README).
final class MediaController: ObservableObject {
    enum Source: String, CaseIterable {
        case music = "Music"
        case spotify = "Spotify"
        case safari = "Safari"
        case chrome = "Google Chrome"
        case arc = "Arc"
        case brave = "Brave Browser"
        case edge = "Microsoft Edge"

        var bundleID: String {
            switch self {
            case .music: return "com.apple.Music"
            case .spotify: return "com.spotify.client"
            case .safari: return "com.apple.Safari"
            case .chrome: return "com.google.Chrome"
            case .arc: return "company.thebrowser.Browser"
            case .brave: return "com.brave.Browser"
            case .edge: return "com.microsoft.edgemac"
            }
        }

        var isBrowser: Bool { self != .music && self != .spotify }

        /// Short name for the UI.
        var displayName: String {
            switch self {
            case .music: return "Music"
            case .spotify: return "Spotify"
            case .safari: return "YouTube · Safari"
            case .chrome: return "YouTube · Chrome"
            case .arc: return "YouTube · Arc"
            case .brave: return "YouTube · Brave"
            case .edge: return "YouTube · Edge"
            }
        }

        var symbol: String {
            switch self {
            case .music: return "music.note"
            case .spotify: return "dot.radiowaves.left.and.right"
            default: return "play.rectangle.fill"
            }
        }

        /// Where the "Allow JavaScript from Apple Events" switch lives in each browser.
        var javaScriptSettingPath: String {
            switch self {
            case .safari: return "Safari → Settings → Advanced → tick \"Show features for web developers\", then Develop menu → Allow JavaScript from Apple Events"
            case .arc: return "Arc → View → Developer → Allow JavaScript from Apple Events"
            default: return "\(rawValue) → View → Developer → Allow JavaScript from Apple Events"
            }
        }

        var stateScript: String {
            switch self {
            case .music:
                return """
                tell application "Music"
                    if player state is playing then
                        set ps to "playing"
                    else if player state is paused then
                        set ps to "paused"
                    else
                        return "stopped"
                    end if
                    set t to current track
                    return ps & "||" & (name of t) & "||" & (artist of t) & "||" & (album of t) & "||" & (duration of t) & "||" & (player position)
                end tell
                """
            case .spotify:
                return """
                tell application "Spotify"
                    if player state is playing then
                        set ps to "playing"
                    else if player state is paused then
                        set ps to "paused"
                    else
                        return "stopped"
                    end if
                    set t to current track
                    return ps & "||" & (name of t) & "||" & (artist of t) & "||" & (album of t) & "||" & ((duration of t) / 1000) & "||" & (player position) & "||" & (artwork url of t)
                end tell
                """
            default:
                return BrowserScripts.state(for: self)
            }
        }
    }

    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        var duration: Double
        var source: Source
        /// For YouTube: the tab's address, so controls go to the right tab.
        var tabURL: String?
    }

    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var position: Double = 0
    @Published private(set) var positionDate = Date()
    /// Set when a browser has a YouTube tab but blocks JavaScript from Apple Events.
    @Published private(set) var setupHint: String?

    private let queue = DispatchQueue(label: "NotchIsland.media", qos: .userInitiated)
    private var timer: Timer?
    private var artworkKey: String?
    private var polling = false

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.poll() }
        }
        poll()
    }

    /// Playback position interpolated between polls, for a smooth progress bar.
    func position(at date: Date) -> Double {
        guard let track else { return 0 }
        let p = isPlaying ? position + date.timeIntervalSince(positionDate) : position
        return min(max(p, 0), track.duration)
    }

    // MARK: Controls

    func playPause() {
        isPlaying.toggle()   // optimistic; the next poll corrects it
        send(app: "playpause", js: BrowserScripts.toggleJS)
    }

    func next() { send(app: "next track", js: BrowserScripts.nextJS) }
    func previous() { send(app: "previous track", js: BrowserScripts.previousJS) }

    func openPlayer() {
        let source = track?.source ?? .music
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    private func send(app command: String, js: String) {
        guard let track else { return }
        let source = track.source
        let script: String
        if source.isBrowser {
            guard let tabURL = track.tabURL else { return }
            script = BrowserScripts.action(js, in: source, tabURL: tabURL)
        } else {
            script = "tell application \"\(source.rawValue)\" to \(command)"
        }
        queue.async { [weak self] in
            _ = Self.run(script)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.poll() }
        }
    }

    // MARK: Polling

    private func poll() {
        guard !polling else { return }
        // Only talk to apps that are already running — `tell application` would launch them.
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let sources = Source.allCases.filter { running.contains($0.bundleID) }
        guard !sources.isEmpty else {
            apply(nil)
            if setupHint != nil { setupHint = nil }
            return
        }

        polling = true
        queue.async { [weak self] in
            var best: (Source, [String])?
            var hint: String?
            for source in sources {
                let (output, errorNumber) = Self.runDetailed(source.stateScript)
                if let errorNumber {
                    // -1743 = Automation declined (respect silently); -600/-609/-1712 = app quitting or busy.
                    if source.isBrowser, ![-1743, -600, -609, -1712].contains(errorNumber), hint == nil {
                        hint = "To show YouTube from \(source.rawValue): \(source.javaScriptSettingPath)"
                    }
                    continue
                }
                guard let output, output != "stopped" else { continue }
                let parts = output.components(separatedBy: "||")
                guard parts.count >= 6 else { continue }
                if parts[0] == "playing" { best = (source, parts); break }   // a playing source wins
                if best == nil { best = (source, parts) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.polling = false
                if self.setupHint != hint { self.setupHint = hint }
                self.apply(best)
            }
        }
    }

    private func apply(_ result: (Source, [String])?) {
        guard let result else {
            if track != nil { track = nil; artwork = nil; artworkKey = nil }
            if isPlaying { isPlaying = false }
            return
        }
        let (source, p) = result
        // Handles "1,5" locales and JavaScript's NaN / Infinity (live streams).
        let number = { (s: String) -> Double in
            let d = Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0
            return d.isFinite ? d : 0
        }

        let newTrack = Track(
            title: p[1],
            artist: p[2],
            album: p[3],
            duration: number(p[4]),
            source: source,
            tabURL: source.isBrowser && p.count > 7 ? p[7] : nil
        )
        if newTrack != track { track = newTrack }

        let playing = p[0] == "playing"
        if playing != isPlaying { isPlaying = playing }

        position = number(p[5])
        positionDate = Date()

        let key = "\(source.rawValue)|\(newTrack.title)|\(newTrack.album)"
        if key != artworkKey {
            artworkKey = key
            artwork = nil
            loadArtwork(source: source, url: p.count > 6 ? p[6] : nil, key: key)
        }
    }

    private func loadArtwork(source: Source, url: String?, key: String) {
        let deliver: (NSImage?) -> Void = { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.artworkKey == key else { return }
                self.artwork = image
            }
        }

        if source == .music {
            queue.async {
                let descriptor = Self.descriptor("tell application \"Music\" to get raw data of artwork 1 of current track")
                deliver(descriptor.flatMap { NSImage(data: $0.data) })
            }
            return
        }

        // Spotify artwork URL, or the YouTube thumbnail.
        guard let url, !url.isEmpty, let remote = URL(string: url) else { return deliver(nil) }
        URLSession.shared.dataTask(with: remote) { data, _, _ in
            deliver(data.flatMap { NSImage(data: $0) })
        }.resume()
    }

    // MARK: AppleScript helpers

    private static func descriptor(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        return error == nil ? result : nil
    }

    private static func run(_ source: String) -> String? {
        descriptor(source)?.stringValue
    }

    /// Like `run`, but also reports the AppleScript error number on failure.
    private static func runDetailed(_ source: String) -> (String?, Int?) {
        guard let script = NSAppleScript(source: source) else { return (nil, 0) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            return (nil, error[NSAppleScript.errorNumber] as? Int ?? 0)
        }
        return (result.stringValue, nil)
    }
}

/// AppleScript + JavaScript used to read and control YouTube tabs.
///
/// The JavaScript only uses single quotes so it can sit inside an AppleScript "string".
/// It reads `navigator.mediaSession.metadata`, which YouTube and YouTube Music fill in with the
/// title, channel and thumbnail, falling back to the page title.
enum BrowserScripts {
    static let readJS = "(function(){var v=document.querySelector('video');if(!v||!(v.currentSrc||v.src))return '';var m=navigator.mediaSession&&navigator.mediaSession.metadata;var c=function(s){return String(s||'').split('||').join(' ');};var t=(m&&m.title)||document.title.replace(/ - YouTube( Music)?$/,'');var a=(m&&m.artist)||'';var al=(m&&m.album)||'YouTube';var art='';if(m&&m.artwork&&m.artwork.length){art=m.artwork[m.artwork.length-1].src;}else{var id=new URLSearchParams(location.search).get('v');if(id){art='https://i.ytimg.com/vi/'+id+'/hqdefault.jpg';}}return (v.paused?'paused':'playing')+'||'+c(t)+'||'+c(a)+'||'+c(al)+'||'+v.duration+'||'+v.currentTime+'||'+c(art);})()"

    static let toggleJS = "(function(){var v=document.querySelector('video');if(v){if(v.paused){v.play();}else{v.pause();}}})()"

    static let nextJS = "(function(){var b=document.querySelector('.ytp-next-button')||document.querySelector('ytmusic-player-bar .next-button');if(b){b.click();}})()"

    static let previousJS = "(function(){var v=document.querySelector('video');if(v&&v.currentTime>3){v.currentTime=0;return;}var b=document.querySelector('ytmusic-player-bar .previous-button');if(b){b.click();}else{history.back();}})()"

    /// How each browser runs JavaScript in a tab `t`.
    private static func runJS(_ js: String, browser: MediaController.Source) -> String {
        browser == .safari
            ? "do JavaScript \"\(js)\" in t"
            : "tell t to execute javascript \"\(js)\""
    }

    /// Finds YouTube tabs, prefers one that's playing. Output ends with "||<tab URL>".
    static func state(for browser: MediaController.Source) -> String {
        """
        tell application "\(browser.rawValue)"
            set best to "stopped"
            repeat with w in windows
                set urls to URL of tabs of w
                repeat with i from 1 to count of urls
                    set u to item i of urls
                    if u is missing value then set u to ""
                    if u contains "youtube.com/" then
                        set t to tab i of w
                        set r to \(runJS(readJS, browser: browser))
                        if r is not missing value and r is not "" then
                            set r to r & "||" & u
                            if r starts with "playing" then return r
                            if best is "stopped" then set best to r
                        end if
                    end if
                end repeat
            end repeat
            return best
        end tell
        """
    }

    /// Runs `js` in the tab whose address is `tabURL`.
    static func action(_ js: String, in browser: MediaController.Source, tabURL: String) -> String {
        let safeURL = tabURL
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "\(browser.rawValue)"
            repeat with w in windows
                set urls to URL of tabs of w
                repeat with i from 1 to count of urls
                    if (item i of urls) is "\(safeURL)" then
                        set t to tab i of w
                        \(runJS(js, browser: browser))
                        return "ok"
                    end if
                end repeat
            end repeat
        end tell
        """
    }
}
