import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // ⚠️ DO NOT call FirebaseApp.configure() here!
    // Flutter's firebase_core plugin handles initialization from main.dart
    
    // ✅ NEW: Setup badge clearing method channel
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let badgeChannel = FlutterMethodChannel(name: "com.bariwise/badge",
                                            binaryMessenger: controller.binaryMessenger)
    
    badgeChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      
      if call.method == "clearBadge" {
        // Clear the app badge
        UIApplication.shared.applicationIconBadgeNumber = 0
        result(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })
    
    // Register Flutter plugins
    GeneratedPluginRegistrant.register(with: self)
    
    // 🔔 Request notification permissions (iOS 10+)
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
      UNUserNotificationCenter.current().requestAuthorization(
        options: authOptions,
        completionHandler: { _, _ in }
      )
    } else {
      let settings: UIUserNotificationSettings =
        UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
      application.registerUserNotificationSettings(settings)
    }
    
    application.registerForRemoteNotifications()
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // 🔔 Handle FCM token refresh
  override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    // Pass device token to Firebase (handled automatically by FlutterFire)
  }
  
  override func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("⚠️ Failed to register for remote notifications: \(error)")
  }
}