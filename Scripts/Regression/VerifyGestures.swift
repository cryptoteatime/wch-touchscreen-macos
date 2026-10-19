import Foundation
import CoreGraphics

@main struct VerifyGestures {
    static func main() throws {
        var checks=0
        func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(),message);checks+=1 }
        func event(_ kind: TouchEvent.Kind,_ ms: UInt64,_ x: Int = 8000,_ y: Int = 4000) -> TouchEvent {
            TouchEvent(kind: kind,contactID:0,rawX:x,rawY:y,timestamp:DispatchTime(uptimeNanoseconds:1_000_000_000+ms*1_000_000))
        }
        let q=DispatchQueue(label:"gesture.verification")
        func make(_ sink: Recorder, hold:Int=30,right:Int=65,up:Int=0,back:Int=0) -> GestureController {
            GestureController(mapperProvider:{CoordinateMapper(displayBounds:CGRect(x:0,y:0,width:1200,height:1920))},
                inputSink:sink,cursorController:Cursor(),timing:GestureTiming(warpToClickDelayMs:0,
                downToUpDelayMs:up,clickToWarpBackDelayMs:back,tapDebounceMs:50,holdToDragMs:hold,
                rightClickHoldMs:right),schedulingQueue:q)
        }
        // Isolated quick tap stays a single left click.
        do {let s=Recorder(), g=make(Recorder());_ = g
            let c=make(s);q.sync{c.handle(event(.down,0));c.handle(event(.up,20))}
            check(s.events == ["Ldown1","Lup1"],"Quick tap must click once")
        }
        // Holding without movement must not left-click before the context menu.
        do {let s=Recorder(),c=make(s)
            q.sync{c.handle(event(.down,0))};Thread.sleep(forTimeInterval:0.05)
            q.sync{check(s.events.isEmpty,"Holding must not emit an early left-down");c.handle(event(.up,90))}
            check(s.events == ["Rdown","Rup"],"Long press emits only a right-click")
        }
        // A medium stationary hold remains a normal click on release.
        do {let s=Recorder(),c=make(s)
            q.sync{c.handle(event(.down,0))};Thread.sleep(forTimeInterval:0.04)
            q.sync{c.handle(event(.up,45))}
            check(s.events == ["Ldown1","Lup1"],"Medium stationary hold is one normal click")
        }
        // Move immediately to scroll, regardless of total duration.
        do {let s=Recorder(),c=make(s)
            q.sync{c.handle(event(.down,0));c.handle(event(.move,10,9000));c.handle(event(.move,80,10000));c.handle(event(.up,100))}
            check(s.events == ["scroll1","scroll2","scroll4"],"Immediate movement must only scroll")
        }
        // Hold then move to drag, even if release passes the right-click duration.
        do {let s=Recorder(),c=make(s)
            q.sync{c.handle(event(.down,0))};Thread.sleep(forTimeInterval:0.04)
            q.sync{c.handle(event(.move,45,9000));c.handle(event(.move,80,10000));c.handle(event(.up,100))}
            check(s.events == ["Ldown1","drag","drag","Lup1"],"Hold-move is drag, never a right-click")
        }
        // Tap, then second contact down/move/up performs a double-click drag.
        do {let s=Recorder(),c=make(s)
            q.sync{c.handle(event(.down,0));c.handle(event(.up,20));c.handle(event(.down,150));c.handle(event(.move,170,9000));c.handle(event(.up,200))}
            check(s.events == ["Ldown1","Lup1","Ldown2","drag","Lup2"],"Double-tap hold carries click count 2 while dragging")
        }
        do {let s=Recorder(),c=make(s)
            q.sync{c.handle(event(.down,0));c.handle(event(.up,20));c.handle(event(.down,150));c.handle(event(.up,170))}
            check(s.events == ["Ldown1","Lup1","Ldown2","Lup2"],"Normal double-tap is preserved")
        }
        // Second press can arrive before the first click's delayed cleanup.
        do {let s=Recorder(),c=make(s,up:25,back:25)
            q.sync{c.handle(event(.down,0));c.handle(event(.up,10));c.handle(event(.down,20));c.handle(event(.up,40))}
            Thread.sleep(forTimeInterval:0.06)
            check(s.events == ["Ldown1","Lup1","Ldown2","Lup2"],"Fast double tap cleans up both button releases")
        }
        // Cancellation before movement/secondary emission must not leak a click.
        do {let s=Recorder(),c=make(s)
            q.sync{c.handle(event(.down,0))};Thread.sleep(forTimeInterval:0.04)
            q.sync{c.forceCancel()};check(s.events.isEmpty,"Cancelling a stationary hold must be click-free")
        }
        // Cancelling a right click releases once; cancelled delayed work stays cancelled.
        do {let s=Recorder(),c=make(s,up:30,back:30)
            q.sync{c.handle(event(.down,0));c.handle(event(.up,90));c.forceCancel()}
            Thread.sleep(forTimeInterval:0.08)
            check(s.events == ["Rdown","Rup"],"Cancelled secondary click has exactly one balanced release")
        }
        do {let s=Recorder(),c=make(s,up:10,back:100)
            q.sync{c.handle(event(.down,0));c.handle(event(.up,90))};Thread.sleep(forTimeInterval:0.04)
            q.sync{c.forceCancel()};Thread.sleep(forTimeInterval:0.11)
            check(s.events == ["Rdown","Rup"],"Cleanup after release must not emit another right-up")
        }
        do {let s=Recorder(),c=make(s)
            c.mayBeginHold={false};q.sync{c.handle(event(.down,0))};Thread.sleep(forTimeInterval:0.04)
            q.sync{c.handle(event(.up,90))};check(s.events.isEmpty,"Untrusted hold cannot create a right-click")
        }
        // Configuration bounds and separation leave a usable drag window.
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        try Data("{\"gesture\":{\"holdToDragMs\":1000,\"rightClickHoldMs\":300}}".utf8).write(to:root)
        let config=DriverConfiguration.load(from:root).configuration
        check(config.gesture.rightClickHoldMs == 1150,"Right hold must leave time to start dragging")
        check(DriverConfiguration.defaults.gesture.rightClickHoldMs == 650,"Default right-click is 650 ms")
        print("Gesture regression scenarios passed: \(checks)")
    }
}
private final class Recorder: SyntheticInputSink {
    var events:[String]=[]
    func postMouseDown(at:CGPoint,clickCount:Int){events.append("Ldown\(clickCount)")}
    func postMouseUp(at:CGPoint,clickCount:Int){events.append("Lup\(clickCount)")}
    func postRightMouseDown(at:CGPoint){events.append("Rdown")}
    func postRightMouseUp(at:CGPoint){events.append("Rup")}
    func postMouseDragged(to:CGPoint){events.append("drag")}
    func postScroll(deltaX:CGFloat,deltaY:CGFloat,phase:SyntheticScrollPhase){events.append("scroll\(phase.rawValue)")}
}
private final class Cursor: CursorController {
    func borrow(warpingTo:CGPoint)->Bool{true}
    func updatePosition(_ point:CGPoint){}
    func returnToOrigin(){}
    func forceShow(){}
}
