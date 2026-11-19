// Stream screenshots: turns a decoded video frame into a PNG on disk.
#ifndef SCREENSHOT_H
#define SCREENSHOT_H

#include <QImage>
#include <QString>

#include <functional>

struct AVFrame;

namespace Screenshot {

/// Converts a decoded frame (software or hardware) to an 8-bit RGB image.
/// HDR (PQ) frames are tone-mapped to SDR. Returns a null image if the format is unsupported.
QImage frameToImage(const AVFrame *frame, QString *error = nullptr);

/// Folder screenshots are saved to: <Pictures>/Nimbus Remote
QString screenshotDir();

/// Takes ownership of `frame` (a clone), converts and saves it on a worker thread.
/// `done` is called on the worker thread with the saved path, or an empty path and an error.
void saveAsync(AVFrame *frame, std::function<void(const QString &path, const QString &error)> done);

}

#endif
