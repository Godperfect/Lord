import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:get/get.dart';

import 'package:namida/class/route.dart';
import 'package:namida/controller/current_color.dart';
import 'package:namida/controller/folders_controller.dart';
import 'package:namida/controller/miniplayer_controller.dart';
import 'package:namida/controller/scroll_search_controller.dart';
import 'package:namida/controller/settings_controller.dart';
import 'package:namida/core/constants.dart';
import 'package:namida/core/dimensions.dart';
import 'package:namida/core/enums.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/namida_converter_ext.dart';
import 'package:namida/core/themes.dart';
import 'package:namida/core/translations/language.dart';
import 'package:namida/packages/inner_drawer.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';

class NamidaNavigator {
  static NamidaNavigator get inst => _instance;
  static final NamidaNavigator _instance = NamidaNavigator._internal();
  NamidaNavigator._internal();

  final navKey = Get.nestedKey(1);

  final RxList<NamidaRoute> currentWidgetStack = <NamidaRoute>[].obs;
  NamidaRoute? get currentRoute => currentWidgetStack.lastOrNull;
  int _currentDialogNumber = 0;
  int _currentMenusNumber = 0;

  final GlobalKey<InnerDrawerState> innerDrawerKey = GlobalKey<InnerDrawerState>();
  final heroController = HeroController();

  Future<T?> showMenu<T>(Future? menuFunction) async {
    _currentMenusNumber++;
    _printMenus();
    return await menuFunction;
  }

  void popMenu({bool handleClosing = true}) {
    if (_currentMenusNumber > 0) {
      _currentMenusNumber--;
      if (handleClosing) {
        Get.close(1);
      }
    }
    _printMenus();
  }

  void popAllMenus() {
    if (_currentMenusNumber > 0) {
      Get.close(_currentMenusNumber);
      _currentMenusNumber = 0;
    }
    _printMenus();
  }

  void toggleDrawer() {
    innerDrawerKey.currentState?.toggle();
  }

  void _hideSearchMenuAndUnfocus() => ScrollSearchController.inst.hideSearchMenu();
  void _minimizeMiniplayer() => MiniPlayerController.inst.snapToMini();

  void _hideEverything() {
    _hideSearchMenuAndUnfocus();
    _minimizeMiniplayer();
    closeAllDialogs();
  }

  void onFirstLoad() {
    final initialTab = settings.selectedLibraryTab.value;
    navigateTo(initialTab.toWidget(), durationInMs: 0);
    Dimensions.inst.updateAllTileDimensions();
  }

  Future<void> toggleFullScreen(Widget widget, {bool setOrientations = true, Future<void> Function()? onWillPop}) async {
    if (_isInFullScreen) {
      await exitFullScreen(setOrientations: setOrientations);
    } else {
      await enterFullScreen(widget, setOrientations: setOrientations, onWillPop: onWillPop);
    }
  }

  Future<void> _setOrientations(List<DeviceOrientation> orientations) async {
    await SystemChrome.setPreferredOrientations(orientations);
  }

  bool get isInFullScreen => _isInFullScreen;
  bool _isInFullScreen = false;
  Future<void> enterFullScreen(Widget widget, {bool setOrientations = true, Future<void> Function()? onWillPop}) async {
    if (_isInFullScreen) return;

    _isInFullScreen = true;

    Get.to(
      () => WillPopScope(
        onWillPop: () async {
          if (onWillPop != null) await onWillPop();
          exitFullScreen();
          return false;
        },
        child: widget,
      ),
      id: null,
      preventDuplicates: true,
      transition: Transition.noTransition,
      curve: Curves.easeOut,
      duration: Duration.zero,
      opaque: true,
      fullscreenDialog: false,
    );
    if (setOrientations) {
      await Future.wait([
        _setOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]),
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
      ]);
    }
  }

  Future<void> exitFullScreen({bool setOrientations = true}) async {
    if (!_isInFullScreen) return;
    Get.close(1);
    if (setOrientations) {
      await Future.wait([
        _setOrientations(kDefaultOrientations),
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values),
      ]);
    }
    _isInFullScreen = false;
  }

  Future<void> navigateTo(
    Widget page, {
    bool nested = true,
    Transition transition = Transition.cupertino,
    int durationInMs = 500,
  }) async {
    currentWidgetStack.add(page.toNamidaRoute());
    _hideEverything();

    currentRoute?.updateColorScheme();

    await Get.to(
      () => page,
      id: nested ? 1 : null,
      preventDuplicates: false,
      transition: transition,
      curve: Curves.easeOut,
      duration: Duration(milliseconds: durationInMs),
      opaque: true,
      fullscreenDialog: false,
    );
  }

  /// Use [dialogBuilder] in case you want to acess the theme generated by [colorScheme].
  Future<void> navigateDialog({
    Widget? dialog,
    Widget Function(ThemeData theme)? dialogBuilder,
    int durationInMs = 300,
    bool tapToDismiss = true,
    FutureOr<void> Function()? onDismissing,
    Color? colorScheme,
    bool lighterDialogColor = true,
    double scale = 0.96,
    bool blackBg = false,
  }) async {
    final rootNav = navigator;
    if (rootNav == null) return;

    ScrollSearchController.inst.unfocusKeyboard();
    _currentDialogNumber++;

    Future<bool> onWillPop() async {
      if (!tapToDismiss) return false;
      if (onDismissing != null) await onDismissing();

      if (_currentDialogNumber > 0) {
        closeDialog();
        return false;
      }

      return true;
    }

    final theme = AppThemes.inst.getAppTheme(colorScheme, null, lighterDialogColor);

    await Get.to(
      () => WillPopScope(
        onWillPop: onWillPop,
        child: GestureDetector(
          onTap: onWillPop,
          child: NamidaBgBlur(
            blur: 5.0,
            enabled: _currentDialogNumber == 1,
            child: Container(
              color: Colors.black.withOpacity(blackBg ? 1.0 : 0.45),
              child: Transform.scale(
                scale: scale,
                child: Theme(
                  data: theme,
                  child: dialogBuilder == null ? dialog! : dialogBuilder(theme),
                ),
              ),
            ),
          ),
        ),
      ),
      duration: Duration(milliseconds: durationInMs),
      preventDuplicates: false,
      opaque: false,
      fullscreenDialog: true,
      transition: Transition.fade,
    );

    _printDialogs();
  }

  Future<void> closeDialog([int count = 1]) async {
    if (_currentDialogNumber == 0) return;
    final closeCount = count.withMaximum(_currentDialogNumber);
    _currentDialogNumber -= closeCount;
    Get.close(closeCount);
    _printDialogs();
  }

  Future<void> closeAllDialogs() async {
    closeDialog(_currentDialogNumber);
    _printDialogs();
  }

  void _printDialogs() => printy("Current Dialogs: $_currentDialogNumber");
  void _printMenus() => printy("Current Menus: $_currentMenusNumber");

  Future<void> navigateOff(
    Widget page, {
    bool nested = true,
    Transition transition = Transition.cupertino,
    int durationInMs = 500,
  }) async {
    currentWidgetStack.removeLast();
    currentWidgetStack.add(page.toNamidaRoute());
    _hideEverything();

    currentRoute?.updateColorScheme();

    await Get.off(
      () => page,
      id: nested ? 1 : null,
      preventDuplicates: false,
      transition: transition,
      curve: Curves.easeOut,
      duration: Duration(milliseconds: durationInMs),
      opaque: true,
      fullscreenDialog: false,
    );
  }

  Future<void> navigateOffAll(
    Widget page, {
    bool nested = true,
    Transition transition = Transition.cupertino,
  }) async {
    currentWidgetStack
      ..clear()
      ..add(page.toNamidaRoute());
    _hideEverything();

    currentRoute?.updateColorScheme();

    await Get.offAll(
      () => page,
      id: nested ? 1 : null,
      transition: transition,
      curve: Curves.easeOut,
      duration: const Duration(milliseconds: 500),
    );
  }

  Future<void> popPage() async {
    if (innerDrawerKey.currentState?.isOpened ?? false) {
      innerDrawerKey.currentState?.close();
      return;
    }
    if (ScrollSearchController.inst.isGlobalSearchMenuShown.value) {
      _hideSearchMenuAndUnfocus();
      return;
    }

    if (currentRoute?.route == RouteType.PAGE_folders) {
      final canIgoBackPls = Folders.inst.onBackButton();
      if (!canIgoBackPls) return;
    }

    // pop only if not in root, otherwise show _doubleTapToExit().
    if (currentWidgetStack.length > 1) {
      currentWidgetStack.removeLast();
      navKey?.currentState?.pop();
    } else {
      await _doubleTapToExit();
    }
    currentRoute?.updateColorScheme();
    _hideSearchMenuAndUnfocus();
  }

  DateTime _currentBackPressTime = DateTime(0);
  Future<bool> _doubleTapToExit() async {
    final now = DateTime.now();
    if (now.difference(_currentBackPressTime) > const Duration(seconds: 3)) {
      _currentBackPressTime = now;

      final tcolor = Color.alphaBlend(CurrentColor.inst.color.withAlpha(50), Get.textTheme.displayMedium!.color!);
      Get.showSnackbar(
        GetSnackBar(
          messageText: Text(
            lang.EXIT_APP_SUBTITLE,
            style: Get.textTheme.displayMedium?.copyWith(color: tcolor),
          ),
          icon: Icon(
            Broken.logout,
            color: tcolor,
          ),
          shouldIconPulse: false,
          snackPosition: SnackPosition.BOTTOM,
          snackStyle: SnackStyle.FLOATING,
          borderRadius: 14.0.multipliedRadius,
          backgroundColor: Colors.grey.withOpacity(0.2),
          barBlur: 10.0,
          // dismissDirection: DismissDirection.none,
          margin: const EdgeInsets.all(8.0),
          animationDuration: const Duration(milliseconds: 300),
          forwardAnimationCurve: Curves.fastLinearToSlowEaseIn,
          reverseAnimationCurve: Curves.easeInOutQuart,
          duration: const Duration(seconds: 3),
          snackbarStatus: (status) {
            // -- resets time
            if (status == SnackbarStatus.CLOSED) {
              _currentBackPressTime = DateTime(0);
            }
          },
        ),
      );
      return false;
    }
    SystemNavigator.pop();
    return true;
  }
}
