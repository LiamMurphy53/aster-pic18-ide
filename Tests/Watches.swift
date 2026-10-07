import Foundation

@main struct WatchTests {
 static func main() throws {
  let base=URL(fileURLWithPath:CommandLine.arguments[1]), fm=FileManager.default
  let suite="aster-watch-tests-"+UUID().uuidString, defaults=UserDefaults(suiteName:suite)!
  let dir=fm.temporaryDirectory.appendingPathComponent(suite)
  defer {defaults.removePersistentDomain(forName:suite);try? fm.removeItem(at:dir)}
  try fm.createDirectory(at:dir,withIntermediateDirectories:true)
  let a=dir.appendingPathComponent("A.X"), b=dir.appendingPathComponent("B.X")
  for path in [a,b] {try fm.copyItem(at:base.appendingPathComponent("Resources/Template.X"),to:path)}
  let first=try PICProject(a,preferences:defaults), second=try PICProject(b,preferences:defaults)
  precondition(first.savedWatches.isEmpty && second.savedWatches.isEmpty)
  try first.saveWatches(["TMR0H","TMR0L","COUNT","TMR0H"])
  try second.saveWatches(["LATB","TABLAT"])
  let reopened=try PICProject(a,preferences:UserDefaults(suiteName:suite)!)
  precondition(reopened.savedWatches == ["TMR0H","TMR0L","COUNT"])
  precondition(second.savedWatches == ["LATB","TABLAT"])
  precondition(reopened.info()["watches"] as? [String] == reopened.savedWatches)
  let alias=dir.appendingPathComponent("Alias.X")
  try fm.createSymbolicLink(at:alias,withDestinationURL:a)
  let aliased=try PICProject(alias,preferences:defaults)
  precondition(aliased.savedWatches == reopened.savedWatches)
  try reopened.saveWatches([])
  let empty=try PICProject(a,preferences:defaults)
  precondition(empty.savedWatches.isEmpty && second.savedWatches == ["LATB","TABLAT"])
  do {try second.saveWatches(["bad name"]);fatalError("Invalid name accepted")}catch{}
  precondition(second.savedWatches == ["LATB","TABLAT"])
  print("PASS: independent project watches, reopen, ordered deduplication, empty list, canonical paths, invalid names")
 }
}
