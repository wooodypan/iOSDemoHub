import Foundation
import ObjectiveC

// MARK: - CatalystKeyInterceptor
// Mac Catalyst 下拦截键盘快捷键的“底层兜底”工具。
//
// 为什么需要它？（这是 ⌘W 拦不住的根因）
//   ⌘W 在 Catalyst 下不是普通按键事件，而是系统主菜单里 “Close Window” 的
//   **按键等价（key equivalent）**：AppKit 在 NSWindow 上直接执行 performClose:。
//   这条路径比 UIKit 的 UIKeyCommand 优先级更高，所以：
//     - 只加 UIKeyCommand       → 根本收不到事件；
//     - 只删菜单项（buildMenu） → 系统在某些情况下仍会兜底执行 performClose:。
//   苹果在 WWDC《Key Event Handling in Cocoa Applications》里给过答案：
//   想在“常规按键等价处理之前”做自己的事，可以重写 NSApplication/NSWindow 的 sendEvent，
//   **或者装一个 NSEvent 本地事件监听**。这里选后者，对 UIKit 侵入最小。
//
// 为什么用 NSClassFromString 而不是直接调用 NSEvent？
//   Catalyst 工程不能 import AppKit（头文件不可见），但 AppKit 在运行时确实已加载。
//   所以参考 Dynamic（https://github.com/mhdhejazi/Dynamic）的套路：
//   拿类名 → 拿选择器 → 拿函数指针(IMP) → unsafeBitCast 成 C 函数直接调。
//
// 整个实现只在 Mac Catalyst 下编译；iOS / iPadOS 下这个文件是空的，
// 那边由 UIKeyCommand 负责。
#if targetEnvironment(macCatalyst)

/// Mac Catalyst 下的本地键盘事件拦截器。
/// 用法：创建一个实例并**强持有**它（实例释放 = 自动解除监听）。
public final class CatalystKeyInterceptor {

    // NSEventTypeKeyDown = 10，监听掩码是对应位：1 << 10
    private static let keyDownEventMask: UInt64 = UInt64(1) << 10
    // NSEventModifierFlagCommand = 1 << 20
    private static let commandModifierFlag: UInt = UInt(1) << 20

    /// 拦截回调。
    /// - Parameter event: 拿到的 NSEvent（类型写成 AnyObject，因为 Catalyst 下不能 import AppKit）。
    /// - Returns: true 表示“这个按键我处理了，请把它吞掉，不要再传给 AppKit”；
    ///            false 表示“我不处理，按系统默认行为走”。
    /// - 注意：这个闭包会被本类长期持有，请自行用 weak 捕获外部对象，避免循环引用。
    public typealias Handler = (_ event: AnyObject) -> Bool

    // MARK: 全局注册表

    // NSEvent 的监听回调是一个 ObjC block。Swift 里只有**不捕获任何上下文**的闭包
    // 才能转成 @convention(block)（捕获了上下文的闭包会被当成 @noescape，
    // AppKit 把它存起来之后再调用就会崩：“closure passed as @noescape has escaped”）。
    // 所以这里用一个全局注册表：block 本身不捕获任何东西，只负责转发给静态函数，
    // 由静态函数去表里找到真正要执行的 handler。
    private static var handlers: [Int: Handler] = [:]
    private static var nextHandlerID = 0
    // 全局只装一个监听（装多个的话同一个事件会被处理多次，可能重复关 Tab）。
    private static var monitorToken: AnyObject?

    // 不捕获上下文的 block：遍历注册表，只要有一个 handler 说“我处理了”，就吞掉事件。
    private static let monitorBlock: @convention(block) (AnyObject) -> AnyObject? = { event in
        // 先拷贝一份快照：handler 里可能会创建/销毁拦截器，边遍历边改字典会崩。
        let snapshot = Array(CatalystKeyInterceptor.handlers.values)
        for handler in snapshot {
            if handler(event) {
                // 返回 nil = 吞掉事件，AppKit 不会再处理（也就不会触发 ⌘W 关窗口）。
                return nil
            }
        }
        // 没人处理：原样返回，走系统默认行为。
        return event
    }

    private let handler: Handler
    private var handlerID: Int = -1

    /// - Parameter handler: 见 Handler 说明。闭包里请自行用 weak 避免循环引用。
    public init(handler: @escaping Handler) {
        self.handler = handler
        registerHandler()
    }

    deinit {
        unregisterHandler()
    }

    // MARK: - 注册 / 注销

    private func registerHandler() {
        handlerID = CatalystKeyInterceptor.nextHandlerID
        CatalystKeyInterceptor.nextHandlerID += 1
        CatalystKeyInterceptor.handlers[handlerID] = handler
        // 第一个拦截器出现时才真正去装监听，之后复用同一个。
        if CatalystKeyInterceptor.monitorToken == nil {
            CatalystKeyInterceptor.monitorToken = CatalystKeyInterceptor.addLocalMonitor()
        }
    }

    private func unregisterHandler() {
        guard handlerID >= 0 else { return }
        CatalystKeyInterceptor.handlers.removeValue(forKey: handlerID)
        handlerID = -1
        // 没人再需要监听了才真正移除。
        if CatalystKeyInterceptor.handlers.isEmpty {
            CatalystKeyInterceptor.removeLocalMonitor()
        }
    }

    // MARK: - 装 / 卸 NSEvent 监听（Dynamic 式动态调用）

    private static func addLocalMonitor() -> AnyObject? {
        // 第 1 步：运行时拿到 AppKit 的 NSEvent 类。
        guard let eventClass = NSClassFromString("NSEvent") else { return nil }
        let selector = NSSelectorFromString("addLocalMonitorForEventsMatchingMask:handler:")

        // 第 2 步：要调的是**类方法**，类方法存在元类（metaclass）上，
        // 所以要在类对象上再取一次 class 才拿得到类方法的实现。
        guard let metaclass = object_getClass(eventClass) else { return nil }
        let implementation = class_getMethodImplementation(metaclass, selector)
        guard implementation != nil else { return nil }

        // 第 3 步：把 C 函数指针（IMP）转成 Swift 能直接调用的 C 函数类型。
        // 第 4 个参数是 ObjC block，用 @convention(block) 表示。
        typealias AddLocalMonitor = @convention(c) (
            AnyClass,                                       // 消息接收者：NSEvent 类对象
            Selector,                                       // addLocalMonitorForEventsMatchingMask:handler:
            UInt64,                                         // 要监听的事件掩码（这里只听 keyDown）
            @convention(block) (AnyObject) -> AnyObject?    // 回调 block
        ) -> AnyObject?                                     // 返回监听 token（要强持有）

        let addLocalMonitor = unsafeBitCast(implementation, to: AddLocalMonitor.self)

        // 第 4 步：装上监听。注意传的是上面那个**不捕获上下文**的静态 block。
        return addLocalMonitor(eventClass, selector, keyDownEventMask, monitorBlock)
    }

    private static func removeLocalMonitor() {
        guard let token = monitorToken else { return }
        monitorToken = nil

        guard let eventClass = NSClassFromString("NSEvent") else { return }
        let selector = NSSelectorFromString("removeMonitor:")
        guard let metaclass = object_getClass(eventClass) else { return }
        let implementation = class_getMethodImplementation(metaclass, selector)
        guard implementation != nil else { return }

        // NSEvent.removeMonitor(_:)：把 token 传回去即可解除监听。
        typealias RemoveMonitor = @convention(c) (AnyClass, Selector, AnyObject) -> Void
        let removeMonitor = unsafeBitCast(implementation, to: RemoveMonitor.self)
        removeMonitor(eventClass, selector, token)
    }

    // MARK: - 读取 NSEvent 的信息（不能 import AppKit，只能用 KVC 取值）

    /// 事件上的修饰键（Command / Shift / Option ...），对应 AppKit 的 NSEvent.modifierFlags。
    public static func modifierFlags(of event: AnyObject) -> UInt {
        // NSEvent 是 NSObject 子类，value(forKey:) 可以直接读它的只读属性。
        let number = (event as? NSObject)?.value(forKey: "modifierFlags") as? NSNumber
        return number?.uintValue ?? 0
    }

    /// 是否按住了 Command 键。
    public static func isCommandKeyPressed(in event: AnyObject) -> Bool {
        // 按位与：Command 那一位是 1 就说明按住了 Command。
        return modifierFlags(of: event) & CatalystKeyInterceptor.commandModifierFlag != 0
    }

    /// 忽略修饰键之后的字符。⌘W 得到的就是 "w"（取的是键帽上的字母，与键盘布局无关）。
    public static func charactersIgnoringModifiers(in event: AnyObject) -> String? {
        return (event as? NSObject)?.value(forKey: "charactersIgnoringModifiers") as? String
    }

    /// 判断是不是 “Command + 某个字母键”（不区分大小写）。
    /// - Parameter character: 要匹配的字母，例如 "w" 表示判断 ⌘W。
    public static func isCommandPressed(with character: String, in event: AnyObject) -> Bool {
        guard isCommandKeyPressed(in: event) else { return false }
        guard let characters = charactersIgnoringModifiers(in: event), !characters.isEmpty else {
            return false
        }
        return characters.lowercased() == character.lowercased()
    }
}

#endif
