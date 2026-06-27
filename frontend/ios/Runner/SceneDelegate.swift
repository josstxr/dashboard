import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
    override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        super.scene(scene, willConnectTo: session, options: connectionOptions)
        
        if let flutterViewController = window?.rootViewController as? FlutterViewController,
           let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.registerChannels(binaryMessenger: flutterViewController.binaryMessenger)
        }
    }

    override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        super.scene(scene, openURLContexts: URLContexts)

        guard let url = URLContexts.first?.url,
              let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            return
        }

        _ = appDelegate.handleWorkoutAction(url: url)
    }
}
