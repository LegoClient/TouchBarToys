import AppKit

// Dev modes print diagnostics; keep them unbuffered so nothing is lost on exit.
setvbuf(stdout, nil, _IONBF, 0)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
