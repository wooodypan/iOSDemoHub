Pod::Spec.new do |s|
  s.name         = 'MultiTabController'
  s.version      = '1.0.0'
  s.summary      = '浏览器式多 Tab 的 iOS 分栏容器组件（模仿 VS Code Tab 策略）。'

  s.description  = <<-DESC
MultiTabController 提供一套可复用的 iOS UI 组件，用于构建“左侧分类列表 + 右侧多 Tab 详情宿主”的
分栏界面，并实现了类似 VS Code 的 Tab 复用策略（预览 / 正式 / 固定）。已适配 iPhone、iPad 与
Mac Catalyst：

- RootBuilder：按设备自动选择布局（iPhone 标签栏 / iPad·Mac 分栏根控制器）。
- ArticleListViewController / DetailViewController / DetailHostViewController：列表、详情与右侧多 Tab 宿主。
- ArticleOpenRouting：协议化路由，把“列表点开文章”的意图从具体设备环境中解耦。
- DeviceHelper / WindowManager：设备判断与多窗口（新窗口）能力。

注意：底层的 PPTabBarController 为内部实现类型，未对外公开，请通过 RootBuilder / TabBarBuilder 等入口使用。
DESC

  s.homepage     = 'https://github.com/wooodypan/iOSDemoHub'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  # 作者邮箱请按实际情况修改
  s.author       = { 'wooodypan' => 'wooodypan@example.com' }
  s.source       = { :git => 'https://github.com/wooodypan/iOSDemoHub.git', :tag => s.version.to_s }

  s.platforms        = { :ios => '12.0' }
  s.swift_versions  = ['5.0']

  # 只打包库源码（MultiTabController/MultiTabController/ 下的 swift 文件），
  # 明确排除 App 宿主层（AppDelegate.swift / Info.plist / LaunchScreen / Assets.xcassets）
  # 与参考项目 NewsSplitDemo。
  s.source_files = 'MultiTabController/MultiTabController/MultiTabController/**/*.swift'

  # UIKit 为主；Mac Catalyst 下用到的 AppKit 由系统自动链接，无需在此声明
  s.frameworks   = 'UIKit'
  s.requires_arc = true
end
