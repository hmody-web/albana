import UserNotifications

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent =
            request.content.mutableCopy() as? UNMutableNotificationContent

        guard let bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        let userInfo = request.content.userInfo

        var imageString: String?

        if let fcmOptions = userInfo["fcm_options"] as? [String: Any] {
            imageString = fcmOptions["image"] as? String
        }

        if imageString == nil {
            imageString = userInfo["image_url"] as? String
        }

        guard
            let imageString,
            let remoteURL = URL(string: imageString)
        else {
            contentHandler(bestAttemptContent)
            return
        }

        URLSession.shared.downloadTask(with: remoteURL) { location, _, _ in
            guard let location else {
                contentHandler(bestAttemptContent)
                return
            }

            let fileManager = FileManager.default
            let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())

            let extensionName =
                remoteURL.pathExtension.isEmpty
                ? "jpg"
                : remoteURL.pathExtension

            let localURL = tempDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(extensionName)

            do {
                try? fileManager.removeItem(at: localURL)
                try fileManager.moveItem(at: location, to: localURL)

                let attachment = try UNNotificationAttachment(
                    identifier: "notification-image",
                    url: localURL,
                    options: nil
                )

                bestAttemptContent.attachments = [attachment]
            } catch {
                print("Notification image error: \(error)")
            }

            contentHandler(bestAttemptContent)
        }.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler,
           let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}