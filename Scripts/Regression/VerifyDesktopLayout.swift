import CoreGraphics
import Foundation
@main struct VerifyDesktopLayout {
 static func main() throws {
  var n = 0
  func check(_ condition: @autoclosure () -> Bool, _ reason: String) { precondition(condition(), reason); n += 1 }
  func screen(_ uuid: String, _ id: UInt32, _ serial: UInt32, _ x: Int, builtIn: Bool = false) -> DesktopScreen {
   DesktopScreen(uuid: uuid, vendor: builtIn ? 1552 : 19083, model: builtIn ? 1 : 8704, serial: serial, builtIn: builtIn,
     frame: CGRect(x:x,y:0,width:builtIn ? 1512:1050,height:builtIn ? 982:1680), rotation: builtIn ? 0:(serial == 0 ? 90:270),
     width:builtIn ? 1512:1050,height:builtIn ? 982:1680,pixelWidth:builtIn ? 3024:1050,pixelHeight:builtIn ? 1964:1680,refreshRate:60,runtimeID:id)
  }
  let main = screen("mac",1,42,0,builtIn:true), left = screen("left",3,0,-1050), right = screen("right",13,26,1512)
  let win = DesktopWindow(bundleID:"com.example.app",pid:100,launchedAt:123456,windowID:20,screenUUID:"right",frame:CGRect(x:1600,y:100,width:900,height:1200))
  let layout = DesktopLayout(screens:[main,left,right],windows:[win])
  check(layout.isValid,"Working layout valid")
  let decoded = try JSONDecoder().decode(DesktopLayout.self,from:JSONEncoder().encode(layout))
  check(decoded == layout,"Layout persistence preserves geometry and process incarnation")
  var newLeft = left; newLeft.runtimeID = 30
  var newRight = right; newRight.runtimeID = 99; newRight.uuid = "displaylink-recreated"
  let reconnected = [newRight,main,newLeft]
  let matches = layout.matches(reconnected)!
  check(matches["left"]?.runtimeID == 30,"Reconnect matches changed runtime ID")
  check(matches["right"]?.runtimeID == 99,"Unique hardware fallback matches recreated DisplayLink UUID")
  check(!layout.needsExternalDisplayRestore(matches:matches),"Restored geometry does not trigger repeated display writes")
  var defaultOrigin = newLeft; defaultOrigin.frame.origin.y = 400
  check(layout.needsExternalDisplayRestore(matches:layout.matches([main,defaultOrigin,newRight])!),"A late macOS origin reset is detected")
  var defaultRotation = newRight; defaultRotation.rotation = 0
  check(layout.needsExternalDisplayRestore(matches:layout.matches([main,newLeft,defaultRotation])!),"A late rotation reset is detected")
  var defaultScale = newRight; defaultScale.pixelWidth *= 2
  check(layout.needsExternalDisplayRestore(matches:layout.matches([main,newLeft,defaultScale])!),"A late scaling reset is detected")
  var newMainRefresh = main; newMainRefresh.refreshRate = 120
  check(!layout.needsExternalDisplayRestore(matches:layout.matches([newMainRefresh,newLeft,newRight])!),"The built-in refresh rate stays under user control")
  check(layout.matches([main,left]) == nil,"One late monitor cannot trigger restoration")
  check(layout.matches([main]) == nil,"Undocked topology cannot replace docked profile")
  var imposter = right; imposter.uuid = "other"; imposter.serial = 27
  check(layout.matches([main,left,imposter]) == nil,"Different monitor is not guessed")
  var duplicate = newLeft; duplicate.uuid = "duplicate"; duplicate.runtimeID = 21
  var missingUUIDLeft = left; missingUUIDLeft.uuid = "old-left"
  let ambiguous = DesktopLayout(screens:[main,missingUUIDLeft,right],windows:[])
  check(ambiguous.matches([main,newLeft,duplicate]) == nil,"Ambiguous controllers never match")
  check(layout.matches([main,left,right,duplicate]) == nil,"Unexpected extra monitor pauses restoration")
  var largerMain = main; largerMain.frame.size.width = 1800
  let shiftedMatches = layout.matches([largerMain,left,right])!
  check(layout.targetOrigin(for:right,matches:shiftedMatches).x == 1800,"Right screen follows current MacBook width without changing built-in mode")
  check(layout.targetOrigin(for:left,matches:shiftedMatches).x == -1050,"Left display stays against left edge")
  var shiftedRight = right; shiftedRight.frame.origin.x = 1800
  let target = layout.targetFrame(for:win,matches:layout.matches([largerMain,left,shiftedRight])!)!
  check(target.minX == 1888 && target.size == win.frame.size,"Window retains screen-relative position")
  var huge = win; huge.frame = CGRect(x:1400,y:-300,width:4000,height:4000)
  let clamped = layout.targetFrame(for:huge,matches:matches)!
  check(right.frame.contains(clamped),"Offscreen oversized windows are kept reachable")
  var newProcess = win; newProcess.launchedAt += 1
  check(newProcess.key != win.key,"Reused PID cannot match an old process")
  var changedWindow = win; changedWindow.windowID += 1
  check(changedWindow.key != win.key,"Different window does not inherit saved position")
  var policy = DesktopLayoutPolicy(hasSavedLayout:true)
  check(policy.action(hasLayout:true,completeMatch:false,canLearn:false) == .wait,"Startup undocked waits")
  check(policy.action(hasLayout:true,completeMatch:true,canLearn:true) == .restore,"Complete reconnect restores before learning")
  policy.restored()
  check(policy.action(hasLayout:true,completeMatch:true,canLearn:true) == .capture,"Stable connected changes are learned")
  policy.membershipChanged()
  check(policy.action(hasLayout:true,completeMatch:false,canLearn:true) == .wait,"Disconnect freezes even if an external is still present")
  check(policy.action(hasLayout:true,completeMatch:true,canLearn:true) == .restore,"Late second display resumes restoration")
  for _ in 0..<3 { policy.restoreFailed() }
  check(policy.action(hasLayout:true,completeMatch:true,canLearn:true) == .wait && policy.failed,"Failed restore never overwrites good snapshot")
  policy.membershipChanged()
  check(policy.action(hasLayout:true,completeMatch:true,canLearn:true) == .restore,"New reconnect permits bounded retry")
  var initial = DesktopLayoutPolicy(hasSavedLayout:false)
  check(initial.action(hasLayout:false,completeMatch:false,canLearn:false) == .wait,"First launch waits for full hardware")
  check(initial.action(hasLayout:false,completeMatch:false,canLearn:true) == .capture,"First complete topology is learned")
  var invalid = layout; invalid.screens[1].rotation = 45
  check(!invalid.isValid,"Reject invalid rotations")
  invalid = layout; invalid.windows.append(win)
  check(!invalid.isValid,"Reject duplicate window records")
  invalid = layout; invalid.screens[1].frame.origin.x = .infinity
  check(!invalid.isValid,"Reject nonfinite coordinates")
  if CommandLine.arguments.count > 1 {
   let seed = try JSONDecoder().decode(DesktopLayout.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
   check(seed.isValid && seed.screens.count == 3, "Seeded real display profile decodes and validates")
  }
  print("PASS: \(n) desktop layout regression checks")
 }
}
