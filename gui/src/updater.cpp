#include "updater.h"
#include "appinfo.h"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>

Q_LOGGING_CATEGORY(nimbusUpdate, "nimbus.update")

namespace {

QString updateDir()
{
	return QDir(QDir::tempPath()).filePath("NimbusRemoteUpdate");
}

QNetworkRequest githubRequest(const QUrl &url)
{
	QNetworkRequest req(url);
	req.setRawHeader("User-Agent", "NimbusRemote-Updater");
	req.setRawHeader("Accept", "application/vnd.github+json");
	req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
	req.setTransferTimeout(30000);
	return req;
}

// Waits for the app to exit, copies the new files over the old ones, optionally restarts it.
// Logs to install.log next to the downloaded zip.
const char *installer_script = R"PS(
param([int]$AppPid, [string]$Zip, [string]$AppDir, [int]$Restart)
$ErrorActionPreference = 'Stop'
$work = Split-Path -Parent $Zip
$log = Join-Path $work 'install.log'
function Log($m) { Add-Content -LiteralPath $log -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) }
try {
    Log "update: waiting for process $AppPid"
    try { Wait-Process -Id $AppPid -Timeout 90 -ErrorAction Stop } catch { }
    $extract = Join-Path $work 'extract'
    if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
    Log "update: extracting $Zip"
    Expand-Archive -LiteralPath $Zip -DestinationPath $extract -Force
    $src = Join-Path $extract 'NimbusRemote'
    if (-not (Test-Path -LiteralPath (Join-Path $src 'chiaki.exe'))) { $src = $extract }
    if (-not (Test-Path -LiteralPath (Join-Path $src 'chiaki.exe'))) { throw 'chiaki.exe not found in the update' }
    $ok = $false
    for ($i = 0; $i -lt 15 -and -not $ok; $i++) {
        try { Copy-Item -Path (Join-Path $src '*') -Destination $AppDir -Recurse -Force -ErrorAction Stop; $ok = $true }
        catch { Log "update: copy attempt $($i + 1) failed: $($_.Exception.Message)"; Start-Sleep -Seconds 1 }
    }
    if (-not $ok) { throw 'could not replace the app files' }
    Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Zip -Force -ErrorAction SilentlyContinue
    Log "update: installed into $AppDir"
} catch {
    Log "update: FAILED: $($_.Exception.Message)"
}
if ($Restart -eq 1) { Start-Process -FilePath (Join-Path $AppDir 'chiaki.exe') -WorkingDirectory $AppDir }
)PS";

}

Updater::Updater(QObject *parent)
	: QObject(parent),
	net(new QNetworkAccessManager(this))
{
	if(!canSelfUpdate() && !canNotifyOnly())
		state_ = "unsupported";
}

bool Updater::canNotifyOnly()
{
#ifdef Q_OS_MACOS
	return !qEnvironmentVariableIsSet("NIMBUS_NO_UPDATE");
#else
	return false;
#endif
}

void Updater::openReleasePage()
{
	QDesktopServices::openUrl(QUrl(release_url.isEmpty()
		? QStringLiteral("https://github.com/%1/releases/latest").arg(APP_UPDATE_REPO)
		: release_url));
}

Updater::~Updater()
{
	if(reply)
		reply->abort();
}

QString Updater::currentVersion() const
{
	return QStringLiteral(APP_RELEASE_TAG);
}

bool Updater::isNewer(const QString &a, const QString &b)
{
	static const QRegularExpression num("\\d+");
	auto numbers = [](const QString &s) {
		QList<qlonglong> out;
		auto it = num.globalMatch(s);
		while(it.hasNext())
			out.append(it.next().captured(0).toLongLong());
		return out;
	};
	const auto na = numbers(a), nb = numbers(b);
	for(int i = 0; i < qMax(na.size(), nb.size()); i++)
	{
		const qlonglong x = i < na.size() ? na[i] : 0;
		const qlonglong y = i < nb.size() ? nb[i] : 0;
		if(x != y)
			return x > y;
	}
	return false;
}

bool Updater::canSelfUpdate()
{
#ifdef Q_OS_WIN
	if(qEnvironmentVariableIsSet("NIMBUS_NO_UPDATE"))
		return false;
	// A packaged build carries its Qt DLLs; a build-tree exe doesn't and must not overwrite itself
	return QFileInfo::exists(QDir(QCoreApplication::applicationDirPath()).filePath("Qt6Core.dll"));
#else
	return false;
#endif
}

void Updater::setState(const QString &s, const QString &err)
{
	state_ = s;
	error_ = err;
	emit changed();
}

void Updater::check()
{
	if(state_ == "unsupported" || state_ == "checking" || state_ == "downloading" || state_ == "ready" || state_ == "available")
		return;
	setState("checking");
	const QUrl url(QStringLiteral("https://api.github.com/repos/%1/releases/latest").arg(APP_UPDATE_REPO));
	QNetworkReply *r = net->get(githubRequest(url));
	connect(r, &QNetworkReply::finished, this, [this, r]() {
		r->deleteLater();
		if(r->error() != QNetworkReply::NoError)
		{
			qCWarning(nimbusUpdate) << "Update check failed:" << r->errorString();
			setState("error", r->errorString());
			return;
		}
		const QJsonObject rel = QJsonDocument::fromJson(r->readAll()).object();
		const QString tag = rel.value("tag_name").toString();
		latest_tag = tag;
		if(tag.isEmpty() || !isNewer(tag, currentVersion()))
		{
			qCInfo(nimbusUpdate) << "Up to date:" << currentVersion() << "latest" << tag;
			setState("uptodate");
			return;
		}
		release_url = rel.value("html_url").toString();
		if(!canSelfUpdate())
		{
			qCInfo(nimbusUpdate) << "Update available:" << tag << "- download it from" << release_url;
			setState("available");
			return;
		}
		QString asset_url;
		for(const QJsonValue &v : rel.value("assets").toArray())
		{
			const QJsonObject a = v.toObject();
			const QString name = a.value("name").toString();
			if(name.startsWith(APP_UPDATE_ASSET_PREFIX) && name.endsWith(".zip"))
			{
				asset_url = a.value("browser_download_url").toString();
				break;
			}
		}
		if(asset_url.isEmpty())
		{
			setState("error", tr("Release %1 has no Windows download").arg(tag));
			return;
		}
		qCInfo(nimbusUpdate) << "Update available:" << tag << "- downloading";
		download(asset_url, tag);
	});
}

void Updater::download(const QString &url, const QString &tag)
{
	QDir().mkpath(updateDir());
	zip_path = QDir(updateDir()).filePath(QStringLiteral("NimbusRemote-%1.zip").arg(tag));
	file = new QFile(zip_path + ".part", this);
	if(!file->open(QIODevice::WriteOnly | QIODevice::Truncate))
	{
		setState("error", tr("Can't write %1").arg(file->fileName()));
		file->deleteLater();
		file = nullptr;
		return;
	}
	progress_ = 0.0;
	setState("downloading");
	QNetworkRequest req = githubRequest(QUrl(url));
	req.setRawHeader("Accept", "application/octet-stream");
	req.setTransferTimeout(120000);
	reply = net->get(req);
	connect(reply, &QNetworkReply::readyRead, this, [this]() {
		if(file && reply)
			file->write(reply->readAll());
	});
	connect(reply, &QNetworkReply::downloadProgress, this, [this](qint64 got, qint64 total) {
		if(total > 0)
		{
			progress_ = double(got) / double(total);
			emit changed();
		}
	});
	connect(reply, &QNetworkReply::finished, this, [this]() {
		QNetworkReply *r = reply;
		reply = nullptr;
		r->deleteLater();
		if(file)
		{
			file->write(r->readAll());
			file->close();
		}
		const QString part = file ? file->fileName() : QString();
		if(file)
		{
			file->deleteLater();
			file = nullptr;
		}
		if(r->error() != QNetworkReply::NoError)
		{
			QFile::remove(part);
			qCWarning(nimbusUpdate) << "Update download failed:" << r->errorString();
			setState("error", r->errorString());
			return;
		}
		QFile::remove(zip_path);
		if(!QFile::rename(part, zip_path))
		{
			setState("error", tr("Can't save the update"));
			return;
		}
		progress_ = 1.0;
		qCInfo(nimbusUpdate) << "Update downloaded to" << zip_path;
		setState("ready");
	});
}

bool Updater::launchInstaller(bool restart)
{
	if(state_ != "ready" || installer_launched)
		return false;
	const QString script = QDir(updateDir()).filePath("install-update.ps1");
	QFile f(script);
	if(!f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
	{
		setState("error", tr("Can't write the installer"));
		return false;
	}
	f.write(installer_script);
	f.close();
	const QString app_dir = QDir::toNativeSeparators(QCoreApplication::applicationDirPath());
	const QStringList args = {
		"-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
		"-File", QDir::toNativeSeparators(script),
		"-AppPid", QString::number(QCoreApplication::applicationPid()),
		"-Zip", QDir::toNativeSeparators(zip_path),
		"-AppDir", app_dir,
		"-Restart", restart ? "1" : "0",
	};
	// Full path: PATH can be trimmed (some launchers do), and then "powershell.exe" isn't found
	QString powershell = qEnvironmentVariable("SystemRoot", "C:\\Windows") + "\\System32\\WindowsPowerShell\\v1.0\\powershell.exe";
	if(!QFileInfo::exists(powershell))
		powershell = "powershell.exe";
	if(!QProcess::startDetached(powershell, args))
	{
		qCWarning(nimbusUpdate) << "Couldn't start the update installer" << powershell;
		setState("error", tr("Couldn't start the installer"));
		return false;
	}
	installer_launched = true;
	qCInfo(nimbusUpdate) << "Installer started for" << latest_tag << (restart ? "(restart)" : "(on exit)");
	return true;
}

void Updater::installAndRestart()
{
	if(launchInstaller(true))
		QCoreApplication::quit();
}

void Updater::installOnExitIfReady()
{
	launchInstaller(false);
}
