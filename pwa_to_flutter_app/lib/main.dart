import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart'; // إضافة OneSignal

import 'webview_popup.dart';
import 'constants.dart';
import 'util.dart';

Future main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // إعداد OneSignal
  OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
  OneSignal.initialize("e542557c-fbed-4ca6-96fa-0b37e0d21490");
  OneSignal.Notifications.requestPermission(true);

  if (!kIsWeb && kDebugMode && defaultTargetPlatform == TargetPlatform.android) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(kDebugMode);
  }
  runApp(const MaterialApp(home: MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? webViewController;

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
    setupOneSignalListeners();
  }

  void setupOneSignalListeners() {
    // الاستماع للنقر على الإشعار أو أزرار الإشعار (مثل زر قبول)
    OneSignal.Notifications.addClickListener((event) {
      final actionId = event.result.actionId;
      // إذا ضغط السائق على زر قبول في الإشعار
      if (actionId == "accept") {
        webViewController?.loadUrl(
          urlRequest: URLRequest(url: WebUri("https://driver.zoonasd.com/accept-ride.html"))
        );
      }
    });
  }

  InAppWebViewSettings sharedSettings = InAppWebViewSettings(
      supportMultipleWindows: true,
      javaScriptCanOpenWindowsAutomatically: true,
      applicationNameForUserAgent: 'Tirhal Driver App',
      userAgent: 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/107.0.5304.105 Mobile Safari/537.36',
      disableDefaultErrorPage: true,
      allowsInlineMediaPlayback: true, // مهم للصوت
      limitsNavigationsToAppBoundDomains: true);

  @override
  void dispose() {
    webViewController = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb) {
      if (webViewController != null && defaultTargetPlatform == TargetPlatform.android) {
        if (state == AppLifecycleState.paused) {
          pauseAll();
        } else {
          resumeAll();
        }
      }
    }
  }

  void pauseAll() {
    if (defaultTargetPlatform == TargetPlatform.android) { webViewController?.pause(); }
    webViewController?.pauseTimers();
  }

  void resumeAll() {
    if (defaultTargetPlatform == TargetPlatform.android) { webViewController?.resume(); }
    webViewController?.resumeTimers();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final controller = webViewController;
        if (controller != null) {
          if (await controller.canGoBack()) {
            controller.goBack();
            return false;
          }
        }
        return true;
      },
      child: Scaffold(
          appBar: AppBar(toolbarHeight: 0),
          body: Column(children: <Widget>[
            Expanded(
              child: Stack(
                children: [
                  FutureBuilder<bool>(
                    future: isNetworkAvailable(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return Container();
                      final bool networkAvailable = snapshot.data ?? false;
                      final cacheMode = networkAvailable ? CacheMode.LOAD_DEFAULT : CacheMode.LOAD_CACHE_ELSE_NETWORK;
                      final webViewInitialSettings = sharedSettings.copy();
                      webViewInitialSettings.cacheMode = cacheMode;

                      return InAppWebView(
                        key: webViewKey,
                        initialUrlRequest: URLRequest(url: WebUri("https://r.zoonasd.com/")),
                        initialSettings: webViewInitialSettings,
                        onWebViewCreated: (controller) {
                          webViewController = controller;
                        },
                        shouldOverrideUrlLoading: (controller, navigationAction) async {
                          final uri = navigationAction.request.url;
                          if (uri != null && navigationAction.isForMainFrame && 
                              uri.host != "driver.zoonasd.com" && await canLaunchUrl(uri)) {
                            launchUrl(uri);
                            return NavigationActionPolicy.CANCEL;
                          }
                          return NavigationActionPolicy.ALLOW;
                        },
                        onCreateWindow: (controller, createWindowAction) async {
                          showDialog(
                            context: context,
                            builder: (context) {
                              final popupWebViewSettings = sharedSettings.copy();
                              popupWebViewSettings.supportMultipleWindows = false;
                              return WebViewPopup(
                                  createWindowAction: createWindowAction,
                                  popupWebViewSettings: popupWebViewSettings);
                            },
                          );
                          return true;
                        },
                      );
                    },
                  )
                ],
              ),
            ),
          ])),
    );
  }
}
