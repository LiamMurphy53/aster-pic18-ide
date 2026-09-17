import AppKit
let output = URL(fileURLWithPath:CommandLine.arguments[1])
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
for (size,name) in [(16,"icon_16x16.png"),(32,"icon_16x16@2x.png"),(32,"icon_32x32.png"),(64,"icon_32x32@2x.png"),(128,"icon_128x128.png"),(256,"icon_128x128@2x.png"),(256,"icon_256x256.png"),(512,"icon_256x256@2x.png"),(512,"icon_512x512.png"),(1024,"icon_512x512@2x.png")] {
    let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:rep)
    let t=AffineTransform(scale:CGFloat(size)/1024); (t as NSAffineTransform).concat()
    let path=NSBezierPath(roundedRect:NSRect(x:60,y:60,width:904,height:904),xRadius:202,yRadius:202)
    NSGradient(starting:NSColor(calibratedRed:0.055,green:0.086,blue:0.11,alpha:1),ending:NSColor(calibratedRed:0.10,green:0.19,blue:0.20,alpha:1))!.draw(in:path,angle:85)
    NSColor(calibratedRed:0.26,green:0.43,blue:0.39,alpha:0.5).setStroke(); path.lineWidth=3;path.stroke()
    NSColor(calibratedRed:0.61,green:0.92,blue:0.79,alpha:1).setStroke()
    for i in 0..<8 {
        let angle=Double(i)*Double.pi/4, inner:Double=60, outer:Double=i%2==0 ? 240:207
        let line=NSBezierPath();line.move(to:NSPoint(x:512+cos(angle)*inner,y:512+sin(angle)*inner));line.line(to:NSPoint(x:512+cos(angle)*outer,y:512+sin(angle)*outer));line.lineWidth=29;line.lineCapStyle = .round;line.stroke()
    }
    NSColor(calibratedRed:0.61,green:0.92,blue:0.79,alpha:1).setFill()
    NSBezierPath(ovalIn:NSRect(x:490,y:490,width:44,height:44)).fill()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name))
}
func sizeData(_ n: Int) -> Data { var value = UInt32(n).bigEndian; return withUnsafeBytes(of:&value) { Data($0) } }
var chunks = Data()
for (kind,name) in [("ic07","icon_128x128.png"),("ic08","icon_256x256.png"),("ic09","icon_512x512.png"),("ic10","icon_512x512@2x.png"),("ic11","icon_16x16@2x.png"),("ic12","icon_32x32@2x.png")] {
    let bytes = try Data(contentsOf:output.appendingPathComponent(name))
    chunks.append(Data(kind.utf8)); chunks.append(sizeData(bytes.count+8)); chunks.append(bytes)
}
var container = Data("icns".utf8); container.append(sizeData(chunks.count+8)); container.append(chunks)
try container.write(to:output.deletingLastPathComponent().appendingPathComponent("AppIcon.icns"))
