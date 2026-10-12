import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/services/logging/logger.dart';

/// Android TV / Google TV adaptation.
///
/// The app is built from touch-first Material widgets, and Flutter's focus
/// system already moves between them with arrow keys — that part needs no
/// work. Two things are missing on a TV, and both live here:
///
///  * Hardware reports a *different* confirm key than a keyboard. A remote's OK
///    button arrives as [LogicalKeyboardKey.enter] on most set-top hardware and
///    [LogicalKeyboardKey.select] on others, and Flutter's default shortcut map
///    does not bind every variant.
///  * Nothing is scaled for viewing distance. A 65" panel read from across a
///    room needs larger type than the phone-sized text this app is tuned for.
///
/// Everything here is inert on a phone or tablet: the shortcuts only fire when
/// a remote key arrives, and the text scale only applies once the platform
/// reports leanback.
class TvEnvironment {
  const TvEnvironment._(this.isTv, this.textScale);

  /// True on Android TV / Google TV, where input comes from a D-pad rather
  /// than a touchscreen. Always false elsewhere.
  final bool isTv;

  /// Multiplier applied to [MediaQuery.textScaler].
  ///
  /// 1.3 lifts labels clear of the noise floor without disturbing the
  /// layouts, which are flexible enough to absorb it.
  final double textScale;

  static const TvEnvironment mobile = TvEnvironment._(false, 1.0);
  static const TvEnvironment television = TvEnvironment._(true, 1.3);

  static const MethodChannel _channel =
      MethodChannel('com.predidit.kazumi/intent');

  static TvEnvironment _current = mobile;

  /// The environment resolved at startup. Readable before [load] completes —
  /// it falls back to [mobile] until then.
  static TvEnvironment get current => _current;

  /// Asks the platform whether this device declares leanback.
  ///
  /// Feature detection beats a size/orientation heuristic here. A large tablet
  /// in landscape looks like a TV but has a touchscreen, and scaling its text
  /// would be wrong; leanback is the exact property the launcher keys off.
  static Future<TvEnvironment> load() async {
    if (!Platform.isAndroid) {
      return _current = mobile;
    }
    try {
      final isTv = await _channel.invokeMethod<bool>('isLeanback') ?? false;
      return _current = isTv ? television : mobile;
    } catch (e) {
      // A missing channel must never break startup on a phone.
      KazumiLogger().w('Tv: leanback probe failed', error: e);
      return _current = mobile;
    }
  }
}

/// Remote keys that mean "confirm", mapped to [ButtonActivateIntent].
///
/// [ButtonActivateIntent] is the *key press* intent; the framework's own action
/// turns it into [ActivateIntent] on whichever node holds focus, which is what
/// Buttons, ListTiles and InkWells listen for. Binding to [ActivateIntent]
/// directly would re-enter that same action and recurse.
///
/// [LogicalKeyboardKey.enter] and [LogicalKeyboardKey.space] are already bound
/// by `WidgetsApp`, and are listed here so a remote reporting either works even
/// if a future Flutter release drops the default.
const Map<ShortcutActivator, Intent> _tvConfirmShortcuts =
    <ShortcutActivator, Intent>{
  LogicalKeyboardKey.select: ButtonActivateIntent(),
  LogicalKeyboardKey.numpadEnter: ButtonActivateIntent(),
  LogicalKeyboardKey.enter: ButtonActivateIntent(),
  LogicalKeyboardKey.space: ButtonActivateIntent(),
};

/// Binds a TV remote's confirm key across its hardware variants.
///
/// Install through `MaterialApp.router`'s `builder`, which places this above
/// the [Navigator] and below the app's own overlays.
class TvShortcuts extends StatelessWidget {
  const TvShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Phones keep the stock map untouched — space and enter are ordinary
    // typing keys there.
    if (!TvScope.of(context).isTv) return child;

    return Shortcuts(shortcuts: _tvConfirmShortcuts, child: child);
  }
}

/// Enlarges text for ten-foot viewing.
class TvTextScale extends StatelessWidget {
  const TvTextScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final environment = TvScope.of(context);
    if (!environment.isTv) return child;

    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        textScaler: TextScaler.linear(environment.textScale),
      ),
      child: child,
    );
  }
}

/// Publishes the resolved [TvEnvironment] to the subtree.
class TvScope extends InheritedWidget {
  const TvScope({
    super.key,
    required this.environment,
    required super.child,
  });

  final TvEnvironment environment;

  static TvEnvironment of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TvScope>();
    return scope?.environment ?? TvEnvironment.current;
  }

  @override
  bool updateShouldNotify(TvScope oldWidget) =>
      environment != oldWidget.environment;
}

/// Folds the TV layers into one widget so the wiring in `app_widget.dart`
/// stays to a single line.
class TvSupport extends StatelessWidget {
  const TvSupport({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!TvScope.of(context).isTv) return child;
    return TvTextScale(
      child: TvShortcuts(child: child),
    );
  }
}
