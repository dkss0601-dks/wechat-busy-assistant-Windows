import Cocoa

let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
let tile = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 198, yRadius: 198)
NSGradient(colors: [NSColor(red: 0.15, green: 0.72, blue: 0.62, alpha: 1), NSColor(red: 0.16, green: 0.40, blue: 0.54, alpha: 1)])!.draw(in: tile, angle: -55)
NSGraphicsContext.saveGraphicsState(); tile.addClip()
NSColor.white.withAlphaComponent(0.09).setFill()
NSBezierPath(ovalIn: NSRect(x: 400, y: 560, width: 530, height: 530)).fill()
NSGraphicsContext.restoreGraphicsState()
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.12); shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -12)
NSGraphicsContext.saveGraphicsState(); shadow.set()
NSColor.white.setFill()
let bubble = NSBezierPath(roundedRect: NSRect(x: 238, y: 325, width: 548, height: 382), xRadius: 120, yRadius: 120)
let tail = NSBezierPath(); tail.move(to: NSPoint(x: 309, y: 380)); tail.line(to: NSPoint(x: 295, y: 250)); tail.curve(to: NSPoint(x: 438, y: 345), controlPoint1: NSPoint(x: 340, y: 260), controlPoint2: NSPoint(x: 404, y: 323)); tail.close(); bubble.append(tail); bubble.fill()
NSGraphicsContext.restoreGraphicsState()
NSColor(red: 0.15, green: 0.56, blue: 0.52, alpha: 1).setFill()
for x in [365.0, 486.0, 607.0] { NSBezierPath(ovalIn: NSRect(x: x, y: 485, width: 58, height: 58)).fill() }
let star = NSBezierPath(); star.move(to: NSPoint(x: 760, y: 844)); star.curve(to: NSPoint(x: 855, y: 750), controlPoint1: NSPoint(x: 777, y: 773), controlPoint2: NSPoint(x: 788, y: 767)); star.curve(to: NSPoint(x: 760, y: 656), controlPoint1: NSPoint(x: 788, y: 735), controlPoint2: NSPoint(x: 777, y: 721)); star.curve(to: NSPoint(x: 665, y: 750), controlPoint1: NSPoint(x: 743, y: 721), controlPoint2: NSPoint(x: 732, y: 735)); star.curve(to: NSPoint(x: 760, y: 844), controlPoint1: NSPoint(x: 732, y: 767), controlPoint2: NSPoint(x: 743, y: 773)); star.close()
NSColor(red: 0.88, green: 0.98, blue: 0.76, alpha: 1).setFill(); star.fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
