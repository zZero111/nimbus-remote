// Self-update from GitHub releases (Windows, portable zip builds).
//
// Flow: check the latest release on launch -> download its zip in the background ->
// "Restart & update" on the home screen, or install automatically when the app closes.
// A small PowerShell script waits for the app to exit, copies the new files over the old ones
// and (optionally) starts the app again. Settings live in the registry, so they are untouched.
#ifndef UPDATER_H
#define UPDATER_H

#include <QObject>
#include <QString>

class QNetworkAccessManager;
class QNetworkReply;
class QFile;

class Updater : public QObject
{
	Q_OBJECT
	Q_PROPERTY(QString state READ state NOTIFY changed)            // idle, checking, downloading, ready, error, uptodate, unsupported
	Q_PROPERTY(QString currentVersion READ currentVersion CONSTANT)
	Q_PROPERTY(QString latestVersion READ latestVersion NOTIFY changed)
	Q_PROPERTY(double progress READ progress NOTIFY changed)        // 0..1 while downloading
	Q_PROPERTY(QString error READ error NOTIFY changed)

public:
	explicit Updater(QObject *parent = nullptr);
	~Updater() override;

	QString state() const { return state_; }
	QString currentVersion() const;
	QString latestVersion() const { return latest_tag; }
	double progress() const { return progress_; }
	QString error() const { return error_; }

	/// Asks GitHub for the latest release; downloads it if it's newer than this build.
	Q_INVOKABLE void check();
	/// Installs the downloaded update now and quits; the app starts again afterwards.
	Q_INVOKABLE void installAndRestart();
	/// Called when the app is closing: installs a downloaded update without restarting.
	void installOnExitIfReady();

	/// True if `a` is a newer release tag than `b` (compares every number in the tags in order).
	static bool isNewer(const QString &a, const QString &b);
	/// Only portable packaged builds can update themselves (not a build-tree exe).
	static bool canSelfUpdate();

signals:
	void changed();

private:
	void setState(const QString &s, const QString &err = QString());
	void download(const QString &url, const QString &tag);
	bool launchInstaller(bool restart);

	QNetworkAccessManager *net = nullptr;
	QNetworkReply *reply = nullptr;
	QFile *file = nullptr;
	QString state_ = "idle";
	QString latest_tag;
	QString error_;
	QString zip_path;
	double progress_ = 0.0;
	bool installer_launched = false;
};

#endif
