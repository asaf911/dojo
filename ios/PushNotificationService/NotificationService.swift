import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        if let bestAttemptContent = bestAttemptContent {
            // Handle OneSignal rich notification image
            if let att = request.content.userInfo["att"] as? [String: Any],
               let imageURLString = att["id"] as? String,
               let imageURL = URL(string: imageURLString) {
                downloadImage(from: imageURL) { attachment in
                    if let attachment = attachment {
                        bestAttemptContent.attachments = [attachment]
                        print("OneSignal image attached successfully.")
                    } else {
                        print("Failed to attach OneSignal image.")
                    }
                    contentHandler(bestAttemptContent)
                }
            } else {
                // No image URL found, deliver the notification as-is
                contentHandler(bestAttemptContent)
            }
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    private func downloadImage(from url: URL, completion: @escaping (UNNotificationAttachment?) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { downloadedUrl, response, error in
            if let error = error {
                print("Image download error: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let downloadedUrl = downloadedUrl else {
                print("Downloaded URL is nil.")
                completion(nil)
                return
            }

            do {
                let fileManager = FileManager.default
                let tmpDirectory = fileManager.temporaryDirectory
                let tmpURL = tmpDirectory.appendingPathComponent(url.lastPathComponent)
                try fileManager.moveItem(at: downloadedUrl, to: tmpURL)
                let attachment = try UNNotificationAttachment(identifier: "", url: tmpURL, options: nil)
                print("Image downloaded and attached.")
                completion(attachment)
            } catch {
                print("Failed to create attachment: \(error.localizedDescription)")
                completion(nil)
            }
        }
        task.resume()
    }
}
