package app.alextran.immich

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.ext.SdkExtensions
import android.provider.Settings
import app.alextran.immich.background.BackgroundEngineLock
import app.alextran.immich.background.BackgroundWorkerApiImpl
import app.alextran.immich.background.BackgroundWorkerFgHostApi
import app.alextran.immich.background.BackgroundWorkerLockApi
import app.alextran.immich.connectivity.ConnectivityApi
import app.alextran.immich.connectivity.ConnectivityApiImpl
import app.alextran.immich.core.HttpClientManager
import app.alextran.immich.core.ImmichPlugin
import app.alextran.immich.core.NetworkApiPlugin
import me.albemala.native_video_player.NativeVideoPlayerPlugin
import app.alextran.immich.images.LocalImageApi
import app.alextran.immich.images.LocalImagesImpl
import app.alextran.immich.images.RemoteImageApi
import app.alextran.immich.images.RemoteImagesImpl
import app.alextran.immich.passkey.PasskeyPlugin
import app.alextran.immich.permission.PermissionApi
import app.alextran.immich.permission.PermissionApiImpl
import app.alextran.immich.sync.NativeSyncApi
import app.alextran.immich.sync.NativeSyncApiImpl26
import app.alextran.immich.sync.NativeSyncApiImpl30
import app.alextran.immich.viewintent.ViewIntentPlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
  private var installReceiver: BroadcastReceiver? = null
  private val io = Executors.newSingleThreadExecutor()
  private lateinit var updateChannel: MethodChannel

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    registerPlugins(this, flutterEngine)
    flutterEngine.plugins.add(PasskeyPlugin())

    updateChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "online.isosmart.photos/native")
    updateChannel.setMethodCallHandler { call, result ->
      when (call.method) {
        "canInstall" -> result.success(packageManager.canRequestPackageInstalls())
        "openInstallSettings" -> {
          startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
          result.success(null)
        }
        "installApk" -> {
          listenForInstall()
          val path = call.argument<String>("path") ?: run {
            result.error("invalid_arg", "missing apk path", null)
            return@setMethodCallHandler
          }
          val sha = call.argument<String>("sha256")
          io.execute {
            try {
              install(File(path), sha)
              runOnUiThread { result.success(null) }
            } catch (e: Exception) {
              runOnUiThread { result.error("install_error", e.message, null) }
            }
          }
        }
        else -> result.notImplemented()
      }
    }
  }

  private fun install(apk: File, sha256: String?) {
    val installer = packageManager.packageInstaller
    val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
    params.setAppPackageName(packageName)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
    }
    val id = installer.createSession(params)
    val session = installer.openSession(id)
    try {
      val md = MessageDigest.getInstance("SHA-256")
      session.openWrite("app.apk", 0, apk.length()).use { out ->
        apk.inputStream().use { input ->
          val buf = ByteArray(1 shl 16)
          while (true) {
            val n = input.read(buf)
            if (n < 0) break
            md.update(buf, 0, n)
            out.write(buf, 0, n)
          }
        }
        session.fsync(out)
      }
      val hex = md.digest().joinToString("") { "%02x".format(it) }
      if (!sha256.isNullOrEmpty() && !hex.equals(sha256, ignoreCase = true)) {
        throw IllegalStateException("damaged download")
      }
      val intent = Intent(INSTALL_ACTION).setPackage(packageName)
      val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
      session.commit(PendingIntent.getBroadcast(this, id, intent, flags).intentSender)
      session.close()
    } catch (e: Exception) {
      try {
        session.abandon()
      } catch (_: Exception) {}
      throw e
    }
  }

  private fun listenForInstall() {
    if (installReceiver != null) return
    val receiver = object : BroadcastReceiver() {
      override fun onReceive(context: Context, intent: Intent) {
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
          PackageInstaller.STATUS_PENDING_USER_ACTION -> {
            @Suppress("DEPRECATION")
            val confirm = if (Build.VERSION.SDK_INT >= 33)
              intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
            else intent.getParcelableExtra(Intent.EXTRA_INTENT)
            confirm?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            confirm?.let { startActivity(it) }
            updateChannel.invokeMethod("installStatus", "confirm")
          }
          PackageInstaller.STATUS_SUCCESS -> updateChannel.invokeMethod("installStatus", "done")
          else -> {
            val msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "status $status"
            updateChannel.invokeMethod("installStatus", "failed: $msg")
          }
        }
      }
    }
    val filter = IntentFilter(INSTALL_ACTION)
    if (Build.VERSION.SDK_INT >= 33) registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
    else @Suppress("UnspecifiedRegisterReceiverFlag") registerReceiver(receiver, filter)
    installReceiver = receiver
  }

  override fun onDestroy() {
    installReceiver?.let { unregisterReceiver(it) }
    installReceiver = null
    io.shutdown()
    super.onDestroy()
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
  }

  companion object {
    private const val INSTALL_ACTION = "online.isosmart.photos.INSTALL_STATUS"

    fun registerPlugins(ctx: Context, flutterEngine: FlutterEngine) {
      HttpClientManager.initialize(ctx)
      NativeVideoPlayerPlugin.dataSourceFactory = HttpClientManager::createDataSourceFactory
      flutterEngine.plugins.add(NetworkApiPlugin())

      val messenger = flutterEngine.dartExecutor.binaryMessenger
      val backgroundEngineLockImpl = BackgroundEngineLock(ctx)
      BackgroundWorkerLockApi.setUp(messenger, backgroundEngineLockImpl)
      val nativeSyncApiImpl =
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) < 1) {
          NativeSyncApiImpl26(ctx)
        } else {
          NativeSyncApiImpl30(ctx)
        }
      val permissionApiImpl = PermissionApiImpl(ctx)
      NativeSyncApi.setUp(messenger, nativeSyncApiImpl)
      PermissionApi.setUp(messenger, permissionApiImpl)
      LocalImageApi.setUp(messenger, LocalImagesImpl(ctx))
      RemoteImageApi.setUp(messenger, RemoteImagesImpl(ctx))

      BackgroundWorkerFgHostApi.setUp(messenger, BackgroundWorkerApiImpl(ctx))
      ConnectivityApi.setUp(messenger, ConnectivityApiImpl(ctx))

      flutterEngine.plugins.add(ViewIntentPlugin())
      flutterEngine.plugins.add(backgroundEngineLockImpl)
      flutterEngine.plugins.add(nativeSyncApiImpl)
      flutterEngine.plugins.add(permissionApiImpl)
    }

    fun cancelPlugins(flutterEngine: FlutterEngine) {
      val nativeApi =
        flutterEngine.plugins.get(NativeSyncApiImpl26::class.java) as ImmichPlugin?
          ?: flutterEngine.plugins.get(NativeSyncApiImpl30::class.java) as ImmichPlugin?
      nativeApi?.detachFromEngine()
      val permissionApi = flutterEngine.plugins.get(PermissionApiImpl::class.java) as ImmichPlugin?
      permissionApi?.detachFromEngine()
    }
  }
}
